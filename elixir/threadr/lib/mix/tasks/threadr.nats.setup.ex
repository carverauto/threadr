defmodule Mix.Tasks.Threadr.Nats.Setup do
  @shortdoc "Creates the Threadr JetStream stream and consumer"
  @moduledoc """
  Provisions the JetStream topology used by the Threadr rewrite.
  """

  use Mix.Task

  alias Gnat.Jetstream.API.{Consumer, Stream}
  alias Threadr.Messaging.Topology

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    ensure_stream()
    ensure_consumer()

    Mix.shell().info(
      "JetStream ready: stream=#{Topology.stream_name()} consumer=#{Topology.consumer_name()}"
    )
  end

  defp ensure_stream do
    case Stream.info(Topology.connection_name(), Topology.stream_name()) do
      {:ok, _stream} ->
        :ok

      {:error, _reason} ->
        case Stream.create(Topology.connection_name(), Topology.stream_spec()) do
          {:ok, _stream} -> :ok
          {:error, reason} -> Mix.raise("failed to create JetStream stream: #{inspect(reason)}")
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
          {:error, reason} -> Mix.raise("failed to create JetStream consumer: #{inspect(reason)}")
        end
    end
  end
end
