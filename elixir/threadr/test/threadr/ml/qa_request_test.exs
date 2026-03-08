defmodule Threadr.ML.QARequestTest do
  use ExUnit.Case, async: true

  alias Threadr.ML.QARequest

  test "builds and merges runtime opts explicitly" do
    request =
      QARequest.new("what happened?", :bot,
        limit: 3,
        requester_actor_handle: "leku",
        since: ~U[2026-03-01 00:00:00Z]
      )
      |> QARequest.merge_runtime_opts(generation_model: "test-chat", limit: 5)

    assert request.question == "what happened?"
    assert request.strategy == :bot
    assert request.limit == 5
    assert request.requester_actor_handle == "leku"
    assert request.generation_model == "test-chat"

    assert QARequest.to_runtime_opts(request) == [
             limit: 5,
             since: ~U[2026-03-01 00:00:00Z],
             generation_model: "test-chat",
             requester_actor_handle: "leku"
           ]
  end
end
