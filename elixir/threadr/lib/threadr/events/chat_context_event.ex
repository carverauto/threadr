defmodule Threadr.Events.ChatContextEvent do
  @moduledoc """
  Canonical payload for normalized non-message chat context events.
  """

  @derive Jason.Encoder
  @enforce_keys [:platform, :event_type, :observed_at]
  defstruct [:platform, :event_type, :observed_at, :channel, :actor, metadata: %{}, raw: %{}]

  def from_map(attrs) do
    %__MODULE__{
      platform: fetch!(attrs, :platform),
      event_type: fetch!(attrs, :event_type),
      observed_at: fetch_datetime!(attrs, :observed_at),
      channel: fetch(attrs, :channel),
      actor: fetch(attrs, :actor),
      metadata: fetch(attrs, :metadata, %{}),
      raw: fetch(attrs, :raw, %{})
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
