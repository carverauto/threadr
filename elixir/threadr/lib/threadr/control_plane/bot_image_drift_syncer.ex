defmodule Threadr.ControlPlane.BotImageDriftSyncer do
  @moduledoc """
  Requeues bots when the configured desired workload image drifts from the
  current controller contract.

  This lets Argo-driven control-plane config updates roll existing IRC and
  Discord bot deployments without manual bot edits.
  """

  use GenServer

  alias Threadr.ControlPlane.Service

  @name __MODULE__

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  def trigger do
    if Process.whereis(@name) do
      GenServer.cast(@name, :trigger)
    else
      :ok
    end
  end

  @impl true
  def init(_opts) do
    state = syncer_config()
    maybe_schedule_immediate(state)
    {:ok, state}
  end

  @impl true
  def handle_cast(:trigger, state) do
    sync(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:sync, state) do
    sync(state)
    maybe_schedule(state)
    {:noreply, state}
  end

  defp sync(%{enabled: true}) do
    case Service.reconcile_bots_with_image_drift() do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp sync(_state), do: :ok

  defp maybe_schedule_immediate(%{enabled: true}) do
    Process.send_after(self(), :sync, 1_000)
  end

  defp maybe_schedule_immediate(_state), do: :ok

  defp maybe_schedule(%{enabled: true, poll_interval_ms: poll_interval_ms}) do
    Process.send_after(self(), :sync, poll_interval_ms)
  end

  defp maybe_schedule(_state), do: :ok

  defp syncer_config do
    config = Application.get_env(:threadr, __MODULE__, [])

    %{
      enabled: Keyword.get(config, :enabled, false),
      poll_interval_ms: Keyword.get(config, :poll_interval_ms, 60_000)
    }
  end
end
