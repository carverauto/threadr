defmodule Threadr.ML.EmbeddingsTest do
  use ExUnit.Case, async: true

  alias Threadr.ML.Embeddings
  alias Threadr.TenantData.Message

  test "publishes a processing.result envelope for a tenant message" do
    message = %Message{
      id: Ecto.UUID.generate(),
      external_id: "discord-message-123",
      body: "hello from threadr"
    }

    assert {:ok, envelope} =
             Embeddings.generate_for_message(
               message,
               "acme-threat-intel",
               provider: Threadr.TestEmbeddingProvider,
               publisher: {Threadr.TestPublisher, self()}
             )

    assert_receive {:published_envelope, published}
    assert published.id == envelope.id
    assert envelope.type == "processing.result"
    assert envelope.subject == "threadr.tenants.acme-threat-intel.processing.result"
    assert envelope.data.pipeline == "embeddings"
    assert envelope.data.status == "completed"
    assert envelope.data.message_id == "discord-message-123"
    assert envelope.data.payload["model"] == "test-embedding-model"
    assert envelope.data.payload["provider"] == "test"
    assert envelope.data.payload["embedding"] == [0.1, 0.2, 0.3]
    assert envelope.data.metrics["text_length"] == 18
  end

  test "embeds query text through the provider boundary" do
    assert {:ok, result} =
             Embeddings.embed_query(
               "who mentioned bob?",
               provider: Threadr.TestEmbeddingProvider,
               model: "test-query-model"
             )

    assert result.embedding == [0.4, 0.5, 0.6]
    assert result.model == "test-query-model"
    assert result.provider == "test"
    assert result.metadata["input_type"] == "query"
    assert result.metadata["text_length"] == 18
  end

  test "returns a provider error when local embeddings are disabled" do
    message = %Message{id: Ecto.UUID.generate(), external_id: "msg-1", body: "hello"}

    assert {:error, :embedding_provider_not_configured} =
             Embeddings.generate_for_message(
               message,
               "acme-threat-intel",
               provider: Threadr.ML.Embeddings.NoopProvider
             )
  end

  test "returns a provider error when query embeddings are disabled" do
    assert {:error, :embedding_provider_not_configured} =
             Embeddings.embed_query(
               "hello",
               provider: Threadr.ML.Embeddings.NoopProvider
             )
  end

  test "hash provider returns deterministic normalized vectors for document and query text" do
    assert {:ok, document} =
             Embeddings.embed_query(
               "malicious oauth app calendar sync helper",
               provider: Threadr.ML.Embeddings.HashProvider
             )

    assert {:ok, query} =
             Embeddings.embed_query(
               "what was the malicious oauth app called?",
               provider: Threadr.ML.Embeddings.HashProvider
             )

    assert document.model == "term-hash-384-v1"
    assert query.model == "term-hash-384-v1"
    assert document.provider == "hash"
    assert query.provider == "hash"
    assert length(document.embedding) == 384
    assert length(query.embedding) == 384

    document_magnitude =
      document.embedding
      |> Enum.reduce(0.0, fn value, acc -> acc + value * value end)
      |> :math.sqrt()

    query_magnitude =
      query.embedding
      |> Enum.reduce(0.0, fn value, acc -> acc + value * value end)
      |> :math.sqrt()

    assert_in_delta document_magnitude, 1.0, 1.0e-6
    assert_in_delta query_magnitude, 1.0, 1.0e-6
  end
end
