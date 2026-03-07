defmodule Threadr.ControlPlane.BotStatus do
  @moduledoc """
  Enum-backed operational lifecycle states for tenant bot workloads.
  """

  use Ash.Type.Enum,
    values: [:pending, :reconciling, :running, :stopped, :degraded, :deleting, :deleted, :error]
end
