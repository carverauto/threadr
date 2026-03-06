defmodule Threadr.ML.Generation.Result do
  @moduledoc """
  Provider-agnostic generation result.
  """

  @enforce_keys [:content, :model, :provider]
  defstruct [:content, :model, :provider, metadata: %{}]

  @type t :: %__MODULE__{
          content: String.t(),
          model: String.t(),
          provider: String.t(),
          metadata: map()
        }
end
