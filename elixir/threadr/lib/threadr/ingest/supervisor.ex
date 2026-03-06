defmodule Threadr.Ingest.Supervisor do
  @moduledoc """
  Starts a single platform ingestion runtime when the bot pod is configured to
  ingest messages for a specific platform.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Supervisor.init(Threadr.Ingest.child_specs(), strategy: :one_for_one)
  end
end
