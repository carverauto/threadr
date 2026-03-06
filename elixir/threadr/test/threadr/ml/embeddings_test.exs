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

  test "returns a provider error when local embeddings are disabled" do
    message = %Message{id: Ecto.UUID.generate(), external_id: "msg-1", body: "hello"}

    assert {:error, :embedding_provider_not_configured} =
             Embeddings.generate_for_message(
               message,
               "acme-threat-intel",
               provider: Threadr.ML.Embeddings.NoopProvider
             )
  end
end
