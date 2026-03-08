defmodule Threadr.ML.SummaryRequestTest do
  use ExUnit.Case, async: true

  alias Threadr.ML.SummaryRequest

  test "builds and merges runtime opts explicitly" do
    request =
      SummaryRequest.new("incident response",
        limit: 3,
        since: ~U[2026-03-01 00:00:00Z]
      )
      |> SummaryRequest.merge_runtime_opts(
        generation_model: "test-chat",
        embedding_endpoint: "https://embeddings.example.test",
        limit: 5
      )

    assert request.topic == "incident response"
    assert request.limit == 5
    assert request.generation_model == "test-chat"
    assert request.embedding_endpoint == "https://embeddings.example.test"

    assert SummaryRequest.to_runtime_opts(request) == [
             limit: 5,
             embedding_endpoint: "https://embeddings.example.test",
             since: ~U[2026-03-01 00:00:00Z],
             generation_model: "test-chat"
           ]
  end
end
