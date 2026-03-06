defmodule Threadr.TenantData.GraphSnapshot do
  @moduledoc """
  Builds tenant-scoped graph exploration snapshots for the deck.gl client.
  """

  import Ecto.Query

  alias Threadr.Repo
  alias Threadr.TenantData.GraphSnapshot.Native

  @schema_version 1
  @actor_state 0
  @channel_state 1

  def schema_version, do: @schema_version

  def latest_snapshot(%{schema_name: schema_name} = tenant) when is_binary(schema_name) do
    projection = build_projection(schema_name)
    generated_at = DateTime.utc_now()
    revision = snapshot_revision(tenant, projection)

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

  defp build_projection(prefix) do
    actors = actors(prefix)
    channels = channels(prefix)
    actor_message_counts = grouped_counts(prefix, "messages", :actor_id)
    channel_message_counts = grouped_counts(prefix, "messages", :channel_id)
    actor_relationship_weights = actor_relationship_weights(prefix)

    actor_nodes =
      actors
      |> Enum.sort_by(&display_label(&1))
      |> ring_layout(320.0)
      |> Enum.map(fn {actor, {x, y}} ->
        message_count = Map.get(actor_message_counts, actor.id, 0)
        size = node_size(message_count + Map.get(actor_relationship_weights, actor.id, 0))

        %{
          id: actor.id,
          label: display_label(actor),
          kind: "actor",
          state: @actor_state,
          size: size,
          x: x,
          y: y,
          details_json:
            Jason.encode!(%{
              id: actor.id,
              type: "actor",
              platform: actor.platform,
              handle: actor.handle,
              display_name: actor.display_name,
              external_id: actor.external_id,
              message_count: message_count,
              last_seen_at: actor.last_seen_at
            })
        }
      end)

    channel_nodes =
      channels
      |> Enum.sort_by(& &1.name)
      |> ring_layout(140.0)
      |> Enum.map(fn {channel, {x, y}} ->
        message_count = Map.get(channel_message_counts, channel.id, 0)

        %{
          id: channel.id,
          label: channel.name,
          kind: "channel",
          state: @channel_state,
          size: node_size(message_count),
          x: x,
          y: y,
          details_json:
            Jason.encode!(%{
              id: channel.id,
              type: "channel",
              platform: channel.platform,
              name: channel.name,
              external_id: channel.external_id,
              message_count: message_count
            })
        }
      end)

    nodes = actor_nodes ++ channel_nodes
    node_index = Map.new(Enum.with_index(nodes), fn {node, index} -> {node.id, index} end)

    relationship_edges = relationship_edges(prefix, node_index)
    participation_edges = participation_edges(prefix, node_index)

    %{
      nodes: nodes,
      edges: relationship_edges ++ participation_edges
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

  defp grouped_counts(prefix, table, key) do
    Repo.all(
      from(row in table,
        prefix: ^prefix,
        group_by: field(row, ^key),
        select: {field(row, ^key), count("*")}
      )
    )
    |> Map.new(fn {id, count} -> {normalize_id(id), count} end)
  end

  defp actor_relationship_weights(prefix) do
    outgoing =
      Repo.all(
        from(r in "relationships",
          prefix: ^prefix,
          group_by: r.from_actor_id,
          select: {r.from_actor_id, sum(r.weight)}
        )
      )

    incoming =
      Repo.all(
        from(r in "relationships",
          prefix: ^prefix,
          group_by: r.to_actor_id,
          select: {r.to_actor_id, sum(r.weight)}
        )
      )

    (outgoing ++ incoming)
    |> Enum.reduce(%{}, fn {actor_id, weight}, acc ->
      Map.update(acc, normalize_id(actor_id), weight || 0, &(&1 + (weight || 0)))
    end)
  end

  defp relationship_edges(prefix, node_index) do
    Repo.all(
      from(r in "relationships",
        prefix: ^prefix,
        select: %{
          from_actor_id: r.from_actor_id,
          to_actor_id: r.to_actor_id,
          relationship_type: r.relationship_type,
          weight: r.weight
        }
      )
    )
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

  defp participation_edges(prefix, node_index) do
    Repo.all(
      from(m in "messages",
        prefix: ^prefix,
        group_by: [m.actor_id, m.channel_id],
        select: %{
          actor_id: m.actor_id,
          channel_id: m.channel_id,
          message_count: count("*")
        }
      )
    )
    |> Enum.flat_map(fn edge ->
      with {:ok, source} <- fetch_node_index(node_index, normalize_id(edge.actor_id)),
           {:ok, target} <- fetch_node_index(node_index, normalize_id(edge.channel_id)) do
        [
          %{
            source: source,
            target: target,
            weight: edge.message_count,
            label: "participates_in",
            kind: "participation"
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

  defp ring_layout(items, radius) do
    count = length(items)

    Enum.with_index(items)
    |> Enum.map(fn {item, index} ->
      angle =
        if count <= 1 do
          0.0
        else
          2.0 * :math.pi() * index / count
        end

      {item, {radius * :math.cos(angle), radius * :math.sin(angle)}}
    end)
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

  defp normalize_id(value) when is_binary(value) do
    case Ecto.UUID.load(value) do
      {:ok, uuid} -> uuid
      :error -> value
    end
  end

  defp normalize_id(value), do: value

  defp build_bitmaps(nodes) do
    states = Enum.map(nodes, & &1.state)

    case Native.build_roaring_bitmaps(states) do
      {root, affected, healthy, unknown, {root_count, affected_count, healthy_count, unknown_count}} ->
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
        {node.x, node.y, node.state, node.label, node.kind, node.size, node.details_json}
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

  defp snapshot_revision(%{subject_name: subject_name}, projection) do
    payload =
      Jason.encode!(%{
        tenant: subject_name,
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
end
