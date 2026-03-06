defmodule Threadr.TenantData.GraphLayoutTest do
  use ExUnit.Case, async: true

  alias Threadr.TenantData.GraphLayout

  test "lays out components deterministically with hubs near the component center" do
    nodes = [
      node(0, "actor-a", "actor", %{component_id: 1, degree: 5}),
      node(1, "channel-a", "channel", %{component_id: 1, degree: 2}),
      node(2, "message-a", "message", %{component_id: 1, degree: 1}),
      node(3, "actor-b", "actor", %{component_id: 2, degree: 3}),
      node(4, "message-b", "message", %{component_id: 2, degree: 1})
    ]

    layout = GraphLayout.layout(nodes, [])

    actor_a = Enum.find(layout, &(&1.id == "actor-a"))
    channel_a = Enum.find(layout, &(&1.id == "channel-a"))
    message_a = Enum.find(layout, &(&1.id == "message-a"))
    actor_b = Enum.find(layout, &(&1.id == "actor-b"))

    assert actor_a.x == 0.0
    assert actor_a.y == 0.0
    assert abs(channel_a.x) > abs(actor_a.x)
    assert abs(message_a.x) > abs(channel_a.x) or abs(message_a.y) > abs(channel_a.y)
    assert actor_b.x >= 560.0 or actor_b.y >= 560.0
  end

  test "uses traversal depth so grandchildren sit farther out than direct neighbors" do
    nodes = [
      node(0, "actor-a", "actor", %{component_id: 1, degree: 3}),
      node(1, "channel-a", "channel", %{component_id: 1, degree: 2}),
      node(2, "actor-b", "actor", %{component_id: 1, degree: 1}),
      node(3, "message-a", "message", %{component_id: 1, degree: 1})
    ]

    edges = [
      %{source: 0, target: 1, label: "MENTIONED", kind: "relationship", weight: 1},
      %{source: 0, target: 2, label: "MENTIONED", kind: "relationship", weight: 1},
      %{source: 1, target: 3, label: "authored", kind: "authored", weight: 1}
    ]

    layout = GraphLayout.layout(nodes, edges)

    anchor = Enum.find(layout, &(&1.id == "actor-a"))
    direct_neighbor = Enum.find(layout, &(&1.id == "channel-a"))
    second_neighbor = Enum.find(layout, &(&1.id == "actor-b"))
    grandchild = Enum.find(layout, &(&1.id == "message-a"))

    assert anchor.x == 0.0
    assert anchor.y == 0.0

    assert distance(anchor, direct_neighbor) < distance(anchor, grandchild)
    assert distance(anchor, second_neighbor) < distance(anchor, grandchild)
  end

  defp node(index, id, kind, profile) do
    %{
      index: index,
      id: id,
      label: id,
      kind: kind,
      state: 0,
      size: 12.0,
      x: 0.0,
      y: 0.0,
      details: %{graph_profile: profile}
    }
  end

  defp distance(left, right) do
    dx = left.x - right.x
    dy = left.y - right.y
    :math.sqrt((dx * dx) + (dy * dy))
  end
end
