defmodule Threadr.ML.Embeddings.Provider do
  @moduledoc """
  Behaviour for local embedding providers.
  """

  @type result ::
          {:ok,
           %{embedding: [number()], model: String.t(), provider: String.t(), metadata: map()}}
          | {:error, term()}

  @callback embed_document(String.t(), keyword()) ::
              result()

  @callback embed_query(String.t(), keyword()) ::
              result()
end
