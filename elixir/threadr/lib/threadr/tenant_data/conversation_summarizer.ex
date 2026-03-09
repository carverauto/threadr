defmodule Threadr.TenantData.ConversationSummarizer do
  @moduledoc """
  Periodic summarization and topic extraction for reconstructed conversations.
  """

  import Ash.Expr
  import Ecto.Query
  require Ash.Query

  alias Threadr.ML.{Generation, GenerationProviderOpts}
  alias Threadr.Repo

  alias Threadr.TenantData.{
    Conversation,
    ConversationMembership,
    ExtractedEntity,
    ExtractedFact,
    PendingItem
  }

  @summary_version "conversation-summary-v1"
  @max_context_messages 20

  def summarize_conversation(conversation_id, tenant_schema, runtime_opts \\ [])
      when is_binary(conversation_id) and is_binary(tenant_schema) and is_list(runtime_opts) do
    with {:ok, conversation} <- fetch_conversation(conversation_id, tenant_schema),
         {:ok, messages} <- conversation_messages(conversation_id, tenant_schema),
         {:ok, parsed_summary, generation_result} <-
           generate_summary(conversation, messages, tenant_schema, runtime_opts),
         {:ok, updated} <-
           persist_summary(
             conversation,
             messages,
             parsed_summary,
             generation_result,
             tenant_schema
           ) do
      {:ok, updated}
    end
  end

  def pending_conversation_ids(tenant_schema, limit \\ 10)
      when is_binary(tenant_schema) and is_integer(limit) and limit > 0 do
    from(c in "conversations",
      where: fragment("coalesce((?->>?)::boolean, false)", c.metadata, "summary_needs_refresh"),
      order_by: [asc: c.last_message_at, asc: c.inserted_at],
      limit: ^limit,
      select: c.id
    )
    |> Repo.all(prefix: tenant_schema)
    |> Enum.map(&Ecto.UUID.cast!/1)
  end

  def summary_version, do: @summary_version

  defp fetch_conversation(conversation_id, tenant_schema) do
    case Conversation
         |> Ash.Query.filter(expr(id == ^conversation_id))
         |> Ash.read_one(tenant: tenant_schema) do
      {:ok, nil} -> {:error, {:conversation_not_found, conversation_id}}
      {:ok, conversation} -> {:ok, conversation}
      error -> error
    end
  end

  defp conversation_messages(conversation_id, tenant_schema) do
    message_ids =
      ConversationMembership
      |> Ash.Query.filter(expr(conversation_id == ^conversation_id and member_kind == "message"))
      |> Ash.Query.sort(attached_at: :asc)
      |> Ash.read!(tenant: tenant_schema)
      |> Enum.map(& &1.member_id)

    if message_ids == [] do
      {:error, :conversation_has_no_messages}
    else
      uuid_ids = Enum.map(message_ids, &dump_uuid!/1)

      messages =
        from(m in "messages",
          where: m.id in ^uuid_ids,
          order_by: [asc: m.observed_at, asc: m.id],
          select: %{
            id: m.id,
            actor_id: m.actor_id,
            body: m.body,
            metadata: m.metadata,
            observed_at: m.observed_at
          }
        )
        |> Repo.all(prefix: tenant_schema)

      actor_map = actor_map(messages, tenant_schema)
      entity_map = entity_map(messages, tenant_schema)
      fact_map = fact_map(messages, tenant_schema)

      enriched =
        Enum.map(messages, fn message ->
          actor = Map.get(actor_map, message.actor_id, %{})

          %{
            id: Ecto.UUID.cast!(message.id),
            body: message.body,
            observed_at: message.observed_at,
            metadata: message.metadata || %{},
            actor_id: Ecto.UUID.cast!(message.actor_id),
            actor_handle: actor[:handle],
            actor_display_name: actor[:display_name],
            dialogue_act: get_in(message.metadata || %{}, ["dialogue_act", "label"]),
            entities: Map.get(entity_map, Ecto.UUID.cast!(message.id), []),
            facts: Map.get(fact_map, Ecto.UUID.cast!(message.id), [])
          }
        end)

      {:ok, enriched}
    end
  end

  defp actor_map(messages, tenant_schema) do
    actor_ids =
      messages
      |> Enum.map(& &1.actor_id)
      |> Enum.uniq()

    from(a in "actors",
      where: a.id in ^actor_ids,
      select: {a.id, %{handle: a.handle, display_name: a.display_name}}
    )
    |> Repo.all(prefix: tenant_schema)
    |> Map.new(fn {id, attrs} -> {Ecto.UUID.cast!(id), attrs} end)
  end

  defp entity_map(messages, tenant_schema) do
    message_ids =
      messages
      |> Enum.map(& &1.id)
      |> Enum.uniq()

    ExtractedEntity
    |> Ash.Query.filter(expr(source_message_id in ^Enum.map(message_ids, &Ecto.UUID.cast!/1)))
    |> Ash.read!(tenant: tenant_schema)
    |> Enum.group_by(
      & &1.source_message_id,
      &%{
        entity_type: &1.entity_type,
        name: &1.name,
        canonical_name: &1.canonical_name,
        confidence: &1.confidence
      }
    )
  end

  defp fact_map(messages, tenant_schema) do
    message_ids =
      messages
      |> Enum.map(& &1.id)
      |> Enum.uniq()

    ExtractedFact
    |> Ash.Query.filter(expr(source_message_id in ^Enum.map(message_ids, &Ecto.UUID.cast!/1)))
    |> Ash.read!(tenant: tenant_schema)
    |> Enum.group_by(
      & &1.source_message_id,
      &%{
        fact_type: &1.fact_type,
        subject: &1.subject,
        predicate: &1.predicate,
        object: &1.object,
        confidence: &1.confidence
      }
    )
  end

  defp generate_summary(conversation, messages, tenant_schema, runtime_opts) do
    used_messages = Enum.take(messages, -@max_context_messages)
    prompt = summary_prompt(conversation, used_messages, tenant_schema)

    provider_opts =
      runtime_opts
      |> GenerationProviderOpts.from_prefixed()
      |> Keyword.put_new(:system_prompt, summary_system_prompt())

    with {:ok, generation_result} <- Generation.complete(prompt, provider_opts),
         {:ok, parsed_summary} <- parse_summary(generation_result.content, used_messages) do
      {:ok, parsed_summary, generation_result}
    end
  end

  defp summary_prompt(conversation, messages, tenant_schema) do
    open_items = open_pending_items(conversation.id, tenant_schema)

    """
    Summarize the reconstructed conversation using only the supplied evidence.

    Return exactly this format:
    TOPIC: <one concise topic phrase, 2 to 8 words>
    SUMMARY: <2 to 4 grounded sentences, citing message labels like [M1] when useful>

    Conversation:
    - Id: #{conversation.id}
    - State: #{conversation.lifecycle_state}
    - Opened at: #{encode_datetime(conversation.opened_at)}
    - Last message at: #{encode_datetime(conversation.last_message_at)}
    - Open pending items: #{conversation.open_pending_item_count}

    Pending Items:
    #{pending_item_context(open_items)}

    Messages:
    #{message_context(messages)}
    """
  end

  defp parse_summary(content, messages) when is_binary(content) do
    normalized = String.replace(content, "\r\n", "\n")

    case Regex.run(~r/TOPIC:\s*(.+?)\nSUMMARY:\s*(.+)\z/is, normalized) do
      [_, topic, summary] ->
        {:ok,
         %{
           topic: String.trim(topic),
           summary: String.trim(summary),
           message_ids: Enum.map(messages, & &1.id)
         }}

      _ ->
        {:ok,
         %{
           topic: heuristic_topic(messages),
           summary: String.trim(normalized),
           message_ids: Enum.map(messages, & &1.id)
         }}
    end
  end

  defp persist_summary(conversation, messages, parsed_summary, generation_result, tenant_schema) do
    generated_at = DateTime.utc_now() |> DateTime.truncate(:second)

    summary_metadata =
      conversation_summary_metadata(parsed_summary, generation_result, generated_at)

    attrs = %{
      topic_summary: blank_to_nil(parsed_summary.topic),
      confidence_summary:
        (conversation.confidence_summary || %{})
        |> Map.put("summary_message_count", length(messages))
        |> Map.put("summary_messages_used", length(parsed_summary.message_ids))
        |> Map.put("summary_generated_at", encode_datetime(generated_at))
        |> Map.put("summary_source", "batch_generation"),
      metadata:
        (conversation.metadata || %{})
        |> Map.put("conversation_summary", summary_metadata)
        |> Map.put("summary_needs_refresh", false)
        |> Map.put("summary_refresh_reason", "up_to_date")
        |> Map.put("summary_generated_at", encode_datetime(generated_at))
    }

    conversation
    |> Ash.Changeset.for_update(:update, attrs, tenant: tenant_schema)
    |> Ash.update()
  end

  defp conversation_summary_metadata(parsed_summary, generation_result, generated_at) do
    %{
      "text" => parsed_summary.summary,
      "topic" => parsed_summary.topic,
      "message_ids" => Enum.map(parsed_summary.message_ids, &to_string/1),
      "generated_at" => encode_datetime(generated_at),
      "provider" => generation_result.provider,
      "model" => generation_result.model,
      "version" => @summary_version
    }
  end

  defp open_pending_items(conversation_id, tenant_schema) do
    PendingItem
    |> Ash.Query.filter(expr(conversation_id == ^conversation_id and status == "open"))
    |> Ash.Query.sort(opened_at: :asc)
    |> Ash.read!(tenant: tenant_schema)
  end

  defp pending_item_context([]), do: "- none"

  defp pending_item_context(items) do
    items
    |> Enum.map(fn item ->
      "- [#{item.item_kind}] #{item.summary_text}"
    end)
    |> Enum.join("\n")
  end

  defp message_context(messages) do
    messages
    |> Enum.with_index(1)
    |> Enum.map(fn {message, index} ->
      """
      [M#{index}] #{encode_datetime(message.observed_at)} #{display_name(message)}#{dialogue_act_suffix(message)}
      Body: #{blank_to_placeholder(message.body)}
      Entities: #{entity_text(message.entities)}
      Facts: #{fact_text(message.facts)}
      """
      |> String.trim_trailing()
    end)
    |> Enum.join("\n\n")
  end

  defp display_name(message) do
    cond do
      is_binary(message.actor_handle) and message.actor_handle != "" ->
        message.actor_handle

      is_binary(message.actor_display_name) and message.actor_display_name != "" ->
        message.actor_display_name

      true ->
        "unknown"
    end
  end

  defp dialogue_act_suffix(%{dialogue_act: nil}), do: ""
  defp dialogue_act_suffix(%{dialogue_act: ""}), do: ""
  defp dialogue_act_suffix(%{dialogue_act: label}), do: " (#{label})"

  defp entity_text([]), do: "none"

  defp entity_text(entities) do
    entities
    |> Enum.map(fn entity -> entity.canonical_name || entity.name end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] -> "none"
      names -> Enum.join(names, ", ")
    end
  end

  defp fact_text([]), do: "none"

  defp fact_text(facts) do
    facts
    |> Enum.map(fn fact -> "#{fact.subject} #{fact.predicate} #{fact.object}" end)
    |> Enum.join("; ")
  end

  defp heuristic_topic(messages) do
    messages
    |> Enum.flat_map(fn message ->
      Enum.map(message.entities, fn entity -> entity.canonical_name || entity.name end)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {name, count} -> {-count, name} end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.take(3)
    |> case do
      [] -> "conversation update"
      names -> Enum.join(names, ", ")
    end
  end

  defp blank_to_placeholder(nil), do: "(empty)"
  defp blank_to_placeholder(body) when is_binary(body) and body != "", do: body
  defp blank_to_placeholder(_body), do: "(empty)"

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp summary_system_prompt do
    "Summarize the supplied reconstructed tenant conversation faithfully. Do not invent participants, outcomes, or topics."
  end

  defp encode_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp encode_datetime(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime)
  defp encode_datetime(nil), do: nil

  defp dump_uuid!(id) when is_binary(id) do
    case Ecto.UUID.dump(id) do
      {:ok, dumped} -> dumped
      :error -> raise ArgumentError, "invalid UUID #{inspect(id)}"
    end
  end
end
