defmodule Threadr.Messaging.Setup do
  @moduledoc """
  Provisions the JetStream stream and durable consumer for Threadr.
  """

  alias Gnat.Jetstream.API.{Consumer, Stream}
  alias Threadr.Messaging.Topology

  def ensure_topology do
    ensure_stream()
    ensure_consumer()
    :ok
  end

  defp ensure_stream do
    case Stream.info(Topology.connection_name(), Topology.stream_name()) do
      {:ok, _stream} ->
        :ok

      {:error, _reason} ->
        case Stream.create(Topology.connection_name(), Topology.stream_spec()) do
          {:ok, _stream} -> :ok
          {:error, reason} -> raise "failed to create JetStream stream: #{inspect(reason)}"
        end
    end
  end

  defp ensure_consumer do
    case Consumer.info(
           Topology.connection_name(),
           Topology.stream_name(),
           Topology.consumer_name()
         ) do
      {:ok, _consumer} ->
        :ok

      {:error, _reason} ->
        case Consumer.create(Topology.connection_name(), Topology.consumer_spec()) do
          {:ok, _consumer} -> :ok
          {:error, reason} -> raise "failed to create JetStream consumer: #{inspect(reason)}"
        end
    end
  end
end
