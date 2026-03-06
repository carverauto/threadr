defmodule Threadr.Events.IngestCommand do
  @moduledoc """
  Command payload emitted to or from ingestion agents.
  """

  @derive Jason.Encoder
  @enforce_keys [:platform, :command, :issued_at]
  defstruct [:platform, :command, :issued_at, args: %{}, target: nil]

  def from_map(attrs) do
    %__MODULE__{
      platform: fetch!(attrs, :platform),
      command: fetch!(attrs, :command),
      issued_at: fetch_datetime!(attrs, :issued_at),
      args: fetch(attrs, :args, %{}),
      target: fetch(attrs, :target)
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
