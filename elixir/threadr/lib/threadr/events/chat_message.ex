defmodule Threadr.Events.ChatMessage do
  @moduledoc """
  Canonical payload for normalized chat messages.
  """

  @derive Jason.Encoder
  @enforce_keys [:platform, :channel, :actor, :body, :observed_at]
  defstruct [:platform, :channel, :actor, :body, :observed_at, mentions: [], raw: %{}]

  def from_map(attrs) do
    %__MODULE__{
      platform: fetch!(attrs, :platform),
      channel: fetch!(attrs, :channel),
      actor: fetch!(attrs, :actor),
      body: fetch!(attrs, :body),
      observed_at: fetch_datetime!(attrs, :observed_at),
      mentions: fetch(attrs, :mentions, []),
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
