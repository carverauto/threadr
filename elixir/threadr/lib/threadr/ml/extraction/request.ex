defmodule Threadr.ML.Extraction.Request do
  @moduledoc """
  Provider-agnostic extraction request.
  """

  @enforce_keys [:tenant_subject_name, :message_id, :body]
  defstruct [:tenant_subject_name, :message_id, :body, :observed_at, context: %{}]

  @type t :: %__MODULE__{
          tenant_subject_name: String.t(),
          message_id: String.t(),
          body: String.t(),
          observed_at: DateTime.t() | NaiveDateTime.t() | nil,
          context: map()
        }

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Enum.into(attrs, %{})

    %__MODULE__{
      tenant_subject_name: fetch_required!(attrs, :tenant_subject_name),
      message_id: fetch_required!(attrs, :message_id),
      body: fetch_required!(attrs, :body),
      observed_at: fetch(attrs, :observed_at),
      context: fetch(attrs, :context, %{})
    }
  end

  defp fetch_required!(attrs, key) do
    fetch(attrs, key) || raise ArgumentError, "missing required key #{inspect(key)}"
  end

  defp fetch(attrs, key, default \\ nil) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key)) || default
  end
end
