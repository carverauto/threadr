defmodule Threadr.ML.Embeddings.InlinePublisher do
  @moduledoc """
  Persists generated embedding results directly instead of publishing them to JetStream.

  Useful for local seeding and offline backfills where we want the embedding rows
  to exist immediately in the tenant schema.
  """

  alias Threadr.TenantData.Processing

  def publish(envelope), do: publish(envelope, nil)

  def publish(envelope, _arg) do
    case Processing.persist_envelope(envelope) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
