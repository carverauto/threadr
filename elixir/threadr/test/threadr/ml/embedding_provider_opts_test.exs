defmodule Threadr.ML.EmbeddingProviderOptsTest do
  use ExUnit.Case, async: true

  alias Threadr.ML.EmbeddingProviderOpts

  test "maps prefixed embedding runtime opts to provider opts" do
    opts =
      EmbeddingProviderOpts.from_prefixed(
        [
          embedding_provider: Threadr.TestEmbeddingOptsProvider,
          embedding_model: "test-embedding-model",
          embedding_endpoint: "https://embeddings.example.test",
          embedding_api_key: "embedding-secret",
          embedding_provider_name: "custom-embedder",
          document_prefix: "doc:",
          query_prefix: "query:"
        ],
        model: "override-model"
      )

    assert Keyword.get(opts, :provider) == Threadr.TestEmbeddingOptsProvider
    assert Keyword.get(opts, :model) == "override-model"
    assert Keyword.get(opts, :endpoint) == "https://embeddings.example.test"
    assert Keyword.get(opts, :api_key) == "embedding-secret"
    assert Keyword.get(opts, :provider_name) == "custom-embedder"
    assert Keyword.get(opts, :document_prefix) == "doc:"
    assert Keyword.get(opts, :query_prefix) == "query:"
  end

  test "passes direct embedding provider opts through unchanged" do
    opts =
      EmbeddingProviderOpts.from_direct(
        provider: Threadr.TestEmbeddingOptsProvider,
        model: "test-embedding-model",
        endpoint: "https://embeddings.example.test",
        api_key: "embedding-secret",
        provider_name: "custom-embedder",
        document_prefix: "doc:",
        query_prefix: "query:"
      )

    assert opts == [
             model: "test-embedding-model",
             endpoint: "https://embeddings.example.test",
             api_key: "embedding-secret",
             provider_name: "custom-embedder",
             document_prefix: "doc:",
             query_prefix: "query:"
           ]
  end
end
