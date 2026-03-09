defmodule Threadr.ML.ConversationSummaryQA do
  @moduledoc """
  Time-bounded conversation summary QA grounded in reconstructed conversations.
  """

  import Ecto.Query

  alias Threadr.ControlPlane

  alias Threadr.ML.{
    ChannelLabel,
    ConversationQA,
    ConversationSummaryQAIntent,
    Generation,
    GenerationProviderOpts,
    ReconstructionQuery
  }

  @default_limit 20
  @max_limit 50

  def answer_question(tenant_subject_name, question, opts \\ [])
      when is_binary(tenant_subject_name) and is_binary(question) do
    with {:ok, tenant} <-
           ControlPlane.get_tenant_by_subject_name(tenant_subject_name, context: %{system: true}),
         {:ok, intent} <- ConversationSummaryQAIntent.classify(question),
         resolved_opts <- resolve_summary_opts(intent, opts),
         :ok <- require_time_bounds(resolved_opts),
         conversations when conversations != [] <-
           fetch_conversations(tenant.schema_name, resolved_opts) do
      build_answer(tenant, question, intent, conversations, resolved_opts)
    else
      [] -> {:error, :not_conversation_summary_question}
      {:error, :missing_time_bounds} -> {:error, :not_conversation_summary_question}
      {:error, :not_conversation_summary_question} = error -> error
    end
  end

  defp build_answer(tenant, question, intent, conversations, opts) do
    citations = ConversationQA.build_citations(tenant.schema_name, conversations)
    matches = citation_matches(citations)
    context = build_summary_context(question, conversations, citations, opts)

    with {:ok, answer} <- Generation.answer_question(question, context, generation_opts(opts)) do
      {:ok,
       %{
         tenant_subject_name: tenant.subject_name,
         tenant_schema: tenant.schema_name,
         question: question,
         query: %{
           mode: "conversation_summary_qa",
           kind: intent.kind,
           retrieval: "reconstructed_conversations",
           conversation_count: length(conversations),
           evidence_count: length(citations),
           channel_name: Keyword.get(opts, :requester_channel_name),
           since: format_timestamp(Keyword.get(opts, :since)),
           until: format_timestamp(Keyword.get(opts, :until))
         },
         conversations: conversations,
         matches: matches,
         citations: citations,
         facts_over_time: [],
         context: context,
         answer: answer
       }}
    end
  end

  defp fetch_conversations(tenant_schema, opts) do
    limit = conversation_limit(opts)

    from(c in "conversations",
      join: ch in "channels",
      on: ch.id == c.channel_id,
      where: ^channel_filter(Keyword.get(opts, :requester_channel_name)),
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
    |> Enum.map(fn conversation ->
      Map.put(
        conversation,
        :summary_text,
        get_in(conversation, [:metadata, "conversation_summary", "text"])
      )
    end)
  end

  defp build_summary_context(question, conversations, citations, opts) do
    header_lines = [
      "Conversation summary QA for tenant activity in the requested time window.",
      "Question: #{question}",
      "Window: #{format_timestamp(Keyword.get(opts, :since))} -> #{format_timestamp(Keyword.get(opts, :until))}",
      "Evidence retrieval: reconstructed_conversations; conversations=#{length(conversations)}; supporting_messages=#{length(citations)}."
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
          "Participants: #{participant_text(conversation)}",
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
        rows -> Threadr.ML.SemanticQA.build_context(rows)
      end

    Enum.join(header_lines ++ conversation_lines ++ blankable(evidence), "\n\n")
  end

  defp citation_matches(citations) do
    Enum.map(citations, fn citation ->
      %{
        message_id: citation.message_id,
        external_id: citation.external_id,
        body: citation.body,
        observed_at: citation.observed_at,
        actor_handle: citation.actor_handle,
        actor_display_name: citation.actor_display_name,
        channel_name: citation.channel_name,
        model: "conversation-summary",
        distance: nil,
        similarity: citation.similarity
      }
    end)
  end

  defp participant_text(conversation) do
    conversation.participant_summary
    |> Map.get("actor_handles", [])
    |> List.wrap()
    |> case do
      [] -> "unknown"
      handles -> Enum.join(handles, ", ")
    end
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
    entities =
      conversation.entity_summary
      |> Map.get("names", [])
      |> List.wrap()
      |> Enum.take(3)
      |> Enum.join(", ")

    "Participants discussed #{if(entities == "", do: "shared work", else: entities)}."
  end

  defp apply_conversation_time_bounds(query, opts) do
    query
    |> maybe_filter_conversation_since(Keyword.get(opts, :since))
    |> maybe_filter_conversation_until(Keyword.get(opts, :until))
  end

  defp resolve_summary_opts(intent, opts) do
    opts
    |> maybe_put_inferred_bounds(intent.time_scope)
    |> maybe_scope_current_channel(intent.scope_current_channel)
  end

  defp maybe_put_inferred_bounds(opts, :none), do: opts

  defp maybe_put_inferred_bounds(opts, time_scope) do
    if Keyword.get(opts, :since) || Keyword.get(opts, :until) do
      opts
    else
      {since, until} = inferred_bounds(time_scope)
      opts |> Keyword.put(:since, since) |> Keyword.put(:until, until)
    end
  end

  defp maybe_scope_current_channel(opts, false) do
    Keyword.delete(opts, :requester_channel_name)
  end

  defp maybe_scope_current_channel(opts, true), do: opts

  defp channel_filter(nil), do: dynamic(true)

  defp channel_filter(channel_name) do
    normalized = String.downcase(String.trim(channel_name))
    dynamic([_c, ch], fragment("lower(?) = ?", ch.name, ^normalized))
  end

  defp inferred_bounds(:today), do: day_bounds(Date.utc_today())
  defp inferred_bounds(:yesterday), do: day_bounds(Date.add(Date.utc_today(), -1))

  defp inferred_bounds(:last_week) do
    today = Date.utc_today()
    start_date = Date.add(today, -7)
    since = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    until = DateTime.new!(today, ~T[23:59:59], "Etc/UTC")
    {since, until}
  end

  defp inferred_bounds(:last_month) do
    today = Date.utc_today()
    start_date = Date.add(today, -30)
    since = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    until = DateTime.new!(today, ~T[23:59:59], "Etc/UTC")
    {since, until}
  end

  defp day_bounds(date) do
    since = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    until = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
    {since, until}
  end

  defp maybe_filter_conversation_since(query, nil), do: query

  defp maybe_filter_conversation_since(query, %NaiveDateTime{} = since) do
    maybe_filter_conversation_since(query, DateTime.from_naive!(since, "Etc/UTC"))
  end

  defp maybe_filter_conversation_since(query, %DateTime{} = since) do
    where(query, [c, _ch], c.last_message_at >= ^since)
  end

  defp maybe_filter_conversation_until(query, nil), do: query

  defp maybe_filter_conversation_until(query, %NaiveDateTime{} = until) do
    maybe_filter_conversation_until(query, DateTime.from_naive!(until, "Etc/UTC"))
  end

  defp maybe_filter_conversation_until(query, %DateTime{} = until) do
    where(query, [c, _ch], c.opened_at <= ^until)
  end

  defp normalize_conversation(conversation) do
    conversation
    |> Map.update!(:conversation_id, &normalize_identifier/1)
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

  defp generation_opts(opts), do: GenerationProviderOpts.from_prefixed(opts)

  defp require_time_bounds(opts) do
    if Keyword.get(opts, :since) || Keyword.get(opts, :until) do
      :ok
    else
      {:error, :missing_time_bounds}
    end
  end

  defp blankable(nil), do: []
  defp blankable(""), do: []
  defp blankable(value), do: [value]

  defp blank?(value), do: value in [nil, ""]

  defp time_window_label(conversation) do
    "#{format_timestamp(conversation.opened_at)} -> #{format_timestamp(conversation.last_message_at)}"
  end

  defp format_timestamp(nil), do: "open"
  defp format_timestamp(%DateTime{} = timestamp), do: DateTime.to_iso8601(timestamp)
  defp format_timestamp(%NaiveDateTime{} = timestamp), do: NaiveDateTime.to_iso8601(timestamp)
  defp format_timestamp(value), do: to_string(value)

  defp conversation_limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> max(1)
    |> min(@max_limit)
  end
end
