defmodule Threadr.TenantData.GraphSemantics do
  @moduledoc """
  Backend-owned graph semantics for tenant graph snapshots.

  This module computes deterministic structural metadata for each node so the
  client can render and inspect the graph without deriving its own model.
  """

  def enrich_nodes(nodes, edges) do
    adjacency = adjacency(edges, nodes)
    component_by_index = component_membership(nodes, adjacency)
    component_sizes = component_sizes(component_by_index)
    component_anchors = component_anchors(nodes, adjacency, component_by_index)
    branch_profiles = branch_profiles(nodes, adjacency, component_by_index, component_anchors)

    Enum.with_index(nodes)
    |> Enum.map(fn {node, index} ->
      incident_edges = Map.get(adjacency, index, [])
      neighbor_indices = incident_edges |> Enum.map(&neighbor_index(&1, index)) |> Enum.uniq()
      neighbor_nodes = Enum.map(neighbor_indices, &Enum.at(nodes, &1)) |> Enum.reject(&is_nil/1)

      neighbor_kind_counts = Enum.frequencies_by(neighbor_nodes, &(&1.kind || "other"))

      relationship_counts =
        Enum.frequencies_by(incident_edges, &(&1.label || &1.kind || "unknown"))

      degree = length(incident_edges)
      branch_profile = Map.fetch!(branch_profiles, index)
      hop_counts = hop_counts(index, adjacency)

      graph_profile = %{
        degree: degree,
        degree_band: degree_band(degree),
        component_id: Map.get(component_by_index, index),
        component_size: Map.get(component_sizes, Map.get(component_by_index, index), 1),
        community_id: branch_profile.community_id,
        community_role: branch_profile.community_role,
        distance_to_anchor: branch_profile.distance_to_anchor,
        one_hop_count: Map.get(hop_counts, 1, 0),
        two_hop_count: Map.get(hop_counts, 2, 0),
        three_hop_count: Map.get(hop_counts, 3, 0),
        dominant_neighbor_kind: dominant_key(neighbor_kind_counts, "none"),
        dominant_relationship: dominant_key(relationship_counts, "none"),
        adjacent_labels: Enum.take(Enum.map(neighbor_nodes, &(&1.label || &1.id)), 5),
        adjacent_count: length(neighbor_indices),
        relationship_counts: relationship_counts
      }

      Map.update!(node, :details, fn details ->
        Map.put(details, :graph_profile, graph_profile)
      end)
    end)
  end

  defp adjacency(edges, nodes) do
    base = Map.new(Enum.with_index(nodes), fn {_node, index} -> {index, []} end)

    Enum.reduce(edges, base, fn edge, acc ->
      acc
      |> Map.update!(edge.source, &[edge | &1])
      |> Map.update!(edge.target, &[edge | &1])
    end)
  end

  defp component_membership(nodes, adjacency) do
    indices =
      if nodes == [] do
        []
      else
        Enum.to_list(0..(length(nodes) - 1))
      end

    {component_map, _visited, _next_component} =
      Enum.reduce(indices, {%{}, MapSet.new(), 1}, fn index, {acc, visited, component_id} ->
        if MapSet.member?(visited, index) do
          {acc, visited, component_id}
        else
          {members, visited} = walk_component(index, adjacency, visited, [])

          component_map =
            Enum.reduce(members, acc, fn member, inner_acc ->
              Map.put(inner_acc, member, component_id)
            end)

          {component_map, visited, component_id + 1}
        end
      end)

    component_map
  end

  defp component_sizes(component_by_index) do
    component_by_index
    |> Enum.frequencies_by(fn {_index, component_id} -> component_id end)
  end

  defp component_anchors(nodes, adjacency, component_by_index) do
    nodes
    |> Enum.with_index()
    |> Enum.group_by(fn {_node, index} -> Map.get(component_by_index, index) end)
    |> Map.new(fn {component_id, entries} ->
      anchor_index =
        entries
        |> Enum.max_by(fn {node, index} ->
          {degree(index, adjacency), -kind_priority(node), invert_label(sort_label(node))}
        end)
        |> elem(1)

      {component_id, anchor_index}
    end)
  end

  defp branch_profiles(nodes, adjacency, component_by_index, component_anchors) do
    nodes
    |> Enum.with_index()
    |> Enum.group_by(fn {_node, index} -> Map.get(component_by_index, index) end)
    |> Enum.reduce(%{}, fn {component_id, entries}, acc ->
      indices = Enum.map(entries, &elem(&1, 1))
      anchor_index = Map.fetch!(component_anchors, component_id)

      component_profiles =
        build_component_branch_profiles(component_id, indices, anchor_index, nodes, adjacency)

      Map.merge(acc, component_profiles)
    end)
  end

  defp build_component_branch_profiles(component_id, indices, anchor_index, nodes, adjacency) do
    base = %{
      anchor_index => %{
        community_id: "#{component_id}:core",
        community_role: "anchor",
        distance_to_anchor: 0
      }
    }

    ordered_neighbors =
      adjacency
      |> Map.get(anchor_index, [])
      |> Enum.map(&neighbor_index(&1, anchor_index))
      |> Enum.filter(&(&1 in indices))
      |> Enum.uniq()
      |> Enum.sort_by(fn index ->
        node = Enum.at(nodes, index)
        {-degree(index, adjacency), kind_priority(node), sort_label(node)}
      end)

    queue =
      ordered_neighbors
      |> Enum.with_index(1)
      |> Enum.map(fn {index, position} ->
        {index, anchor_index, 1, "#{component_id}:#{position}"}
      end)
      |> :queue.from_list()

    assigned = MapSet.new([anchor_index])
    seeded = Enum.reduce(ordered_neighbors, assigned, &MapSet.put(&2, &1))

    base =
      Enum.with_index(ordered_neighbors, 1)
      |> Enum.reduce(base, fn {index, position}, acc ->
        Map.put(acc, index, %{
          community_id: "#{component_id}:#{position}",
          community_role: "branch",
          distance_to_anchor: 1
        })
      end)

    profiles = walk_branch_queue(queue, seeded, base, nodes, adjacency)

    fill_unassigned_branch_profiles(profiles, indices, anchor_index, component_id)
    |> assign_community_roles(indices, adjacency)
  end

  defp walk_branch_queue(queue, assigned, profiles, nodes, adjacency) do
    case :queue.out(queue) do
      {:empty, _queue} ->
        profiles

      {{:value, {index, parent_index, distance, community_id}}, queue} ->
        neighbors =
          adjacency
          |> Map.get(index, [])
          |> Enum.map(&neighbor_index(&1, index))
          |> Enum.reject(&(&1 == parent_index))
          |> Enum.uniq()
          |> Enum.sort_by(fn neighbor_index ->
            node = Enum.at(nodes, neighbor_index)
            {-degree(neighbor_index, adjacency), kind_priority(node), sort_label(node)}
          end)

        {queue, assigned, profiles} =
          Enum.reduce(neighbors, {queue, assigned, profiles}, fn neighbor_index,
                                                                 {queue, assigned, profiles} ->
            if MapSet.member?(assigned, neighbor_index) do
              {queue, assigned, profiles}
            else
              profile = %{
                community_id: community_id,
                community_role: "branch",
                distance_to_anchor: distance + 1
              }

              {
                :queue.in({neighbor_index, index, distance + 1, community_id}, queue),
                MapSet.put(assigned, neighbor_index),
                Map.put(profiles, neighbor_index, profile)
              }
            end
          end)

        walk_branch_queue(queue, assigned, profiles, nodes, adjacency)
    end
  end

  defp fill_unassigned_branch_profiles(profiles, indices, anchor_index, component_id) do
    Enum.reduce(indices, profiles, fn index, acc ->
      Map.put_new(acc, index, %{
        community_id:
          if index == anchor_index do
            "#{component_id}:core"
          else
            "#{component_id}:isolated"
          end,
        community_role:
          if index == anchor_index do
            "anchor"
          else
            "isolated"
          end,
        distance_to_anchor:
          if index == anchor_index do
            0
          else
            nil
          end
      })
    end)
  end

  defp assign_community_roles(profiles, indices, adjacency) do
    Enum.reduce(indices, profiles, fn index, acc ->
      profile = Map.fetch!(acc, index)

      updated_role =
        cond do
          profile.community_role == "anchor" ->
            "anchor"

          profile.community_role == "isolated" ->
            "isolated"

          bridge_node?(index, adjacency, acc, profile.community_id) ->
            "bridge"

          profile.distance_to_anchor && profile.distance_to_anchor >= 3 ->
            "peripheral"

          true ->
            "branch"
        end

      Map.update!(acc, index, &Map.put(&1, :community_role, updated_role))
    end)
  end

  defp bridge_node?(index, adjacency, profiles, own_community_id) do
    adjacency
    |> Map.get(index, [])
    |> Enum.map(&neighbor_index(&1, index))
    |> Enum.map(fn neighbor_index ->
      profiles |> Map.fetch!(neighbor_index) |> Map.get(:community_id)
    end)
    |> Enum.uniq()
    |> Enum.reject(&(&1 == own_community_id))
    |> Kernel.!=([])
  end

  defp hop_counts(start_index, adjacency) do
    queue = :queue.from_list([{start_index, 0}])
    visited = MapSet.new([start_index])
    counts = %{1 => 0, 2 => 0, 3 => 0}

    walk_hops(queue, visited, counts, adjacency)
  end

  defp walk_hops(queue, visited, counts, adjacency) do
    case :queue.out(queue) do
      {:empty, _queue} ->
        counts

      {{:value, {index, distance}}, queue} ->
        if distance >= 3 do
          walk_hops(queue, visited, counts, adjacency)
        else
          {queue, visited, counts} =
            adjacency
            |> Map.get(index, [])
            |> Enum.map(&neighbor_index(&1, index))
            |> Enum.uniq()
            |> Enum.reduce({queue, visited, counts}, fn neighbor_index,
                                                        {queue, visited, counts} ->
              if MapSet.member?(visited, neighbor_index) do
                {queue, visited, counts}
              else
                next_distance = distance + 1

                {
                  :queue.in({neighbor_index, next_distance}, queue),
                  MapSet.put(visited, neighbor_index),
                  Map.update!(counts, next_distance, &(&1 + 1))
                }
              end
            end)

          walk_hops(queue, visited, counts, adjacency)
        end
    end
  end

  defp walk_component(index, adjacency, visited, members) do
    if MapSet.member?(visited, index) do
      {members, visited}
    else
      visited = MapSet.put(visited, index)
      members = [index | members]

      Map.get(adjacency, index, [])
      |> Enum.map(&neighbor_index(&1, index))
      |> Enum.uniq()
      |> Enum.reduce({members, visited}, fn neighbor, {inner_members, inner_visited} ->
        walk_component(neighbor, adjacency, inner_visited, inner_members)
      end)
    end
  end

  defp degree(index, adjacency), do: adjacency |> Map.get(index, []) |> length()

  defp neighbor_index(edge, index) when edge.source == index, do: edge.target
  defp neighbor_index(edge, _index), do: edge.source

  defp degree_band(degree) when degree >= 8, do: "hub"
  defp degree_band(degree) when degree >= 4, do: "mid"
  defp degree_band(degree) when degree >= 1, do: "leaf"
  defp degree_band(_degree), do: "isolated"

  defp dominant_key(map, fallback) when map == %{}, do: fallback

  defp dominant_key(map, _fallback) do
    map
    |> Enum.max_by(fn {_key, value} -> value end)
    |> elem(0)
  end

  defp kind_priority(%{kind: "actor"}), do: 0
  defp kind_priority(%{kind: "channel"}), do: 1
  defp kind_priority(%{kind: "message"}), do: 2
  defp kind_priority(_node), do: 3

  defp sort_label(node), do: String.downcase(to_string(node.label || node.id || "node"))

  defp invert_label(label) do
    label
    |> to_charlist()
    |> Enum.map(&(-&1))
  end
end
