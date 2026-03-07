defmodule Threadr.TenantData.GraphLayout do
  @moduledoc """
  Deterministic backend-owned graph layout for tenant exploration snapshots.

  Layout is component-aware and degree-aware:
  - connected components are positioned on a stable global grid
  - high-degree nodes anchor near the component center
  - traversal depth determines shell distance from the anchor
  - sibling nodes remain close to their parent branch for readable neighborhoods
  """

  @component_spacing 560.0
  @shell_spacing 120.0

  def layout(nodes, _edges) when nodes == [], do: []

  def layout(nodes, edges) do
    adjacency = adjacency(edges, length(nodes))

    components =
      nodes
      |> Enum.group_by(&component_id/1)
      |> Enum.sort_by(fn {component_id, component_nodes} ->
        {-length(component_nodes), component_id,
         Enum.min_by(component_nodes, &sort_label/1).label}
      end)

    columns =
      components
      |> length()
      |> :math.sqrt()
      |> ceil()
      |> max(1)

    components
    |> Enum.with_index()
    |> Enum.flat_map(fn {{_component_id, component_nodes}, component_index} ->
      center = component_center(component_index, columns)
      layout_component(component_nodes, center, adjacency)
    end)
    |> Enum.sort_by(& &1.index)
  end

  defp layout_component(nodes, {center_x, center_y}, adjacency) do
    nodes_by_index = Map.new(nodes, &{&1.index, &1})
    anchor = anchor_node(nodes)
    traversal = traversal_profile(anchor.index, nodes_by_index, adjacency)

    Enum.map(nodes, fn node ->
      profile = Map.fetch!(traversal, node.index)
      radius = profile.depth * @shell_spacing
      angle = angle_for_node(node, profile, center_x, center_y)

      {x, y} =
        if profile.depth == 0 do
          {center_x, center_y}
        else
          {
            center_x + radius * :math.cos(angle),
            center_y + radius * :math.sin(angle)
          }
        end

      Map.merge(node, %{x: x, y: y})
    end)
  end

  defp anchor_node(nodes) do
    Enum.max_by(nodes, fn node ->
      {degree(node), -kind_priority(node), invert_label(sort_label(node))}
    end)
  end

  defp traversal_profile(anchor_index, nodes_by_index, adjacency) do
    queue = :queue.from_list([{anchor_index, nil, 0, 0.0}])
    visited = MapSet.new()
    levels = %{}

    {levels, _visited} =
      walk_layers(queue, visited, levels, nodes_by_index, adjacency)

    fill_unreached_nodes(levels, nodes_by_index)
  end

  defp walk_layers(queue, visited, levels, nodes_by_index, adjacency) do
    case :queue.out(queue) do
      {:empty, _queue} ->
        {levels, visited}

      {{:value, {index, parent_index, depth, angle}}, queue} ->
        if MapSet.member?(visited, index) do
          walk_layers(queue, visited, levels, nodes_by_index, adjacency)
        else
          visited = MapSet.put(visited, index)
          neighbors = ordered_neighbors(index, parent_index, nodes_by_index, adjacency)

          levels =
            Map.put(levels, index, %{
              parent_index: parent_index,
              depth: depth,
              angle: angle,
              sibling_index: 0,
              sibling_count: 1
            })

          {queue, levels} =
            enqueue_neighbors(queue, levels, index, depth, angle, neighbors)

          walk_layers(queue, visited, levels, nodes_by_index, adjacency)
        end
    end
  end

  defp enqueue_neighbors(queue, levels, _index, _depth, _angle, []), do: {queue, levels}

  defp enqueue_neighbors(queue, levels, index, depth, angle, neighbors) do
    count = length(neighbors)

    Enum.with_index(neighbors)
    |> Enum.reduce({queue, levels}, fn {{neighbor_index, _neighbor}, sibling_index},
                                       {queue, levels} ->
      if Map.has_key?(levels, neighbor_index) do
        {queue, levels}
      else
        neighbor_angle = child_angle(angle, sibling_index, count)

        levels =
          Map.put(levels, neighbor_index, %{
            parent_index: index,
            depth: depth + 1,
            angle: neighbor_angle,
            sibling_index: sibling_index,
            sibling_count: count
          })

        {:queue.in({neighbor_index, index, depth + 1, neighbor_angle}, queue), levels}
      end
    end)
  end

  defp fill_unreached_nodes(levels, nodes_by_index) do
    missing =
      nodes_by_index
      |> Map.keys()
      |> Enum.reject(&Map.has_key?(levels, &1))
      |> Enum.map(fn index -> {index, Map.fetch!(nodes_by_index, index)} end)
      |> Enum.sort_by(fn {_index, node} ->
        {-degree(node), kind_priority(node), sort_label(node)}
      end)

    count = length(missing)

    Enum.with_index(missing)
    |> Enum.reduce(levels, fn {{index, _node}, missing_index}, acc ->
      angle =
        if count <= 1 do
          0.0
        else
          2.0 * :math.pi() * missing_index / count
        end

      Map.put(acc, index, %{
        parent_index: nil,
        depth: 1,
        angle: angle,
        sibling_index: missing_index,
        sibling_count: count
      })
    end)
  end

  defp ordered_neighbors(index, parent_index, nodes_by_index, adjacency) do
    adjacency
    |> Map.get(index, [])
    |> Enum.reject(&(&1 == parent_index))
    |> Enum.uniq()
    |> Enum.map(fn neighbor_index ->
      {neighbor_index, Map.fetch!(nodes_by_index, neighbor_index)}
    end)
    |> Enum.sort_by(fn {_neighbor_index, node} ->
      {-degree(node), kind_priority(node), sort_label(node)}
    end)
  end

  defp angle_for_node(_node, %{angle: angle, depth: 0}, _center_x, _center_y), do: angle

  defp angle_for_node(node, profile, _center_x, _center_y) do
    angle =
      profile.angle +
        layer_bias(profile.depth) +
        kind_angle_bias(node.kind) +
        sibling_bias(profile.sibling_index, profile.sibling_count)

    normalize_angle(angle)
  end

  defp child_angle(parent_angle, sibling_index, sibling_count) do
    span = child_span(sibling_count)
    start = parent_angle - span / 2.0
    start + (sibling_index + 0.5) / sibling_count * span
  end

  defp child_span(sibling_count) when sibling_count <= 1, do: :math.pi() / 2.8
  defp child_span(sibling_count) when sibling_count <= 3, do: :math.pi() * 0.95
  defp child_span(_sibling_count), do: :math.pi() * 1.35

  defp sibling_bias(_sibling_index, sibling_count) when sibling_count <= 1, do: 0.0

  defp sibling_bias(sibling_index, sibling_count) do
    midpoint = (sibling_count - 1) / 2.0
    (sibling_index - midpoint) * 0.06
  end

  defp layer_bias(depth), do: depth * 0.08

  defp kind_angle_bias("actor"), do: -0.08
  defp kind_angle_bias("channel"), do: 0.0
  defp kind_angle_bias("conversation"), do: 0.04
  defp kind_angle_bias("message"), do: 0.08
  defp kind_angle_bias(_kind), do: 0.0

  defp normalize_angle(angle) do
    two_pi = 2.0 * :math.pi()
    wrapped = :math.fmod(angle, two_pi)
    if wrapped < 0.0, do: wrapped + two_pi, else: wrapped
  end

  defp component_center(component_index, columns) do
    row = div(component_index, columns)
    col = rem(component_index, columns)

    {
      col * @component_spacing,
      row * @component_spacing
    }
  end

  defp adjacency(edges, node_count) do
    base =
      if node_count == 0 do
        %{}
      else
        Map.new(0..(node_count - 1), fn index -> {index, []} end)
      end

    Enum.reduce(edges, base, fn edge, acc ->
      acc
      |> Map.update!(edge.source, &[edge.target | &1])
      |> Map.update!(edge.target, &[edge.source | &1])
    end)
  end

  defp component_id(node) do
    node
    |> graph_profile()
    |> Map.get(:component_id, 0)
  end

  defp degree(node) do
    node
    |> graph_profile()
    |> Map.get(:degree, 0)
  end

  defp graph_profile(node) do
    Map.get(node.details || %{}, :graph_profile, %{})
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
