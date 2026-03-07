defmodule Threadr.TenantData.GraphInspector do
  @moduledoc """
  Server-side node inspection for tenant graph exploration.

  The graph client renders from snapshot data, but detailed selection dossiers are
  fetched on demand so the browser does not need to derive or carry a second
  graph model.
  """

  import Ecto.Query

  alias Threadr.CompareDelta
  alias Threadr.Repo
  alias Threadr.TenantData.Graph

  @message_limit 8
  @relationship_limit 8

  def describe_node(node_id, node_kind, tenant_schema)
      when is_binary(node_id) and is_binary(node_kind) and is_binary(tenant_schema) do
    case node_kind do
      "message" -> describe_message(node_id, tenant_schema)
      "actor" -> describe_actor(node_id, tenant_schema)
      "channel" -> describe_channel(node_id, tenant_schema)
      other -> {:error, {:unsupported_node_kind, other}}
    end
  end

  def compare_node_windows(node_id, node_kind, tenant_schema, baseline_window, comparison_window)
      when is_binary(node_id) and is_binary(node_kind) and is_binary(tenant_schema) and
             is_map(baseline_window) and is_map(comparison_window) do
    with {:ok, baseline} <-
           describe_node_window(node_id, node_kind, tenant_schema, baseline_window),
         {:ok, comparison} <-
           describe_node_window(node_id, node_kind, tenant_schema, comparison_window),
         delta <-
           CompareDelta.build(
             baseline.extracted_entities || [],
             comparison.extracted_entities || [],
             baseline.extracted_facts || [],
             comparison.extracted_facts || []
           ) do
      {:ok,
       %{
         node_kind: node_kind,
         node_id: node_id,
         baseline: baseline,
         comparison: comparison,
         entity_delta: delta.entity_delta,
         fact_delta: delta.fact_delta,
         context:
           build_comparison_context(baseline, comparison, baseline_window, comparison_window)
       }}
    end
  end

  defp describe_message(message_id, tenant_schema) do
    with {:ok, message} <- fetch_message(tenant_schema, message_id),
         {:ok, neighborhood} <-
           Graph.neighborhood([message_id], tenant_schema, graph_message_limit: 8) do
      extracted_entities = extracted_entities_for_messages(tenant_schema, [message_id], 12)
      extracted_facts = extracted_facts_for_messages(tenant_schema, [message_id], 12)

      {:ok,
       %{
         type: "message",
         focal: message,
         summary: %{
           message_count: 1,
           related_actor_count: length(neighborhood.actors),
           related_relationship_count: length(neighborhood.relationships),
           extracted_entity_count: length(extracted_entities),
           extracted_fact_count: length(extracted_facts)
         },
         recent_messages: [message],
         extracted_entities: extracted_entities,
         extracted_facts: extracted_facts,
         facts_over_time: facts_over_time(extracted_facts),
         neighborhood: neighborhood_payload(neighborhood)
       }}
    end
  end

  defp describe_node_window(node_id, "message", tenant_schema, _window),
    do: describe_message(node_id, tenant_schema)

  defp describe_node_window(node_id, "actor", tenant_schema, window) do
    with {:ok, actor} <- fetch_actor(tenant_schema, node_id),
         message_ids <- fetch_actor_message_ids(tenant_schema, node_id, window),
         {:ok, neighborhood} <-
           Graph.neighborhood(message_ids, tenant_schema, graph_message_limit: 8) do
      extracted_entities = extracted_entities_for_messages(tenant_schema, message_ids, 12)
      extracted_facts = extracted_facts_for_messages(tenant_schema, message_ids, 12)

      {:ok,
       %{
         type: "actor",
         focal: actor,
         summary: %{
           message_count: length(message_ids),
           channel_count: length(top_channels_for_actor(tenant_schema, node_id, window)),
           related_actor_count: length(neighborhood.actors),
           related_relationship_count: length(neighborhood.relationships),
           extracted_entity_count: length(extracted_entities),
           extracted_fact_count: length(extracted_facts)
         },
         recent_messages: recent_messages_for_actor(tenant_schema, node_id, window),
         top_channels: top_channels_for_actor(tenant_schema, node_id, window),
         top_relationships: top_relationships_for_actor(tenant_schema, node_id, window),
         extracted_entities: extracted_entities,
         extracted_facts: extracted_facts,
         facts_over_time: facts_over_time(extracted_facts),
         neighborhood: neighborhood_payload(neighborhood)
       }}
    end
  end

  defp describe_node_window(node_id, "channel", tenant_schema, window) do
    with {:ok, channel} <- fetch_channel(tenant_schema, node_id),
         message_ids <- fetch_channel_message_ids(tenant_schema, node_id, window),
         {:ok, neighborhood} <-
           Graph.neighborhood(message_ids, tenant_schema, graph_message_limit: 8) do
      extracted_entities = extracted_entities_for_messages(tenant_schema, message_ids, 12)
      extracted_facts = extracted_facts_for_messages(tenant_schema, message_ids, 12)

      {:ok,
       %{
         type: "channel",
         focal: channel,
         summary: %{
           message_count: length(message_ids),
           actor_count: length(top_actors_for_channel(tenant_schema, node_id, window)),
           related_actor_count: length(neighborhood.actors),
           related_relationship_count: length(neighborhood.relationships),
           extracted_entity_count: length(extracted_entities),
           extracted_fact_count: length(extracted_facts)
         },
         recent_messages: recent_messages_for_channel(tenant_schema, node_id, window),
         top_actors: top_actors_for_channel(tenant_schema, node_id, window),
         extracted_entities: extracted_entities,
         extracted_facts: extracted_facts,
         facts_over_time: facts_over_time(extracted_facts),
         neighborhood: neighborhood_payload(neighborhood)
       }}
    end
  end

  defp describe_node_window(_node_id, node_kind, _tenant_schema, _window),
    do: {:error, {:unsupported_node_kind, node_kind}}

  defp describe_actor(actor_id, tenant_schema) do
    with {:ok, actor} <- fetch_actor(tenant_schema, actor_id),
         message_ids <- fetch_actor_message_ids(tenant_schema, actor_id),
         {:ok, neighborhood} <-
           Graph.neighborhood(message_ids, tenant_schema, graph_message_limit: 8) do
      extracted_entities = extracted_entities_for_messages(tenant_schema, message_ids, 12)
      extracted_facts = extracted_facts_for_messages(tenant_schema, message_ids, 12)

      {:ok,
       %{
         type: "actor",
         focal: actor,
         summary: %{
           message_count: length(message_ids),
           channel_count: length(top_channels_for_actor(tenant_schema, actor_id)),
           related_actor_count: length(neighborhood.actors),
           related_relationship_count: length(neighborhood.relationships),
           extracted_entity_count: length(extracted_entities),
           extracted_fact_count: length(extracted_facts)
         },
         recent_messages: recent_messages_for_actor(tenant_schema, actor_id),
         top_channels: top_channels_for_actor(tenant_schema, actor_id),
         top_relationships: top_relationships_for_actor(tenant_schema, actor_id),
         extracted_entities: extracted_entities,
         extracted_facts: extracted_facts,
         facts_over_time: facts_over_time(extracted_facts),
         neighborhood: neighborhood_payload(neighborhood)
       }}
    end
  end

  defp describe_channel(channel_id, tenant_schema) do
    with {:ok, channel} <- fetch_channel(tenant_schema, channel_id),
         message_ids <- fetch_channel_message_ids(tenant_schema, channel_id),
         {:ok, neighborhood} <-
           Graph.neighborhood(message_ids, tenant_schema, graph_message_limit: 8) do
      extracted_entities = extracted_entities_for_messages(tenant_schema, message_ids, 12)
      extracted_facts = extracted_facts_for_messages(tenant_schema, message_ids, 12)

      {:ok,
       %{
         type: "channel",
         focal: channel,
         summary: %{
           message_count: length(message_ids),
           actor_count: length(top_actors_for_channel(tenant_schema, channel_id)),
           related_actor_count: length(neighborhood.actors),
           related_relationship_count: length(neighborhood.relationships),
           extracted_entity_count: length(extracted_entities),
           extracted_fact_count: length(extracted_facts)
         },
         recent_messages: recent_messages_for_channel(tenant_schema, channel_id),
         top_actors: top_actors_for_channel(tenant_schema, channel_id),
         extracted_entities: extracted_entities,
         extracted_facts: extracted_facts,
         facts_over_time: facts_over_time(extracted_facts),
         neighborhood: neighborhood_payload(neighborhood)
       }}
    end
  end

  defp fetch_message(tenant_schema, message_id) do
    Repo.one(
      from(m in "messages",
        prefix: ^tenant_schema,
        join: a in "actors",
        on: a.id == m.actor_id,
        prefix: ^tenant_schema,
        join: c in "channels",
        on: c.id == m.channel_id,
        prefix: ^tenant_schema,
        where: m.id == type(^message_id, :binary_id),
        select: %{
          id: m.id,
          external_id: m.external_id,
          body: m.body,
          observed_at: m.observed_at,
          actor_id: m.actor_id,
          actor_handle: a.handle,
          actor_display_name: a.display_name,
          channel_id: c.id,
          channel_name: c.name
        }
      )
    )
    |> case do
      nil -> {:error, :not_found}
      message -> {:ok, normalize_map_ids(message)}
    end
  end

  defp fetch_actor(tenant_schema, actor_id) do
    Repo.one(
      from(a in "actors",
        prefix: ^tenant_schema,
        where: a.id == type(^actor_id, :binary_id),
        select: %{
          id: a.id,
          platform: a.platform,
          handle: a.handle,
          display_name: a.display_name,
          external_id: a.external_id,
          last_seen_at: a.last_seen_at
        }
      )
    )
    |> case do
      nil -> {:error, :not_found}
      actor -> {:ok, normalize_map_ids(actor)}
    end
  end

  defp fetch_channel(tenant_schema, channel_id) do
    Repo.one(
      from(c in "channels",
        prefix: ^tenant_schema,
        where: c.id == type(^channel_id, :binary_id),
        select: %{
          id: c.id,
          platform: c.platform,
          name: c.name,
          external_id: c.external_id
        }
      )
    )
    |> case do
      nil -> {:error, :not_found}
      channel -> {:ok, normalize_map_ids(channel)}
    end
  end

  defp fetch_actor_message_ids(tenant_schema, actor_id, window \\ %{}) do
    from(m in "messages",
      prefix: ^tenant_schema,
      where: m.actor_id == type(^actor_id, :binary_id),
      order_by: [desc: m.observed_at, desc: m.inserted_at],
      limit: @message_limit,
      select: m.id
    )
    |> maybe_filter_message_since(window_value(window, :since))
    |> maybe_filter_message_until(window_value(window, :until))
    |> Repo.all()
    |> Enum.map(&normalize_id/1)
  end

  defp fetch_channel_message_ids(tenant_schema, channel_id, window \\ %{}) do
    from(m in "messages",
      prefix: ^tenant_schema,
      where: m.channel_id == type(^channel_id, :binary_id),
      order_by: [desc: m.observed_at, desc: m.inserted_at],
      limit: @message_limit,
      select: m.id
    )
    |> maybe_filter_message_since(window_value(window, :since))
    |> maybe_filter_message_until(window_value(window, :until))
    |> Repo.all()
    |> Enum.map(&normalize_id/1)
  end

  defp recent_messages_for_actor(tenant_schema, actor_id, window \\ %{}) do
    from(m in "messages",
      prefix: ^tenant_schema,
      join: c in "channels",
      on: c.id == m.channel_id,
      prefix: ^tenant_schema,
      where: m.actor_id == type(^actor_id, :binary_id),
      order_by: [desc: m.observed_at, desc: m.inserted_at],
      limit: @message_limit,
      select: %{
        id: m.id,
        external_id: m.external_id,
        body: m.body,
        observed_at: m.observed_at,
        channel_id: c.id,
        channel_name: c.name
      }
    )
    |> maybe_filter_message_since(window_value(window, :since))
    |> maybe_filter_message_until(window_value(window, :until))
    |> Repo.all()
    |> Enum.map(&normalize_map_ids/1)
    |> Enum.map(&stringify_timestamps/1)
  end

  defp recent_messages_for_channel(tenant_schema, channel_id, window \\ %{}) do
    from(m in "messages",
      prefix: ^tenant_schema,
      join: a in "actors",
      on: a.id == m.actor_id,
      prefix: ^tenant_schema,
      where: m.channel_id == type(^channel_id, :binary_id),
      order_by: [desc: m.observed_at, desc: m.inserted_at],
      limit: @message_limit,
      select: %{
        id: m.id,
        external_id: m.external_id,
        body: m.body,
        observed_at: m.observed_at,
        actor_id: a.id,
        actor_handle: a.handle,
        actor_display_name: a.display_name
      }
    )
    |> maybe_filter_message_since(window_value(window, :since))
    |> maybe_filter_message_until(window_value(window, :until))
    |> Repo.all()
    |> Enum.map(&normalize_map_ids/1)
    |> Enum.map(&stringify_timestamps/1)
  end

  defp top_channels_for_actor(tenant_schema, actor_id, window \\ %{}) do
    from(m in "messages",
      prefix: ^tenant_schema,
      join: c in "channels",
      on: c.id == m.channel_id,
      prefix: ^tenant_schema,
      where: m.actor_id == type(^actor_id, :binary_id),
      group_by: [c.id, c.name],
      order_by: [desc: count(m.id), asc: c.name],
      limit: 6,
      select: %{
        channel_id: c.id,
        channel_name: c.name,
        message_count: count(m.id)
      }
    )
    |> maybe_filter_message_since(window_value(window, :since))
    |> maybe_filter_message_until(window_value(window, :until))
    |> Repo.all()
    |> Enum.map(&normalize_map_ids/1)
  end

  defp top_actors_for_channel(tenant_schema, channel_id, window \\ %{}) do
    from(m in "messages",
      prefix: ^tenant_schema,
      join: a in "actors",
      on: a.id == m.actor_id,
      prefix: ^tenant_schema,
      where: m.channel_id == type(^channel_id, :binary_id),
      group_by: [a.id, a.handle, a.display_name],
      order_by: [desc: count(m.id), asc: a.handle],
      limit: 6,
      select: %{
        actor_id: a.id,
        actor_handle: a.handle,
        actor_display_name: a.display_name,
        message_count: count(m.id)
      }
    )
    |> maybe_filter_message_since(window_value(window, :since))
    |> maybe_filter_message_until(window_value(window, :until))
    |> Repo.all()
    |> Enum.map(&normalize_map_ids/1)
  end

  defp top_relationships_for_actor(tenant_schema, actor_id, window \\ %{}) do
    message_ids =
      fetch_actor_message_ids(tenant_schema, actor_id, window) |> Enum.map(&dump_uuid!/1)

    from(r in "relationships",
      prefix: ^tenant_schema,
      join: from_actor in "actors",
      on: from_actor.id == r.from_actor_id,
      prefix: ^tenant_schema,
      join: to_actor in "actors",
      on: to_actor.id == r.to_actor_id,
      prefix: ^tenant_schema,
      join: m in "messages",
      on: m.id == r.source_message_id,
      prefix: ^tenant_schema,
      where:
        (r.from_actor_id == type(^actor_id, :binary_id) or
           r.to_actor_id == type(^actor_id, :binary_id)) and
          r.source_message_id in ^message_ids,
      order_by: [desc: r.weight, asc: r.relationship_type],
      limit: @relationship_limit,
      select: %{
        relationship_type: r.relationship_type,
        weight: r.weight,
        from_actor_id: from_actor.id,
        from_actor_handle: from_actor.handle,
        to_actor_id: to_actor.id,
        to_actor_handle: to_actor.handle,
        source_message_id: r.source_message_id
      }
    )
    |> Repo.all()
    |> Enum.map(&normalize_map_ids/1)
  end

  defp maybe_filter_message_since(query, nil), do: query

  defp maybe_filter_message_since(query, %DateTime{} = since),
    do: where(query, [m, ...], m.observed_at >= ^since)

  defp maybe_filter_message_since(query, %NaiveDateTime{} = since),
    do: where(query, [m, ...], m.observed_at >= ^since)

  defp maybe_filter_message_until(query, nil), do: query

  defp maybe_filter_message_until(query, %DateTime{} = until),
    do: where(query, [m, ...], m.observed_at <= ^until)

  defp maybe_filter_message_until(query, %NaiveDateTime{} = until),
    do: where(query, [m, ...], m.observed_at <= ^until)

  defp build_comparison_context(baseline, comparison, baseline_window, comparison_window) do
    """
    Baseline Window:
    #{window_label(baseline_window)}
    #{comparison_snapshot_text(baseline)}

    Comparison Window:
    #{window_label(comparison_window)}
    #{comparison_snapshot_text(comparison)}
    """
  end

  defp comparison_snapshot_text(snapshot) do
    """
    Summary: #{inspect(snapshot.summary)}
    Recent messages: #{Enum.map(snapshot.recent_messages || [], fn m -> m["body"] || m[:body] end) |> Enum.join(" | ")}
    Top relationships: #{Enum.map(snapshot[:top_relationships] || [], fn r -> "#{r["to_actor_handle"] || r[:to_actor_handle]}:#{r["relationship_type"] || r[:relationship_type]}" end) |> Enum.join(" | ")}
    Top channels: #{Enum.map(snapshot[:top_channels] || [], fn c -> "#{c["channel_name"] || c[:channel_name]}:#{c["message_count"] || c[:message_count]}" end) |> Enum.join(" | ")}
    Top actors: #{Enum.map(snapshot[:top_actors] || [], fn a -> "#{a["actor_handle"] || a[:actor_handle]}:#{a["message_count"] || a[:message_count]}" end) |> Enum.join(" | ")}
    Facts over time: #{Enum.map(snapshot[:facts_over_time] || [], fn f -> "#{f["day"] || f[:day]} #{f["top_fact"] || f[:top_fact]}" end) |> Enum.join(" | ")}
    """
  end

  defp window_label(window) do
    "#{format_window_value(window_value(window, :since))} -> #{format_window_value(window_value(window, :until))}"
  end

  defp window_value(window, key) when is_list(window), do: Keyword.get(window, key)
  defp window_value(window, key) when is_map(window), do: Map.get(window, key)
  defp window_value(_, _key), do: nil

  defp format_window_value(nil), do: "open"
  defp format_window_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp format_window_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp format_window_value(value), do: to_string(value)

  defp extracted_entities_for_messages(_tenant_schema, [], _limit), do: []

  defp extracted_entities_for_messages(tenant_schema, message_ids, limit) do
    source_message_ids = Enum.map(message_ids, &dump_uuid!/1)

    Repo.all(
      from(e in "extracted_entities",
        prefix: ^tenant_schema,
        where: e.source_message_id in ^source_message_ids,
        order_by: [desc: e.confidence, asc: e.name],
        limit: ^limit,
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
    |> Enum.map(&normalize_map_ids/1)
  end

  defp extracted_facts_for_messages(_tenant_schema, [], _limit), do: []

  defp extracted_facts_for_messages(tenant_schema, message_ids, limit) do
    source_message_ids = Enum.map(message_ids, &dump_uuid!/1)

    Repo.all(
      from(f in "extracted_facts",
        prefix: ^tenant_schema,
        join: m in "messages",
        on: m.id == f.source_message_id,
        prefix: ^tenant_schema,
        where: f.source_message_id in ^source_message_ids,
        order_by: [desc: f.confidence, asc: f.fact_type],
        limit: ^limit,
        select: %{
          id: f.id,
          fact_type: f.fact_type,
          subject: f.subject,
          predicate: f.predicate,
          object: f.object,
          confidence: f.confidence,
          valid_at: f.valid_at,
          metadata: f.metadata,
          source_message_id: f.source_message_id,
          source_message_observed_at: m.observed_at
        }
      )
    )
    |> Enum.map(&normalize_map_ids/1)
    |> Enum.map(&stringify_timestamps/1)
  end

  defp facts_over_time(facts) do
    facts
    |> Enum.group_by(fn fact ->
      fact_date(
        fact["valid_at"] || fact[:valid_at],
        fact["source_message_observed_at"] || fact[:source_message_observed_at]
      )
    end)
    |> Enum.map(fn {day, grouped} ->
      {{subject, predicate, object}, values} =
        grouped
        |> Enum.group_by(fn fact ->
          {
            fact["subject"] || fact[:subject],
            fact["predicate"] || fact[:predicate],
            fact["object"] || fact[:object]
          }
        end)
        |> Enum.max_by(fn {_key, entries} -> length(entries) end, fn -> {{"", "", ""}, []} end)

      %{
        day: Date.to_iso8601(day),
        fact_count: length(grouped),
        top_fact: Enum.join(Enum.reject([subject, predicate, object], &(&1 in [nil, ""])), " "),
        top_fact_count: length(values)
      }
    end)
    |> Enum.sort_by(& &1.day, :desc)
  end

  defp fact_date(valid_at, observed_at) when is_binary(valid_at) do
    case Date.from_iso8601(String.slice(valid_at, 0, 10)) do
      {:ok, date} -> date
      _ -> fact_date(nil, observed_at)
    end
  end

  defp fact_date(_valid_at, %DateTime{} = observed_at), do: DateTime.to_date(observed_at)

  defp fact_date(_valid_at, %NaiveDateTime{} = observed_at),
    do: NaiveDateTime.to_date(observed_at)

  defp fact_date(_valid_at, observed_at) when is_binary(observed_at) do
    case NaiveDateTime.from_iso8601(observed_at) do
      {:ok, value} -> NaiveDateTime.to_date(value)
      _ -> ~D[1970-01-01]
    end
  end

  defp fact_date(_valid_at, _observed_at), do: ~D[1970-01-01]

  defp neighborhood_payload(neighborhood) do
    %{
      actors: Enum.map(neighborhood.actors, &normalize_map_ids/1),
      relationships:
        Enum.map(neighborhood.relationships, fn relationship ->
          relationship
          |> normalize_map_ids()
          |> stringify_timestamps()
        end),
      messages:
        Enum.map(neighborhood.messages, fn message ->
          message
          |> normalize_map_ids()
          |> stringify_timestamps()
        end)
    }
  end

  defp normalize_map_ids(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {key, normalize_id(value)} end)
  end

  defp normalize_id(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} ->
        uuid

      :error ->
        case Ecto.UUID.load(value) do
          {:ok, uuid} -> uuid
          :error -> value
        end
    end
  end

  defp normalize_id(value), do: value

  defp dump_uuid!(value) when is_binary(value), do: Ecto.UUID.dump!(value)
  defp dump_uuid!(value), do: value

  defp stringify_timestamps(map) when is_map(map) do
    Map.new(map, fn
      {key, %DateTime{} = value} -> {key, DateTime.to_iso8601(value)}
      {key, %NaiveDateTime{} = value} -> {key, NaiveDateTime.to_iso8601(value)}
      {key, value} -> {key, value}
    end)
  end
end
