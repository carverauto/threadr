defmodule Threadr.ControlPlane.BotReconciler do
  @moduledoc """
  Reconciliation boundary for translating bot definitions into Kubernetes workloads.
  """

  @callback reconcile(struct(), struct()) :: :ok | {:error, term()}
end
