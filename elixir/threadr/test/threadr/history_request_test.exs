defmodule Threadr.HistoryRequestTest do
  use ExUnit.Case, async: true

  alias Threadr.HistoryRequest

  test "builds baseline and comparison history runtime opts" do
    request =
      HistoryRequest.new(
        query: "alice",
        actor_handle: "alice",
        entity_type: "person",
        since: ~N[2026-03-05 11:30:00],
        until: ~N[2026-03-05 12:30:00],
        compare_since: ~N[2026-03-05 12:30:00],
        compare_until: ~N[2026-03-05 13:30:00],
        limit: 25,
        context: %{trace_id: "123"}
      )

    assert HistoryRequest.to_runtime_opts(request) == [
             query: "alice",
             actor_handle: "alice",
             entity_type: "person",
             limit: 25,
             since: ~N[2026-03-05 11:30:00],
             until: ~N[2026-03-05 12:30:00]
           ]

    assert HistoryRequest.to_comparison_runtime_opts(request) == [
             query: "alice",
             actor_handle: "alice",
             entity_type: "person",
             limit: 25,
             since: ~N[2026-03-05 12:30:00],
             until: ~N[2026-03-05 13:30:00]
           ]

    assert HistoryRequest.ash_opts(request) == [context: %{trace_id: "123"}]
  end
end
