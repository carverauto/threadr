defmodule Threadr.TenantData.GraphSemanticsTest do
  use ExUnit.Case, async: true

  alias Threadr.TenantData.GraphSemantics

  test "enriches nodes with community and hop metrics" do
    nodes = [
      node(0, "anchor", "actor"),
      node(1, "branch-a", "channel"),
      node(2, "branch-b", "actor"),
      node(3, "leaf-a", "message"),
      node(4, "leaf-b", "message")
    ]

    edges = [
      edge(0, 1, "MENTIONED", "relationship"),
      edge(0, 2, "MENTIONED", "relationship"),
      edge(1, 3, "authored", "authored"),
      edge(2, 4, "in_channel", "in_channel")
    ]

    enriched = GraphSemantics.enrich_nodes(nodes, edges)

    anchor = Enum.at(enriched, 0)
    branch_a = Enum.at(enriched, 1)
    leaf_a = Enum.at(enriched, 3)

    assert anchor.details.graph_profile.component_id == 1
    assert anchor.details.graph_profile.component_size == 5
    assert anchor.details.graph_profile.community_id == "1:core"
    assert anchor.details.graph_profile.community_role == "anchor"
    assert anchor.details.graph_profile.distance_to_anchor == 0
    assert anchor.details.graph_profile.one_hop_count == 2
    assert anchor.details.graph_profile.two_hop_count == 2
    assert anchor.details.graph_profile.three_hop_count == 0

    assert branch_a.details.graph_profile.community_id in ["1:1", "1:2"]
    assert branch_a.details.graph_profile.distance_to_anchor == 1

    assert leaf_a.details.graph_profile.community_id == branch_a.details.graph_profile.community_id
    assert leaf_a.details.graph_profile.distance_to_anchor == 2
    assert leaf_a.details.graph_profile.community_role in ["branch", "peripheral"]
  end

  defp node(index, id, kind) do
    %{
      index: index,
      id: id,
      label: id,
      kind: kind,
      state: 0,
      size: 12.0,
      x: 0.0,
      y: 0.0,
      details: %{}
    }
  end

  defp edge(source, target, label, kind) do
    %{source: source, target: target, label: label, kind: kind, weight: 1}
  end
end
