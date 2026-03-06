defmodule Threadr.ML.Embeddings.NoopProvider do
  @moduledoc """
  Disabled embedding provider used until a local model backend is configured.
  """

  @behaviour Threadr.ML.Embeddings.Provider

  @impl true
  def embed_document(_text, _opts) do
    {:error, :embedding_provider_not_configured}
  end
end
