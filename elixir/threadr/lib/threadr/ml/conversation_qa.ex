defmodule Threadr.ML.ConversationQA do
  @moduledoc """
  Conversation-centric QA for actor-pair questions grounded in reconstructed conversations.
  """

  import Ecto.Query

  alias Threadr.ControlPlane

  alias Threadr.ML.{
    ActorReference,
    ChannelLabel,
    ConversationQAIntent,
    Generation,
    GenerationProviderOpts,
    ReconstructionQuery,
    SemanticQA
  }

  alias Threadr.Repo

  @default_limit 5
  @max_support_messages 3

  def answer_question(tenant_subject_name, question, opts \\ [])
      when is_binary(tenant_subject_name) and is_binary(question) do
    with {:ok, tenant} <-
           ControlPlane.get_tenant_by_subject_name(tenant_subject_name, context: %{system: true}),
         {:ok, intent} <- ConversationQAIntent.classify(question),
         {:ok, actor} <- resolve_actor_reference(tenant.schema_name, intent.actor_ref, opts),
         {:ok, target_actor} <-
           resolve_actor_reference(tenant.schema_name, intent.target_ref, opts),
         shared_conversations when shared_conversations != [] <-
           fetch_shared_conversations(tenant.schema_name, actor, target_actor, opts) do
      build_answer(tenant, question, intent, actor, target_actor, shared_conversations, opts)
    else
      [] -> {:error, :not_conversation_question}
      {:error, {:actor_not_found, _actor_ref}} -> {:error, :not_conversation_question}
      {:error, {:ambiguous_actor, _actor_ref, _matches}} -> {:error, :not_conversation_question}
      {:error, :not_conversation_question} = error -> error
    end
  end

  defp build_answer(tenant, question, intent, actor, target_actor, conversations, opts) do
    citations = build_citations(tenant.schema_name, conversations)
    context = build_conversation_context(question, actor, target_actor, conversations, citations)

    with {:ok, answer} <- Generation.answer_question(question, context, generation_opts(opts)) do
      {:ok,
       %{
         tenant_subject_name: tenant.subject_name,
         tenant_schema: tenant.schema_name,
         question: question,
         query: %{
           mode: "conversation_qa",
           kind: intent.kind,
           actor_handle: actor.handle,
           target_actor_handle: target_actor.handle,
           retrieval: "reconstructed_conversations",
           shared_conversation_count: length(conversations),
           evidence_count: length(citations)
         },
         conversations: conversations,
         citations: citations,
         facts_over_time: [],
         context: context,
         answer: answer
       }}
    end
  end

  defp fetch_shared_conversations(tenant_schema, actor, target_actor, opts) do
    limit = conversation_limit(opts)

    from(c in "conversations",
      join: cm1 in "conversation_memberships",
      on: cm1.conversation_id == c.id and cm1.member_kind == "actor",
      join: cm2 in "conversation_memberships",
      on: cm2.conversation_id == c.id and cm2.member_kind == "actor",
      join: ch in "channels",
      on: ch.id == c.channel_id,
      where: cm1.member_id == ^actor.id and cm2.member_id == ^target_actor.id,
      order_by: [desc: c.last_message_at, desc: c.opened_at],
      limit: ^limit,
      select: %{
        conversation_id: c.id,
        channel_name: ch.name,
        opened_at: c.opened_at,
        last_message_at: c.last_message_at,
        open_pending_item_count: c.open_pending_item_count,
        topic_summary: c.topic_summary,
        participant_summary: c.participant_summary,
        entity_summary: c.entity_summary,
        metadata: c.metadata
      }
    )
    |> apply_conversation_time_bounds(opts)
    |> ReconstructionQuery.all(tenant_schema)
    |> Enum.map(&normalize_conversation/1)
    |> Enum.uniq_by(& &1.conversation_id)
    |> Enum.map(fn conversation ->
      Map.put(
        conversation,
        :summary_text,
        get_in(conversation, [:metadata, "conversation_summary", "text"])
      )
    end)
  end

  def build_citations(tenant_schema, conversations)
      when is_binary(tenant_schema) and is_list(conversations) do
    conversation_ids = Enum.map(conversations, & &1.conversation_id)

    support_messages_by_conversation =
      supporting_messages_by_conversation(tenant_schema, conversation_ids)

    selected_messages =
      conversations
      |> Enum.flat_map(fn conversation ->
        support_messages_by_conversation
        |> Map.get(conversation.conversation_id, [])
        |> pick_support_messages()
        |> Enum.map(&Map.put(&1, :conversation_id, conversation.conversation_id))
      end)
      |> Enum.uniq_by(& &1.message_id)

    entities_by_message =
      fetch_entities_by_message(tenant_schema, Enum.map(selected_messages, & &1.message_id))

    facts_by_message =
      fetch_facts_by_message(tenant_schema, Enum.map(selected_messages, & &1.message_id))

    selected_messages
    |> Enum.with_index(1)
    |> Enum.map(fn {message, index} ->
      %{
        label: "C#{index}",
        rank: index,
        message_id: message.message_id,
        external_id: message.external_id,
        body: message.body,
        observed_at: message.observed_at,
        actor_handle: message.actor_handle,
        actor_display_name: message.actor_display_name,
        channel_name: message.channel_name,
        similarity: 1.0,
        conversation_id: message.conversation_id,
        extracted_entities: Map.get(entities_by_message, message.message_id, []),
        extracted_facts: Map.get(facts_by_message, message.message_id, [])
      }
    end)
  end

  defp build_conversation_context(question, actor, target_actor, conversations, citations) do
    header_lines = [
      "Conversation-focused QA for what #{actor.handle} talked about with #{target_actor.handle}.",
      "Question: #{question}",
      "Evidence retrieval: reconstructed_conversations; shared_conversations=#{length(conversations)}; supporting_messages=#{length(citations)}."
    ]

    citation_labels_by_conversation =
      citations
      |> Enum.group_by(& &1.conversation_id, & &1.label)

    conversation_lines =
      conversations
      |> Enum.with_index(1)
      |> Enum.map(fn {conversation, index} ->
        labels =
          conversation.conversation_id
          |> then(&Map.get(citation_labels_by_conversation, &1, []))
          |> Enum.join(", ")

        [
          "[Conversation #{index}] #{time_window_label(conversation)} in #{ChannelLabel.format(conversation.channel_name)}",
          "Topic: #{conversation.topic_summary || fallback_topic(conversation)}",
          "Summary: #{conversation.summary_text || fallback_summary(conversation)}",
          "Open pending items: #{conversation.open_pending_item_count}",
          if(labels == "", do: nil, else: "Supporting citations: #{labels}")
        ]
        |> Enum.reject(&blank?/1)
        |> Enum.join("\n")
      end)

    evidence =
      case citations do
        [] -> ""
        rows -> SemanticQA.build_context(rows)
      end

    Enum.join(header_lines ++ conversation_lines ++ blankable(evidence), "\n\n")
  end

  defp supporting_messages_by_conversation(_tenant_schema, []), do: %{}

  defp supporting_messages_by_conversation(tenant_schema, conversation_ids) do
    dumped_ids = Enum.map(conversation_ids, &dump_uuid!/1)

    from(cm in "conversation_memberships",
      join: m in "messages",
      on: m.id == type(cm.member_id, :binary_id),
      join: a in "actors",
      on: a.id == m.actor_id,
      join: ch in "channels",
      on: ch.id == m.channel_id,
      where: cm.conversation_id in ^dumped_ids and cm.member_kind == "message",
      order_by: [asc: m.observed_at, asc: m.id],
      select: %{
        conversation_id: cm.conversation_id,
        message_id: m.id,
        external_id: m.external_id,
        body: m.body,
        observed_at: m.observed_at,
        actor_handle: a.handle,
        actor_display_name: a.display_name,
        channel_name: ch.name
      }
    )
    |> ReconstructionQuery.all(tenant_schema)
    |> Enum.map(fn row ->
      row
      |> Map.update!(:conversation_id, &normalize_identifier/1)
      |> Map.update!(:message_id, &normalize_identifier/1)
      |> Map.update!(:external_id, &normalize_identifier/1)
    end)
    |> Enum.group_by(& &1.conversation_id)
  end

  defp pick_support_messages(messages) when length(messages) <= @max_support_messages,
    do: messages

  defp pick_support_messages(messages) do
    first = List.first(messages)
    second = Enum.at(messages, 1)
    last = List.last(messages)

    [first, second, last]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.message_id)
  end

  defp fallback_topic(conversation) do
    conversation.entity_summary
    |> Map.get("names", [])
    |> List.wrap()
    |> Enum.take(3)
    |> case do
      [] -> "shared conversation"
      names -> Enum.join(names, ", ")
    end
  end

  defp fallback_summary(conversation) do
    participants =
      conversation.participant_summary
      |> Map.get("actor_handles", [])
      |> List.wrap()
      |> Enum.join(", ")

    entities =
      conversation.entity_summary
      |> Map.get("names", [])
      |> List.wrap()
      |> Enum.take(3)
      |> Enum.join(", ")

    "#{participants} discussed #{if(entities == "", do: "shared work", else: entities)}."
  end

  defp time_window_label(conversation) do
    "#{format_timestamp(conversation.opened_at)} -> #{format_timestamp(conversation.last_message_at)}"
  end

  defp normalize_conversation(conversation) do
    conversation
    |> Map.update!(:conversation_id, &normalize_identifier/1)
  end

  defp apply_conversation_time_bounds(query, opts) do
    query
    |> maybe_filter_conversation_since(Keyword.get(opts, :since))
    |> maybe_filter_conversation_until(Keyword.get(opts, :until))
  end

  defp maybe_filter_conversation_since(query, nil), do: query

  defp maybe_filter_conversation_since(query, %NaiveDateTime{} = since) do
    maybe_filter_conversation_since(query, DateTime.from_naive!(since, "Etc/UTC"))
  end

  defp maybe_filter_conversation_since(query, %DateTime{} = since) do
    where(query, [c, _cm1, _cm2, _ch], c.last_message_at >= ^since)
  end

  defp maybe_filter_conversation_until(query, nil), do: query

  defp maybe_filter_conversation_until(query, %NaiveDateTime{} = until) do
    maybe_filter_conversation_until(query, DateTime.from_naive!(until, "Etc/UTC"))
  end

  defp maybe_filter_conversation_until(query, %DateTime{} = until) do
    where(query, [c, _cm1, _cm2, _ch], c.opened_at <= ^until)
  end

  defp fetch_entities_by_message(_tenant_schema, []), do: %{}

  defp fetch_entities_by_message(tenant_schema, message_ids) do
    dumped_ids = Enum.map(message_ids, &dump_uuid!/1)

    from(e in "extracted_entities",
      where: e.source_message_id in ^dumped_ids,
      order_by: [desc: e.confidence, asc: e.name],
      select: %{
        source_message_id: e.source_message_id,
        entity_type: e.entity_type,
        name: e.name,
        canonical_name: e.canonical_name,
        confidence: e.confidence
      }
    )
    |> safe_extraction_query(tenant_schema)
  end

  defp fetch_facts_by_message(_tenant_schema, []), do: %{}

  defp fetch_facts_by_message(tenant_schema, message_ids) do
    dumped_ids = Enum.map(message_ids, &dump_uuid!/1)

    from(f in "extracted_facts",
      where: f.source_message_id in ^dumped_ids,
      order_by: [desc: f.confidence, asc: f.fact_type],
      select: %{
        source_message_id: f.source_message_id,
        fact_type: f.fact_type,
        subject: f.subject,
        predicate: f.predicate,
        object: f.object,
        confidence: f.confidence,
        valid_at: f.valid_at
      }
    )
    |> safe_extraction_query(tenant_schema)
  end

  defp safe_extraction_query(query, tenant_schema) do
    query
    |> Repo.all(prefix: tenant_schema)
    |> Enum.map(&normalize_extracted_map/1)
    |> Enum.group_by(& &1.source_message_id)
  rescue
    error in Postgrex.Error ->
      if missing_extraction_table?(error) do
        %{}
      else
        reraise error, __STACKTRACE__
      end
  end

  defp resolve_actor_reference(tenant_schema, raw_ref, opts) do
    ActorReference.resolve(tenant_schema, raw_ref, opts)
  end

  defp generation_opts(opts), do: GenerationProviderOpts.from_prefixed(opts)

  defp blankable(nil), do: []
  defp blankable(""), do: []
  defp blankable(value), do: [value]

  defp blank?(value), do: value in [nil, ""]

  defp missing_extraction_table?(%Postgrex.Error{postgres: %{code: :undefined_table}}), do: true
  defp missing_extraction_table?(%Postgrex.Error{postgres: %{code: "42P01"}}), do: true
  defp missing_extraction_table?(_error), do: false

  defp normalize_extracted_map(map) do
    map
    |> Enum.map(fn
      {:valid_at, %DateTime{} = value} -> {:valid_at, DateTime.to_iso8601(value)}
      {:valid_at, %NaiveDateTime{} = value} -> {:valid_at, NaiveDateTime.to_iso8601(value)}
      {key, value} -> {key, normalize_identifier(value)}
    end)
    |> Map.new()
  end

  defp normalize_identifier(nil), do: nil

  defp normalize_identifier(value) when is_binary(value) do
    if String.valid?(value) do
      value
    else
      case Ecto.UUID.load(value) do
        {:ok, uuid} -> uuid
        :error -> Base.encode16(value, case: :lower)
      end
    end
  end

  defp normalize_identifier(value), do: to_string(value)

  defp format_timestamp(nil), do: "unknown"
  defp format_timestamp(%DateTime{} = timestamp), do: DateTime.to_iso8601(timestamp)
  defp format_timestamp(%NaiveDateTime{} = timestamp), do: NaiveDateTime.to_iso8601(timestamp)
  defp format_timestamp(value), do: to_string(value)

  defp dump_uuid!(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> Ecto.UUID.dump!(uuid)
      :error -> value
    end
  end

  defp dump_uuid!(value), do: value

  defp conversation_limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> max(1)
    |> min(@default_limit)
  end
end
