defmodule Threadr.CompareDeltaTest do
  use ExUnit.Case, async: true

  alias Threadr.CompareDelta

  test "builds added and removed entity and fact deltas" do
    result =
      CompareDelta.build(
        [
          %{entity_type: "person", canonical_name: "Alice"},
          %{entity_type: "person", canonical_name: "Bob"}
        ],
        [
          %{entity_type: "person", canonical_name: "Alice"},
          %{entity_type: "person", canonical_name: "Carol"}
        ],
        [
          %{subject: "Bob", predicate: "reported", object: "payroll access was limited"}
        ],
        [
          %{subject: "Carol", predicate: "reported", object: "payroll access was narrowed"}
        ]
      )

    assert result.entity_delta.unchanged == 1

    assert Enum.any?(result.entity_delta.added, fn entry ->
             entry.label == "person: Carol" and entry.count == 1 and entry.entity_name == "Carol"
           end)

    assert Enum.any?(result.entity_delta.removed, fn entry ->
             entry.label == "person: Bob" and entry.count == 1 and entry.entity_name == "Bob"
           end)

    assert %{type: "person", count: 1} in result.entity_delta.added_by_type

    assert Enum.any?(result.entity_delta.highlights.new_people, fn entry ->
             entry.label == "person: Carol" and entry.count == 1
           end)

    assert Enum.any?(result.fact_delta.added, fn entry ->
             entry.label == "Carol reported payroll access was narrowed" and entry.count == 1 and
               entry.subject == "Carol"
           end)

    assert Enum.any?(result.fact_delta.removed, fn entry ->
             entry.label == "Bob reported payroll access was limited" and entry.count == 1 and
               entry.subject == "Bob"
           end)

    assert %{subject: "Carol", count: 1} in result.fact_delta.added_by_subject

    assert Enum.any?(result.fact_delta.highlights.new_claims, fn entry ->
             entry.label == "Carol reported payroll access was narrowed" and entry.count == 1
           end)
  end
end
