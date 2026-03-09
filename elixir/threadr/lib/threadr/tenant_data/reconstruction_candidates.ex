defmodule Threadr.TenantData.ReconstructionCandidates do
  @moduledoc """
  Bounded candidate retrieval for online conversation reconstruction.
  """

  import Ecto.Query

  alias Threadr.Repo

  @default_message_limit 24
  @default_conversation_limit 8
  @default_unresolved_limit 8
  @default_lookback_hours 72
  @default_unresolved_lookback_hours 168
  @max_limit 100
  @max_lookback_hours 24 * 30
  @conversation_gap_minutes 20
  @opener_dialogue_acts MapSet.new(["question", "request"])
  @resolver_dialogue_acts MapSet.new(["answer", "acknowledgement", "status_update"])

  def for_message(message_id, tenant_schema, opts \\ [])
      when is_binary(message_id) and is_binary(tenant_schema) and is_list(opts) do
    with {:ok, focal_message} <- fetch_message(tenant_schema, message_id) do
      recent_messages =
        focal_message
        |> recent_messages(tenant_schema, opts)
        |> enrich_messages(tenant_schema)

      {:ok,
       %{
         focal_message: enrich_message(focal_message, tenant_schema),
         recent_messages: recent_messages,
         recent_conversations: recent_conversations(focal_message, recent_messages, opts),
         unresolved_items: unresolved_items(focal_message, recent_messages, opts)
       }}
    end
  end

  defp fetch_message(tenant_schema, message_id) do
    Repo.one(
      message_query(tenant_schema,
        where: dynamic([m], m.id == type(^message_id, :binary_id) or m.external_id == ^message_id)
      )
    )
    |> case do
      nil -> {:error, {:message_not_found, message_id}}
      message -> {:ok, normalize_message(message)}
    end
  end

  defp recent_messages(focal_message, tenant_schema, opts) do
    limit = normalize_count_limit(Keyword.get(opts, :message_limit), @default_message_limit)

    lookback_hours =
      normalize_lookback_hours(Keyword.get(opts, :lookback_hours), @default_lookback_hours)

    since = shift_datetime(focal_message.observed_at, -lookback_hours, :hour)

    recent =
      Repo.all(
        message_query(
          tenant_schema,
          where:
            dynamic(
              [m],
              m.channel_id == ^dump_uuid!(focal_message.channel_id) and
                m.id != ^dump_uuid!(focal_message.id) and
                m.observed_at >= ^since and
                m.observed_at < ^focal_message.observed_at
            ),
          limit: limit,
          order_by: [desc: :observed_at, desc: :inserted_at]
        )
      )
      |> Enum.map(&normalize_message/1)

    explicit_reply_candidate =
      focal_message
      |> reply_to_external_id()
      |> explicit_reply_candidate(tenant_schema)

    [explicit_reply_candidate | recent]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
    |> Enum.take(limit)
  end

  defp explicit_reply_candidate(nil, _tenant_schema), do: nil

  defp explicit_reply_candidate(reply_to_external_id, tenant_schema) do
    Repo.one(
      message_query(
        tenant_schema,
        where: dynamic([m], m.external_id == ^reply_to_external_id)
      )
    )
    |> case do
      nil -> nil
      message -> normalize_message(message)
    end
  end

  defp recent_conversations(focal_message, recent_messages, opts) do
    limit =
      normalize_count_limit(Keyword.get(opts, :conversation_limit), @default_conversation_limit)

    focal_conversation_id = conversation_external_id(focal_message)

    recent_messages
    |> Enum.sort_by(&sortable_observed_at/1)
    |> Enum.reduce({[], nil}, fn message, {groups, current} ->
      cond do
        is_nil(current) ->
          {groups, start_conversation(message)}

        same_conversation?(current, message) ->
          {groups, append_to_conversation(current, message)}

        true ->
          {[finalize_conversation(current, focal_conversation_id) | groups],
           start_conversation(message)}
      end
    end)
    |> finalize_conversations(focal_conversation_id)
    |> Enum.sort_by(&sortable_observed_at(%{observed_at: &1.ended_at}), :desc)
    |> Enum.take(limit)
  end

  defp unresolved_items(focal_message, recent_messages, opts) do
    limit =
      normalize_count_limit(Keyword.get(opts, :unresolved_limit), @default_unresolved_limit)

    lookback_hours =
      normalize_lookback_hours(
        Keyword.get(opts, :unresolved_lookback_hours),
        @default_unresolved_lookback_hours
      )

    since = shift_datetime(focal_message.observed_at, -lookback_hours, :hour)

    recent_messages
    |> Enum.filter(fn message ->
      sortable_observed_at(message) >= sortable_observed_at(%{observed_at: since})
    end)
    |> Enum.filter(&opener_message?/1)
    |> Enum.reject(&resolved_before_focal?(&1, recent_messages))
    |> Enum.map(&to_unresolved_item/1)
    |> Enum.take(limit)
  end

  defp message_query(tenant_schema, opts) do
    where_clause = Keyword.get(opts, :where, true)
    order_by_clause = Keyword.get(opts, :order_by, desc: :observed_at, desc: :inserted_at)
    limit_value = Keyword.get(opts, :limit)

    query =
      from(m in "messages",
        prefix: ^tenant_schema,
        join: a in "actors",
        on: a.id == m.actor_id,
        prefix: ^tenant_schema,
        join: c in "channels",
        on: c.id == m.channel_id,
        prefix: ^tenant_schema,
        where: ^where_clause,
        order_by: ^order_by_clause,
        select: %{
          id: m.id,
          external_id: m.external_id,
          body: m.body,
          observed_at: m.observed_at,
          inserted_at: m.inserted_at,
          metadata: m.metadata,
          actor_id: a.id,
          actor_handle: a.handle,
          actor_display_name: a.display_name,
          channel_id: c.id,
          channel_name: c.name,
          platform: a.platform
        }
      )

    if is_integer(limit_value), do: from(row in query, limit: ^limit_value), else: query
  end

  defp enrich_message(message, tenant_schema) do
    [enriched] = enrich_messages([message], tenant_schema)
    enriched
  end

  defp enrich_messages([], _tenant_schema), do: []

  defp enrich_messages(messages, tenant_schema) do
    message_ids = Enum.map(messages, & &1.id)
    entities_by_message = fetch_entities_by_message(tenant_schema, message_ids)
    facts_by_message = fetch_facts_by_message(tenant_schema, message_ids)

    Enum.map(messages, fn message ->
      dialogue_act = get_in(message, [:metadata, "dialogue_act"]) || %{}
      entities = Map.get(entities_by_message, message.id, [])
      facts = Map.get(facts_by_message, message.id, [])

      message
      |> Map.put(:dialogue_act, %{
        label: Map.get(dialogue_act, "label"),
        confidence: Map.get(dialogue_act, "confidence"),
        metadata: Map.get(dialogue_act, "metadata") || %{}
      })
      |> Map.put(:conversation_external_id, conversation_external_id(message))
      |> Map.put(:reply_to_external_id, reply_to_external_id(message))
      |> Map.put(:thread_external_id, get_in(message, [:metadata, "thread_external_id"]))
      |> Map.put(:extracted_entities, entities)
      |> Map.put(:extracted_facts, facts)
      |> Map.put(:entity_names, entity_names(%{extracted_entities: entities}))
      |> Map.put(:fact_types, fact_types(%{extracted_facts: facts}))
    end)
  end

  defp fetch_entities_by_message(_tenant_schema, []), do: %{}

  defp fetch_entities_by_message(tenant_schema, message_ids) do
    source_message_ids = Enum.map(message_ids, &dump_uuid!/1)

    Repo.all(
      from(e in "extracted_entities",
        prefix: ^tenant_schema,
        where: e.source_message_id in ^source_message_ids,
        order_by: [desc: e.confidence, asc: e.name],
        select: %{
          id: e.id,
          entity_type: e.entity_type,
          name: e.name,
          canonical_name: e.canonical_name,
          confidence: e.confidence,
          metadata: e.metadata,
          source_message_id: e.source_message_id
        }
      )
    )
    |> Enum.map(fn entity ->
      %{
        entity
        | id: normalize_uuid(entity.id),
          source_message_id: normalize_uuid(entity.source_message_id)
      }
    end)
    |> Enum.group_by(& &1.source_message_id)
  end

  defp fetch_facts_by_message(_tenant_schema, []), do: %{}

  defp fetch_facts_by_message(tenant_schema, message_ids) do
    source_message_ids = Enum.map(message_ids, &dump_uuid!/1)

    Repo.all(
      from(f in "extracted_facts",
        prefix: ^tenant_schema,
        where: f.source_message_id in ^source_message_ids,
        order_by: [desc: f.confidence, asc: f.fact_type],
        select: %{
          id: f.id,
          fact_type: f.fact_type,
          subject: f.subject,
          predicate: f.predicate,
          object: f.object,
          confidence: f.confidence,
          valid_at: f.valid_at,
          metadata: f.metadata,
          source_message_id: f.source_message_id
        }
      )
    )
    |> Enum.map(fn fact ->
      %{
        fact
        | id: normalize_uuid(fact.id),
          source_message_id: normalize_uuid(fact.source_message_id)
      }
    end)
    |> Enum.group_by(& &1.source_message_id)
  end

  defp normalize_message(message) do
    %{
      message
      | id: normalize_uuid(message.id),
        actor_id: normalize_uuid(message.actor_id),
        channel_id: normalize_uuid(message.channel_id),
        metadata: message.metadata || %{}
    }
  end

  defp reply_to_external_id(message), do: get_in(message, [:metadata, "reply_to_external_id"])

  defp conversation_external_id(message) do
    get_in(message, [:metadata, "conversation_external_id"]) || message.channel_id
  end

  defp start_conversation(message) do
    %{
      channel_id: message.channel_id,
      channel_name: message.channel_name,
      message_ids: [message.id],
      actor_ids: MapSet.new([message.actor_id]),
      actor_handles: MapSet.new([message.actor_handle]),
      entity_names: entity_names(message),
      fact_types: fact_types(message),
      dialogue_labels: dialogue_labels(message),
      conversation_external_ids: MapSet.new([conversation_external_id(message)]),
      message_count: 1,
      started_at: message.observed_at,
      ended_at: message.observed_at,
      last_message_id: message.id
    }
  end

  defp append_to_conversation(conversation, message) do
    %{
      conversation
      | message_ids: conversation.message_ids ++ [message.id],
        actor_ids: MapSet.put(conversation.actor_ids, message.actor_id),
        actor_handles: MapSet.put(conversation.actor_handles, message.actor_handle),
        entity_names: Enum.uniq(conversation.entity_names ++ entity_names(message)),
        fact_types: Enum.uniq(conversation.fact_types ++ fact_types(message)),
        dialogue_labels: Enum.uniq(conversation.dialogue_labels ++ dialogue_labels(message)),
        conversation_external_ids:
          MapSet.put(conversation.conversation_external_ids, conversation_external_id(message)),
        message_count: conversation.message_count + 1,
        ended_at: message.observed_at,
        last_message_id: message.id
    }
  end

  defp finalize_conversations({groups, nil}, _focal_conversation_id),
    do: Enum.reverse(groups)

  defp finalize_conversations({groups, current}, focal_conversation_id),
    do: Enum.reverse([finalize_conversation(current, focal_conversation_id) | groups])

  defp finalize_conversation(conversation, focal_conversation_id) do
    conversation_external_ids =
      conversation.conversation_external_ids
      |> MapSet.to_list()
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()

    %{
      id:
        "candidate-conversation:" <>
          Base.url_encode64(
            :crypto.hash(
              :sha256,
              Enum.join(
                [
                  conversation.channel_id,
                  hd(conversation.message_ids),
                  conversation.last_message_id
                ],
                ":"
              )
            ),
            padding: false
          ),
      channel_id: conversation.channel_id,
      channel_name: conversation.channel_name,
      actor_ids: conversation.actor_ids |> MapSet.to_list() |> Enum.sort(),
      actor_handles: conversation.actor_handles |> MapSet.to_list() |> Enum.sort(),
      message_ids: conversation.message_ids,
      entity_names: Enum.sort(conversation.entity_names),
      fact_types: Enum.sort(conversation.fact_types),
      dialogue_labels: Enum.sort(conversation.dialogue_labels),
      conversation_external_ids: conversation_external_ids,
      message_count: conversation.message_count,
      started_at: conversation.started_at,
      ended_at: conversation.ended_at,
      last_message_id: conversation.last_message_id,
      focal_conversation_match:
        not is_nil(focal_conversation_id) and focal_conversation_id in conversation_external_ids
    }
  end

  defp same_conversation?(conversation, message) do
    same_channel?(conversation, message) and
      within_gap?(conversation.ended_at, message.observed_at)
  end

  defp same_channel?(conversation, message), do: conversation.channel_id == message.channel_id

  defp within_gap?(%DateTime{} = previous, %DateTime{} = current) do
    DateTime.diff(current, previous, :minute) <= @conversation_gap_minutes
  end

  defp within_gap?(%NaiveDateTime{} = previous, %NaiveDateTime{} = current) do
    NaiveDateTime.diff(current, previous, :minute) <= @conversation_gap_minutes
  end

  defp within_gap?(_previous, _current), do: false

  defp opener_message?(message) do
    message
    |> get_in([:dialogue_act, :label])
    |> then(&MapSet.member?(@opener_dialogue_acts, &1))
  end

  defp resolved_before_focal?(opener, recent_messages) do
    Enum.any?(recent_messages, fn candidate ->
      candidate.id != opener.id and
        candidate.actor_id != opener.actor_id and
        sortable_observed_at(candidate) > sortable_observed_at(opener) and
        resolver_message?(candidate) and
        resolves_opener?(candidate, opener)
    end)
  end

  defp resolver_message?(message) do
    message
    |> get_in([:dialogue_act, :label])
    |> then(&MapSet.member?(@resolver_dialogue_acts, &1))
  end

  defp resolves_opener?(candidate, opener) do
    reply_to_external_id(candidate) == opener.external_id or
      conversation_external_id(candidate) == conversation_external_id(opener)
  end

  defp to_unresolved_item(message) do
    %{
      opener_message_id: message.id,
      opener_external_id: message.external_id,
      actor_id: message.actor_id,
      actor_handle: message.actor_handle,
      actor_display_name: message.actor_display_name,
      channel_id: message.channel_id,
      channel_name: message.channel_name,
      body: message.body,
      observed_at: message.observed_at,
      dialogue_act: message.dialogue_act,
      conversation_external_id: message.conversation_external_id,
      entity_names: entity_names(message),
      fact_types: fact_types(message)
    }
  end

  defp entity_names(message) do
    message
    |> Map.get(:extracted_entities, [])
    |> Enum.map(fn entity -> entity.canonical_name || entity.name end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp fact_types(message) do
    message
    |> Map.get(:extracted_facts, [])
    |> Enum.map(& &1.fact_type)
    |> Enum.uniq()
  end

  defp dialogue_labels(message) do
    case get_in(message, [:dialogue_act, :label]) do
      nil -> []
      label -> [label]
    end
  end

  defp sortable_observed_at(%{observed_at: %DateTime{} = observed_at}),
    do: DateTime.to_unix(observed_at, :microsecond)

  defp sortable_observed_at(%{observed_at: %NaiveDateTime{} = observed_at}),
    do: NaiveDateTime.diff(observed_at, ~N[1970-01-01 00:00:00], :microsecond)

  defp sortable_observed_at(%{observed_at: nil}), do: 0

  defp normalize_count_limit(value, _default) when is_integer(value),
    do: value |> max(1) |> min(@max_limit)

  defp normalize_count_limit(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} -> normalize_count_limit(parsed, default)
      :error -> default
    end
  end

  defp normalize_count_limit(_value, default), do: default

  defp normalize_lookback_hours(value, _default) when is_integer(value),
    do: value |> max(1) |> min(@max_lookback_hours)

  defp normalize_lookback_hours(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} -> normalize_lookback_hours(parsed, default)
      :error -> default
    end
  end

  defp normalize_lookback_hours(_value, default), do: default

  defp shift_datetime(%DateTime{} = value, amount, unit), do: DateTime.add(value, amount, unit)

  defp shift_datetime(%NaiveDateTime{} = value, amount, unit),
    do: NaiveDateTime.add(value, amount, unit)

  defp normalize_uuid(nil), do: nil

  defp normalize_uuid(value) when is_binary(value) do
    case Ecto.UUID.load(value) do
      {:ok, uuid} -> uuid
      :error -> value
    end
  end

  defp dump_uuid!(value) when is_binary(value), do: Ecto.UUID.dump!(value)
end
