defmodule Threadr.ML.Generation.Provider do
  @moduledoc """
  Behaviour for general-purpose text generation providers.
  """

  alias Threadr.ML.Generation.{Request, Result}

  @callback complete(Request.t(), keyword()) ::
              {:ok, Result.t()}
              | {:error, term()}
end
