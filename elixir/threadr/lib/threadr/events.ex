defmodule Threadr.Events do
  @moduledoc """
  Canonical event encoding and decoding for Threadr's JetStream subjects.
  """

  alias Threadr.Events.{ChatMessage, Envelope, IngestCommand, ProcessingResult}

  @type_map %{
    "chat.message" => ChatMessage,
    "ingest.command" => IngestCommand,
    "processing.result" => ProcessingResult
  }

  def encode!(%Envelope{} = envelope), do: Jason.encode!(envelope)

  def decode_envelope(payload) when is_binary(payload) do
    with {:ok, decoded} <- Jason.decode(payload) do
      from_map(decoded)
    end
  end

  def from_map(attrs) when is_map(attrs) do
    type = fetch(attrs, :type)
    data = fetch(attrs, :data, %{})

    with {:ok, module} <- fetch_module(type),
         {:ok, decoded_data} <- decode_data(module, data) do
      {:ok,
       Envelope.from_map(
         attrs
         |> Map.put("type", type)
         |> Map.put("data", decoded_data)
       )}
    end
  end

  def build_chat_message(attrs, tenant_subject_name \\ "dev") do
    attrs
    |> ChatMessage.from_map()
    |> Envelope.new(
      "chat.message",
      Threadr.Messaging.Topology.subject_for(:chat_messages, tenant_subject_name)
    )
  end

  def build_ingest_command(attrs, tenant_subject_name \\ "dev") do
    attrs
    |> IngestCommand.from_map()
    |> Envelope.new(
      "ingest.command",
      Threadr.Messaging.Topology.subject_for(:ingest_commands, tenant_subject_name)
    )
  end

  def build_processing_result(attrs, tenant_subject_name \\ "dev") do
    attrs
    |> ProcessingResult.from_map()
    |> Envelope.new(
      "processing.result",
      Threadr.Messaging.Topology.subject_for(:processing_results, tenant_subject_name)
    )
  end

  def event_types, do: Map.keys(@type_map)

  defp fetch_module(type) do
    case Map.fetch(@type_map, type) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, {:unsupported_type, type}}
    end
  end

  defp decode_data(module, attrs) do
    {:ok, module.from_map(attrs)}
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  defp fetch(map, key, default \\ nil) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key)) || default
  end
end
