defmodule Threadr.Messaging.Supervisor do
  @moduledoc """
  Supervises the NATS connection and optional Broadway consumers.
  """

  use Supervisor

  alias Threadr.Messaging.Topology

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children =
      if Topology.messaging_enabled?() do
        [{Gnat.ConnectionSupervisor, Topology.connection_supervisor_config()}] ++
          pipeline_children()
      else
        []
      end

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp pipeline_children do
    if Topology.pipeline_enabled?() do
      [Threadr.Messaging.Pipeline]
    else
      []
    end
  end
end
