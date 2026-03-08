defmodule Threadr.TenantData.GraphLayout do
  @moduledoc """
  Deterministic backend-owned layout for the investigation graph.

  This layout is hierarchy-first:
  - channels are the top-level anchors
  - conversations sit under a channel
  - actors and messages fan out around a conversation

  The goal is readability for investigation drill-in, not a generic force graph.
  """

  @channel_spacing_x 560.0
  @channel_spacing_y 340.0
  @conversation_spacing_y 170.0
  @actor_offset_x -210.0
  @message_offset_x 210.0
  @participant_spacing_y 72.0
  @message_spacing_y 58.0

  def layout(nodes, _edges) when nodes == [], do: []

  def layout(nodes, edges) do
    nodes_by_index = Map.new(nodes, &{&1.index, &1})

    if Enum.any?(nodes, &(&1.kind == "conversation")) do
      layout_hierarchy(nodes, edges, nodes_by_index)
    else
      layout_component_grid(nodes)
    end
  end

  defp layout_hierarchy(nodes, edges, nodes_by_index) do
    channel_nodes =
      nodes
      |> Enum.filter(&(&1.kind == "channel"))
      |> Enum.sort_by(&sort_label/1)

    conversation_indexes_by_channel = conversation_indexes_by_channel(edges, nodes_by_index)
    actor_indexes_by_conversation = actor_indexes_by_conversation(edges, nodes_by_index)
    message_indexes_by_conversation = message_indexes_by_conversation(edges, nodes_by_index)

    channel_positions =
      channel_nodes
      |> Enum.with_index()
      |> Map.new(fn {channel, idx} ->
        col = rem(idx, max(1, ceil(:math.sqrt(length(channel_nodes)))))
        row = div(idx, max(1, ceil(:math.sqrt(length(channel_nodes)))))

        {channel.index, {col * @channel_spacing_x, row * @channel_spacing_y}}
      end)

    positions =
      Enum.reduce(channel_nodes, %{}, fn channel, acc ->
        {channel_x, channel_y} = Map.fetch!(channel_positions, channel.index)
        acc = Map.put(acc, channel.index, {channel_x, channel_y})

        conversation_indexes =
          conversation_indexes_by_channel
          |> Map.get(channel.index, [])
          |> Enum.sort_by(&(nodes_by_index |> Map.fetch!(&1) |> conversation_sort_key()))

        conversation_start_y =
          channel_y - (max(length(conversation_indexes), 1) - 1) * @conversation_spacing_y / 2.0

        Enum.with_index(conversation_indexes)
        |> Enum.reduce(acc, fn {conversation_index, conversation_idx}, nested_acc ->
          conversation_x = channel_x
          conversation_y = conversation_start_y + conversation_idx * @conversation_spacing_y
          nested_acc = Map.put(nested_acc, conversation_index, {conversation_x, conversation_y})

          actor_indexes =
            actor_indexes_by_conversation
            |> Map.get(conversation_index, [])
            |> Enum.sort_by(&(nodes_by_index |> Map.fetch!(&1) |> sort_label()))

          message_indexes =
            message_indexes_by_conversation
            |> Map.get(conversation_index, [])
            |> Enum.sort_by(&(nodes_by_index |> Map.fetch!(&1) |> message_sort_key()))

          nested_acc
          |> place_vertical_list(
            actor_indexes,
            conversation_x + @actor_offset_x,
            conversation_y,
            @participant_spacing_y
          )
          |> place_vertical_list(
            message_indexes,
            conversation_x + @message_offset_x,
            conversation_y,
            @message_spacing_y
          )
        end)
      end)

    nodes
    |> Enum.map(fn node ->
      {x, y} = Map.get(positions, node.index, fallback_position(node))
      %{node | x: x, y: y}
    end)
    |> Enum.sort_by(& &1.index)
  end

  defp place_vertical_list(acc, [], _x, _center_y, _spacing), do: acc

  defp place_vertical_list(acc, indexes, x, center_y, spacing) do
    start_y = center_y - (length(indexes) - 1) * spacing / 2.0

    Enum.with_index(indexes)
    |> Enum.reduce(acc, fn {index, idx}, nested_acc ->
      Map.put(nested_acc, index, {x, start_y + idx * spacing})
    end)
  end

  defp conversation_indexes_by_channel(edges, nodes_by_index) do
    Enum.reduce(edges, %{}, fn edge, acc ->
      if edge.kind != "conversation" do
        acc
      else
        source = Map.fetch!(nodes_by_index, edge.source)
        target = Map.fetch!(nodes_by_index, edge.target)

        cond do
          source.kind == "channel" and target.kind == "conversation" ->
            Map.update(acc, source.index, [target.index], &[target.index | &1])

          target.kind == "channel" and source.kind == "conversation" ->
            Map.update(acc, target.index, [source.index], &[source.index | &1])

          true ->
            acc
        end
      end
    end)
    |> Enum.into(%{}, fn {key, values} -> {key, Enum.uniq(values)} end)
  end

  defp actor_indexes_by_conversation(edges, nodes_by_index) do
    Enum.reduce(edges, %{}, fn edge, acc ->
      if edge.kind != "conversation" do
        acc
      else
        source = Map.fetch!(nodes_by_index, edge.source)
        target = Map.fetch!(nodes_by_index, edge.target)

        cond do
          source.kind == "actor" and target.kind == "conversation" ->
            Map.update(acc, target.index, [source.index], &[source.index | &1])

          target.kind == "actor" and source.kind == "conversation" ->
            Map.update(acc, source.index, [target.index], &[target.index | &1])

          true ->
            acc
        end
      end
    end)
    |> Enum.into(%{}, fn {key, values} -> {key, Enum.uniq(values)} end)
  end

  defp message_indexes_by_conversation(edges, nodes_by_index) do
    Enum.reduce(edges, %{}, fn edge, acc ->
      if edge.kind != "conversation" do
        acc
      else
        source = Map.fetch!(nodes_by_index, edge.source)
        target = Map.fetch!(nodes_by_index, edge.target)

        cond do
          source.kind == "conversation" and target.kind == "message" ->
            Map.update(acc, source.index, [target.index], &[target.index | &1])

          target.kind == "conversation" and source.kind == "message" ->
            Map.update(acc, target.index, [source.index], &[source.index | &1])

          true ->
            acc
        end
      end
    end)
    |> Enum.into(%{}, fn {key, values} -> {key, Enum.uniq(values)} end)
  end

  defp conversation_sort_key(node) do
    details = node.details || %{}
    started_at = Map.get(details, :started_at) || Map.get(details, "started_at")
    {sortable_time(started_at), sort_label(node)}
  end

  defp message_sort_key(node) do
    details = node.details || %{}
    observed_at = Map.get(details, :observed_at) || Map.get(details, "observed_at")
    {sortable_time(observed_at), sort_label(node)}
  end

  defp sortable_time(%DateTime{} = value), do: DateTime.to_unix(value, :microsecond)

  defp sortable_time(%NaiveDateTime{} = value),
    do: NaiveDateTime.diff(value, ~N[1970-01-01 00:00:00], :microsecond)

  defp sortable_time(_), do: 0

  defp fallback_position(node) do
    case node.kind do
      "channel" -> {0.0, 0.0}
      "conversation" -> {0.0, 170.0}
      "actor" -> {@actor_offset_x, 170.0}
      "message" -> {@message_offset_x, 170.0}
      _ -> {0.0, 0.0}
    end
  end

  defp layout_component_grid(nodes) do
    nodes
    |> Enum.with_index()
    |> Enum.map(fn {node, idx} ->
      col = rem(idx, 4)
      row = div(idx, 4)
      %{node | x: col * 220.0, y: row * 180.0}
    end)
    |> Enum.sort_by(& &1.index)
  end

  defp sort_label(node), do: String.downcase(to_string(node.label || node.id || "node"))
end
