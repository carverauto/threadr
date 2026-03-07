defmodule Threadr.ML.Extraction.Provider do
  @moduledoc """
  Behaviour for structured extraction providers.
  """

  alias Threadr.ML.Extraction.{Request, Result}

  @callback extract(Request.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
end
