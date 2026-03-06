defmodule Threadr.ML.Embeddings.Provider do
  @moduledoc """
  Behaviour for local embedding providers.
  """

  @callback embed_document(String.t(), keyword()) ::
              {:ok,
               %{embedding: [number()], model: String.t(), provider: String.t(), metadata: map()}}
              | {:error, term()}
end
