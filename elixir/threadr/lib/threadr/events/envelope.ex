defmodule Threadr.Events.Envelope do
  @moduledoc """
  Normalized message envelope published to JetStream.
  """

  @derive Jason.Encoder
  @enforce_keys [:id, :type, :source, :subject, :occurred_at, :data]
  defstruct [
    :id,
    :type,
    :source,
    :subject,
    :occurred_at,
    :correlation_id,
    data: %{},
    metadata: %{}
  ]

  def new(data, type, subject, attrs \\ %{}) do
    %__MODULE__{
      id: Map.get(attrs, :id, Ecto.UUID.generate()),
      type: type,
      source: Map.get(attrs, :source, "threadr"),
      subject: subject,
      occurred_at: Map.get(attrs, :occurred_at, DateTime.utc_now() |> DateTime.truncate(:second)),
      correlation_id: Map.get(attrs, :correlation_id),
      data: data,
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  def from_map(attrs) do
    %__MODULE__{
      id: fetch!(attrs, :id),
      type: fetch!(attrs, :type),
      source: fetch(attrs, :source, "threadr"),
      subject: fetch!(attrs, :subject),
      occurred_at: fetch_datetime!(attrs, :occurred_at),
      correlation_id: fetch(attrs, :correlation_id),
      data: fetch!(attrs, :data),
      metadata: fetch(attrs, :metadata, %{})
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
