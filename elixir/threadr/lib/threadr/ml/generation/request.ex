defmodule Threadr.ML.Generation.Request do
  @moduledoc """
  Provider-agnostic generation request.
  """

  @enforce_keys [:prompt]
  defstruct [:prompt, :system_prompt, context: %{}, mode: :qa]

  @type t :: %__MODULE__{
          prompt: String.t(),
          system_prompt: String.t() | nil,
          context: map(),
          mode: atom()
        }

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Enum.into(attrs, %{})

    %__MODULE__{
      prompt: fetch_required!(attrs, :prompt),
      system_prompt: fetch(attrs, :system_prompt),
      context: fetch(attrs, :context, %{}),
      mode: fetch(attrs, :mode, :qa)
    }
  end

  defp fetch_required!(attrs, key) do
    fetch(attrs, key) || raise ArgumentError, "missing required key #{inspect(key)}"
  end

  defp fetch(attrs, key, default \\ nil) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key)) || default
  end
end
