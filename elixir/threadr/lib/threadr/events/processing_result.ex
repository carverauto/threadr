defmodule Threadr.Events.ProcessingResult do
  @moduledoc """
  Processing output emitted by Broadway consumers or downstream agents.
  """

  @derive Jason.Encoder
  @enforce_keys [:pipeline, :status, :completed_at]
  defstruct [:pipeline, :status, :completed_at, :message_id, payload: %{}, metrics: %{}]

  def from_map(attrs) do
    %__MODULE__{
      pipeline: fetch!(attrs, :pipeline),
      status: fetch!(attrs, :status),
      completed_at: fetch_datetime!(attrs, :completed_at),
      message_id: fetch(attrs, :message_id),
      payload: fetch(attrs, :payload, %{}),
      metrics: fetch(attrs, :metrics, %{})
    }
  end

  defp fetch!(attrs, key) do
    fetch(attrs, key) || raise ArgumentError, "missing required key #{inspect(key)}"
  end

  defp fetch_datetime!(attrs, key) do
    case fetch!(attrs, key) do
      %DateTime{} = datetime ->
        datetime

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> datetime
          _ -> raise ArgumentError, "invalid datetime for #{inspect(key)}"
        end
    end
  end

  defp fetch(attrs, key, default \\ nil) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key)) || default
  end
end
