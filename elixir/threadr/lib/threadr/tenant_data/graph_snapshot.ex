defmodule Threadr.TenantData.GraphSnapshot do
  @moduledoc """
  Builds tenant-scoped graph exploration snapshots for the deck.gl client.
  """

  import Ecto.Query

  alias Threadr.Repo
  alias Threadr.TenantData.GraphLayout
  alias Threadr.TenantData.GraphSemantics
  alias Threadr.TenantData.GraphSnapshot.Native

  @schema_version 1
  @actor_state 0
  @channel_state 1
  @message_state 2
  @conversation_state 3
  @conversation_gap_minutes 20

  def schema_version, do: @schema_version

  def latest_snapshot(%{schema_name: schema_name} = tenant, window \\ %{}) when is_binary(schema_name) do
    projection = build_projection(schema_name, window)
    generated_at = DateTime.utc_now()
    revision = snapshot_revision(tenant, projection, window)

    with {:ok, bitmaps} <- build_bitmaps(projection.nodes),
         {:ok, payload} <- encode_payload(revision, projection, bitmaps) do
      {:ok,
       %{
         snapshot: %{
           schema_version: @schema_version,
           revision: revision,
           generated_at: generated_at,
           node_count: length(projection.nodes),
           edge_count: length(projection.edges),
           bitmap_metadata: bitmap_metadata(bitmaps)
         },
         payload: payload
       }}
    end
  end

  defp build_projection(prefix, window) do
    actors = actors(prefix)
    channels = channels(prefix)
    messages = recent_messages(prefix, window)
    channel_lookup = Map.new(channels, &{&1.id, &1})
    conversations = conversations(messages, channel_lookup)
    actor_message_counts = grouped_counts(prefix, "messages", :actor_id, window)
    channel_message_counts = grouped_counts(prefix, "messages", :channel_id, window)
    actor_relationship_weights = actor_relationship_weights(prefix, window)

    actor_nodes =
      actors
      |> Enum.sort_by(&display_label(&1))
      |> Enum.with_index()
      |> Enum.map(fn {actor, index} ->
        message_count = Map.get(actor_message_counts, actor.id, 0)
        size = node_size(message_count + Map.get(actor_relationship_weights, actor.id, 0))

        %{
          index: index,
          id: actor.id,
          label: display_label(actor),
          kind: "actor",
          state: @actor_state,
          size: size,
          x: 0.0,
          y: 0.0,
          details: %{
            id: actor.id,
            type: "actor",
            platform: actor.platform,
            handle: actor.handle,
            display_name: actor.display_name,
            external_id: actor.external_id,
            message_count: message_count,
            last_seen_at: actor.last_seen_at
          }
        }
      end)

    channel_nodes =
      channels
      |> Enum.sort_by(& &1.name)
      |> Enum.with_index(length(actor_nodes))
      |> Enum.map(fn {channel, index} ->
        message_count = Map.get(channel_message_counts, channel.id, 0)

        %{
          index: index,
          id: channel.id,
          label: channel.name,
          kind: "channel",
          state: @channel_state,
          size: node_size(message_count),
          x: 0.0,
          y: 0.0,
          details: %{
            id: channel.id,
            type: "channel",
            platform: channel.platform,
            name: channel.name,
            external_id: channel.external_id,
            message_count: message_count
          }
        }
      end)

    real_conversations = Enum.filter(conversations, &real_conversation?/1)

    conversation_nodes =
      real_conversations
      |> Enum.sort_by(&{&1.channel_name || "", sortable_observed_at(%{observed_at: &1.started_at})})
      |> Enum.with_index(length(actor_nodes) + length(channel_nodes))
      |> Enum.map(fn {conversation, index} ->
        %{
          index: index,
          id: conversation.id,
          label: "Conversation",
          kind: "conversation",
          state: @conversation_state,
          size: node_size(conversation.message_count),
          x: 0.0,
          y: 0.0,
          details: %{
            id: conversation.id,
            type: "conversation",
            channel_id: conversation.channel_id,
            channel_name: conversation.channel_name,
            actor_ids: conversation.actor_ids,
            actor_count: length(conversation.actor_ids),
            message_ids: conversation.message_ids,
            message_count: conversation.message_count,
            started_at: conversation.started_at,
            ended_at: conversation.ended_at,
            external_id: conversation.id
          }
        }
      end)

    message_nodes =
      messages
      |> Enum.sort_by(&sortable_observed_at/1, :desc)
      |> Enum.with_index(length(actor_nodes) + length(channel_nodes) + length(conversation_nodes))
      |> Enum.map(fn {message, index} ->
        %{
          index: index,
          id: message.id,
          label: message_label(message),
          kind: "message",
          state: @message_state,
          size: node_size(1),
          x: 0.0,
          y: 0.0,
          details: %{
            id: message.id,
            type: "message",
            body: message.body,
            external_id: message.external_id,
            observed_at: message.observed_at,
            actor_id: message.actor_id,
            channel_id: message.channel_id
          }
        }
      end)

    nodes = actor_nodes ++ channel_nodes ++ conversation_nodes ++ message_nodes
    node_index = Map.new(Enum.with_index(nodes), fn {node, index} -> {node.id, index} end)

    relationship_edges = relationship_edges(prefix, node_index, window)
    actor_channel_edges = actor_channel_edges(prefix, node_index, window)
    conversation_channel_edges = conversation_channel_edges(real_conversations, node_index)
    actor_conversation_edges = actor_conversation_edges(real_conversations, node_index)
    conversation_message_edges = conversation_message_edges(real_conversations, node_index)
    authored_edges = authored_edges(messages, node_index)
    in_channel_edges = in_channel_edges(messages, node_index)
    edges =
      relationship_edges ++
        actor_channel_edges ++
        conversation_channel_edges ++
        actor_conversation_edges ++
        conversation_message_edges ++
        authored_edges ++ in_channel_edges
    nodes = GraphSemantics.enrich_nodes(nodes, edges)
    nodes = GraphLayout.layout(nodes, edges)

    %{
      nodes: nodes,
      edges: edges
    }
  end

  defp actors(prefix) do
    Repo.all(
      from(a in "actors",
        prefix: ^prefix,
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
    |> Enum.map(fn actor -> %{actor | id: normalize_id(actor.id)} end)
  end

  defp channels(prefix) do
    Repo.all(
      from(c in "channels",
        prefix: ^prefix,
        select: %{
          id: c.id,
          platform: c.platform,
          name: c.name,
          external_id: c.external_id
        }
      )
    )
    |> Enum.map(fn channel -> %{channel | id: normalize_id(channel.id)} end)
  end

  defp recent_messages(prefix, window) do
    from(m in "messages",
      prefix: ^prefix,
      order_by: [desc: m.observed_at, desc: m.inserted_at],
      limit: 120,
      select: %{
        id: m.id,
        external_id: m.external_id,
        body: m.body,
        observed_at: m.observed_at,
        actor_id: m.actor_id,
        channel_id: m.channel_id
      }
    )
    |> maybe_filter_message_since(window_value(window, :since))
    |> maybe_filter_message_until(window_value(window, :until))
    |> Repo.all()
    |> Enum.map(fn message ->
      %{
        message
        | id: normalize_id(message.id),
          actor_id: normalize_id(message.actor_id),
          channel_id: normalize_id(message.channel_id)
      }
    end)
  end

  defp conversations(messages, channel_lookup) do
    messages
    |> Enum.group_by(& &1.channel_id)
    |> Enum.flat_map(fn {channel_id, channel_messages} ->
      channel_name = Map.get(channel_lookup, channel_id, %{}) |> Map.get(:name)

      channel_messages
      |> Enum.sort_by(&sortable_observed_at/1)
      |> Enum.reduce({[], nil}, fn message, {groups, current} ->
        cond do
          is_nil(current) ->
            {groups, start_conversation(message, channel_name)}

          same_conversation?(current, message) ->
            {groups, append_to_conversation(current, message)}

          true ->
            {[current | groups], start_conversation(message, channel_name)}
        end
      end)
      |> finalize_conversations()
      |> Enum.map(&finalize_conversation(&1, channel_id))
    end)
  end

  defp start_conversation(message, channel_name) do
    %{
      channel_name: channel_name,
      first_message_id: message.id,
      last_message_id: message.id,
      message_ids: [message.id],
      actor_ids: MapSet.new([message.actor_id]),
      message_count: 1,
      started_at: message.observed_at,
      ended_at: message.observed_at
    }
  end

  defp append_to_conversation(conversation, message) do
    %{
      conversation
      | last_message_id: message.id,
        message_ids: [message.id | conversation.message_ids],
        actor_ids: MapSet.put(conversation.actor_ids, message.actor_id),
        message_count: conversation.message_count + 1,
        ended_at: message.observed_at
    }
  end

  defp finalize_conversations({groups, nil}), do: Enum.reverse(groups)
  defp finalize_conversations({groups, current}), do: Enum.reverse([current | groups])

  defp finalize_conversation(conversation, channel_id) do
    actor_ids =
      conversation.actor_ids
      |> MapSet.to_list()
      |> Enum.sort()

    message_ids = Enum.reverse(conversation.message_ids)

    id =
      conversation_id(
        channel_id,
        conversation.first_message_id,
        conversation.last_message_id,
        conversation.started_at,
        conversation.ended_at
      )

    %{
      id: id,
      channel_id: channel_id,
      channel_name: conversation.channel_name,
      actor_ids: actor_ids,
      actor_count: length(actor_ids),
      message_ids: message_ids,
      message_count: conversation.message_count,
      started_at: conversation.started_at,
      ended_at: conversation.ended_at
    }
  end

  defp real_conversation?(conversation) do
    (conversation.actor_count || length(conversation.actor_ids || [])) >= 2
  end

  defp same_conversation?(conversation, message) do
    previous = conversation.ended_at
    current = message.observed_at

    cond do
      is_nil(previous) or is_nil(current) ->
        false

      match?(%NaiveDateTime{}, previous) and match?(%NaiveDateTime{}, current) ->
        NaiveDateTime.diff(current, previous, :minute) <= @conversation_gap_minutes

      true ->
        false
    end
  end

  defp conversation_id(channel_id, first_message_id, last_message_id, started_at, ended_at) do
    raw =
      [
        normalize_id(channel_id),
        normalize_id(first_message_id),
        normalize_id(last_message_id),
        encode_window_value(started_at),
        encode_window_value(ended_at)
      ]
      |> Enum.join(":")

    "conversation:" <> Base.url_encode64(:crypto.hash(:sha256, raw), padding: false)
  end

  defp sortable_observed_at(%{observed_at: %DateTime{} = observed_at}),
    do: DateTime.to_unix(observed_at, :microsecond)

  defp sortable_observed_at(%{observed_at: %NaiveDateTime{} = observed_at}),
    do: NaiveDateTime.diff(observed_at, ~N[1970-01-01 00:00:00], :microsecond)

  defp sortable_observed_at(%{observed_at: nil}), do: 0
  defp sortable_observed_at(%{observed_at: _value}), do: 0

  defp grouped_counts(prefix, table, key, window) do
    from(row in table,
      prefix: ^prefix,
      group_by: field(row, ^key),
      select: {field(row, ^key), count("*")}
    )
    |> maybe_filter_message_since(window_value(window, :since))
    |> maybe_filter_message_until(window_value(window, :until))
    |> Repo.all()
    |> Map.new(fn {id, count} -> {normalize_id(id), count} end)
  end

  defp actor_relationship_weights(prefix, window) do
    outgoing =
      from(r in "relationships",
        prefix: ^prefix,
        join: m in "messages",
        on: m.id == r.source_message_id,
        prefix: ^prefix,
        group_by: r.from_actor_id,
        select: {r.from_actor_id, sum(r.weight)}
      )
      |> maybe_filter_joined_message_since(window_value(window, :since))
      |> maybe_filter_joined_message_until(window_value(window, :until))
      |> Repo.all()

    incoming =
      from(r in "relationships",
        prefix: ^prefix,
        join: m in "messages",
        on: m.id == r.source_message_id,
        prefix: ^prefix,
        group_by: r.to_actor_id,
        select: {r.to_actor_id, sum(r.weight)}
      )
      |> maybe_filter_joined_message_since(window_value(window, :since))
      |> maybe_filter_joined_message_until(window_value(window, :until))
      |> Repo.all()

    (outgoing ++ incoming)
    |> Enum.reduce(%{}, fn {actor_id, weight}, acc ->
      Map.update(acc, normalize_id(actor_id), weight || 0, &(&1 + (weight || 0)))
    end)
  end

  defp relationship_edges(prefix, node_index, window) do
    from(r in "relationships",
      prefix: ^prefix,
      join: m in "messages",
      on: m.id == r.source_message_id,
      prefix: ^prefix,
      select: %{
        from_actor_id: r.from_actor_id,
        to_actor_id: r.to_actor_id,
        relationship_type: r.relationship_type,
        weight: r.weight
      }
    )
    |> maybe_filter_joined_message_since(window_value(window, :since))
    |> maybe_filter_joined_message_until(window_value(window, :until))
    |> Repo.all()
    |> Enum.flat_map(fn edge ->
      with {:ok, source} <- fetch_node_index(node_index, normalize_id(edge.from_actor_id)),
           {:ok, target} <- fetch_node_index(node_index, normalize_id(edge.to_actor_id)) do
        [
          %{
            source: source,
            target: target,
            weight: edge.weight,
            label: edge.relationship_type,
            kind: "relationship"
          }
        ]
      else
        _ -> []
      end
    end)
  end

  defp actor_channel_edges(prefix, node_index, window) do
    from(m in "messages",
      prefix: ^prefix,
      group_by: [m.actor_id, m.channel_id],
      select: %{
        actor_id: m.actor_id,
        channel_id: m.channel_id,
        weight: count("*")
      }
    )
    |> maybe_filter_message_since(window_value(window, :since))
    |> maybe_filter_message_until(window_value(window, :until))
    |> Repo.all()
    |> Enum.flat_map(fn edge ->
      with {:ok, source} <- fetch_node_index(node_index, normalize_id(edge.actor_id)),
           {:ok, target} <- fetch_node_index(node_index, normalize_id(edge.channel_id)) do
        [
          %{
            source: source,
            target: target,
            weight: edge.weight,
            label: "ACTIVE_IN",
            kind: "relationship"
          }
        ]
      else
        _ -> []
      end
    end)
  end

  defp conversation_channel_edges(conversations, node_index) do
    conversations
    |> Enum.flat_map(fn conversation ->
      with {:ok, source} <- fetch_node_index(node_index, conversation.channel_id),
           {:ok, target} <- fetch_node_index(node_index, conversation.id) do
        [
          %{
            source: source,
            target: target,
            weight: conversation.message_count,
            label: "contains",
            kind: "conversation"
          }
        ]
      else
        _ -> []
      end
    end)
  end

  defp actor_conversation_edges(conversations, node_index) do
    conversations
    |> Enum.flat_map(fn conversation ->
      Enum.flat_map(conversation.actor_ids, fn actor_id ->
        with {:ok, source} <- fetch_node_index(node_index, actor_id),
             {:ok, target} <- fetch_node_index(node_index, conversation.id) do
          [
            %{
              source: source,
              target: target,
              weight: 1,
              label: "participated_in",
              kind: "conversation"
            }
          ]
        else
          _ -> []
        end
      end)
    end)
  end

  defp conversation_message_edges(conversations, node_index) do
    conversations
    |> Enum.flat_map(fn conversation ->
      Enum.flat_map(conversation.message_ids, fn message_id ->
        with {:ok, source} <- fetch_node_index(node_index, conversation.id),
             {:ok, target} <- fetch_node_index(node_index, message_id) do
          [
            %{
              source: source,
              target: target,
              weight: 1,
              label: "contains",
              kind: "conversation"
            }
          ]
        else
          _ -> []
        end
      end)
    end)
  end

  defp authored_edges(messages, node_index) do
    messages
    |> Enum.flat_map(fn edge ->
      with {:ok, source} <- fetch_node_index(node_index, edge.actor_id),
           {:ok, target} <- fetch_node_index(node_index, edge.id) do
        [
          %{
            source: source,
            target: target,
            weight: 1,
            label: "authored",
            kind: "authored"
          }
        ]
      else
        _ -> []
      end
    end)
  end

  defp in_channel_edges(messages, node_index) do
    messages
    |> Enum.flat_map(fn edge ->
      with {:ok, source} <- fetch_node_index(node_index, edge.id),
           {:ok, target} <- fetch_node_index(node_index, edge.channel_id) do
        [
          %{
            source: source,
            target: target,
            weight: 1,
            label: "in_channel",
            kind: "in_channel"
          }
        ]
      else
        _ -> []
      end
    end)
  end

  defp fetch_node_index(node_index, id) do
    case Map.fetch(node_index, id) do
      {:ok, value} -> {:ok, value}
      :error -> :error
    end
  end

  defp node_size(weight) do
    weight
    |> Kernel.+(1)
    |> :math.log10()
    |> Kernel.*(10.0)
    |> Kernel.+(8.0)
  end

  defp display_label(%{display_name: display_name, handle: _handle})
       when is_binary(display_name) and display_name != "",
       do: display_name

  defp display_label(%{handle: handle}) when is_binary(handle) and handle != "", do: handle
  defp display_label(%{name: name}) when is_binary(name) and name != "", do: name
  defp display_label(%{id: id}), do: id

  defp message_label(_message), do: "Message"

  defp normalize_id(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> uuid
      :error -> value
    end
  end

  defp normalize_id(value), do: value

  defp build_bitmaps(nodes) do
    states = Enum.map(nodes, & &1.state)

    case Native.build_roaring_bitmaps(states) do
      {root, affected, healthy, unknown,
       {root_count, affected_count, healthy_count, unknown_count}} ->
        {:ok,
         %{
           root: root,
           affected: affected,
           healthy: healthy,
           unknown: unknown,
           counts: %{
             root: root_count,
             affected: affected_count,
             healthy: healthy_count,
             unknown: unknown_count
           }
         }}

      other ->
        {:error, {:bitmap_encode_failed, other}}
    end
  end

  defp encode_payload(revision, projection, bitmaps) do
    nodes =
      Enum.map(projection.nodes, fn node ->
        {node.x, node.y, node.state, node.label, node.kind, node.size,
         Jason.encode!(node.details)}
      end)

    edges =
      Enum.map(projection.edges, fn edge ->
        {edge.source, edge.target, edge.weight, edge.label, edge.kind}
      end)

    bitmap_sizes = [
      byte_size(bitmaps.root),
      byte_size(bitmaps.affected),
      byte_size(bitmaps.healthy),
      byte_size(bitmaps.unknown)
    ]

    case Native.encode_snapshot(@schema_version, revision, nodes, edges, bitmap_sizes) do
      payload when is_binary(payload) -> {:ok, payload}
      other -> {:error, {:snapshot_encode_failed, other}}
    end
  end

  defp bitmap_metadata(bitmaps) do
    %{
      root_cause: %{bytes: byte_size(bitmaps.root), count: bitmaps.counts.root},
      affected: %{bytes: byte_size(bitmaps.affected), count: bitmaps.counts.affected},
      healthy: %{bytes: byte_size(bitmaps.healthy), count: bitmaps.counts.healthy},
      unknown: %{bytes: byte_size(bitmaps.unknown), count: bitmaps.counts.unknown}
    }
  end

  defp snapshot_revision(%{subject_name: subject_name}, projection, window) do
    payload =
      Jason.encode!(%{
        tenant: subject_name,
        window: %{
          since: encode_window_value(window_value(window, :since)),
          until: encode_window_value(window_value(window, :until))
        },
        nodes:
          Enum.map(projection.nodes, fn node ->
            %{id: node.id, state: node.state, size: Float.round(node.size, 2)}
          end),
        edges:
          Enum.map(projection.edges, fn edge ->
            %{source: edge.source, target: edge.target, weight: edge.weight, kind: edge.kind}
          end)
      })

    payload
    |> then(&:crypto.hash(:sha256, &1))
    |> binary_part(0, 8)
    |> :binary.decode_unsigned()
  end

  defp maybe_filter_message_since(query, nil), do: query
  defp maybe_filter_message_since(query, %NaiveDateTime{} = since), do: where(query, [m], m.observed_at >= ^since)
  defp maybe_filter_message_since(query, %DateTime{} = since), do: where(query, [m], m.observed_at >= ^since)

  defp maybe_filter_message_until(query, nil), do: query
  defp maybe_filter_message_until(query, %NaiveDateTime{} = until), do: where(query, [m], m.observed_at <= ^until)
  defp maybe_filter_message_until(query, %DateTime{} = until), do: where(query, [m], m.observed_at <= ^until)

  defp maybe_filter_joined_message_since(query, nil), do: query
  defp maybe_filter_joined_message_since(query, %NaiveDateTime{} = since), do: where(query, [_, m], m.observed_at >= ^since)
  defp maybe_filter_joined_message_since(query, %DateTime{} = since), do: where(query, [_, m], m.observed_at >= ^since)

  defp maybe_filter_joined_message_until(query, nil), do: query
  defp maybe_filter_joined_message_until(query, %NaiveDateTime{} = until), do: where(query, [_, m], m.observed_at <= ^until)
  defp maybe_filter_joined_message_until(query, %DateTime{} = until), do: where(query, [_, m], m.observed_at <= ^until)

  defp window_value(window, key) when is_list(window), do: Keyword.get(window, key)
  defp window_value(window, key) when is_map(window), do: Map.get(window, key)
  defp window_value(_, _key), do: nil

  defp encode_window_value(nil), do: nil
  defp encode_window_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp encode_window_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp encode_window_value(value), do: to_string(value)
end
