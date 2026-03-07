defmodule Mix.Tasks.Threadr.Nats.Setup do
  @shortdoc "Creates the Threadr JetStream stream and consumer"
  @moduledoc """
  Provisions the JetStream topology used by the Threadr rewrite.
  """

  use Mix.Task

  alias Threadr.Messaging.{Setup, Topology}

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    Setup.ensure_topology()

    Mix.shell().info(
      "JetStream ready: stream=#{Topology.stream_name()} consumer=#{Topology.consumer_name()}"
    )
  end

end
