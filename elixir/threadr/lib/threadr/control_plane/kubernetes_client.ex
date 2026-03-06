defmodule Threadr.ControlPlane.KubernetesClient do
  @moduledoc """
  Boundary for applying, reading, and deleting Kubernetes bot workloads.
  """

  @callback apply_deployment(binary(), binary(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback get_deployment(binary(), binary()) ::
              {:ok, map() | nil} | {:error, term()}
  @callback delete_deployment(binary(), binary()) ::
              {:ok, map()} | {:error, term()}
end
