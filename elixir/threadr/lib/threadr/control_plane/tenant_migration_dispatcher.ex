defmodule Threadr.ControlPlane.TenantMigrationDispatcher do
  @moduledoc """
  Supervised worker that migrates tenant schemas that are pending, failed, or behind.
  """

  use GenServer

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Service
  alias Threadr.ControlPlane.TenantMigrations

  @name __MODULE__

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  def process_pending_once(migrator_override \\ nil) do
    config =
      dispatcher_config()
      |> maybe_put_migrator_override(migrator_override)

    dispatch_pending(config)
  end

  def trigger do
    if dispatcher_config().enabled and Process.whereis(@name) do
      GenServer.cast(@name, :trigger)
    else
      :ok
    end
  end

  @impl true
  def init(_opts) do
    state = dispatcher_config()
    maybe_schedule(state)
    {:ok, state}
  end

  @impl true
  def handle_cast(:trigger, state) do
    if state.enabled do
      dispatch_pending(state)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:process_pending, state) do
    dispatch_pending(state)
    maybe_schedule(state)
    {:noreply, state}
  end

  defp maybe_schedule(%{enabled: true, poll_interval_ms: poll_interval_ms}) do
    Process.send_after(self(), :process_pending, poll_interval_ms)
  end

  defp maybe_schedule(_state), do: :ok

  defp maybe_put_migrator_override(config, nil), do: config

  defp maybe_put_migrator_override(config, migrator_override),
    do: %{config | migrator: migrator_override}

  defp dispatcher_config do
    config = Application.get_env(:threadr, __MODULE__, [])

    %{
      enabled: Keyword.get(config, :enabled, true),
      poll_interval_ms: Keyword.get(config, :poll_interval_ms, 30_000),
      batch_size: Keyword.get(config, :batch_size, 10),
      migrator: Keyword.get(config, :migrator, TenantMigrations)
    }
  end

  defp dispatch_pending(config) do
    system_opts = [context: %{system: true}]
    latest_version = Service.latest_tenant_migration_version()

    with {:ok, tenants} <-
           ControlPlane.list_tenants(
             Keyword.merge(system_opts,
               query: [sort: [inserted_at: :asc], limit: config.batch_size * 5]
             )
           ) do
      tenants
      |> Enum.filter(&tenant_requires_migration?(&1, latest_version))
      |> Enum.take(config.batch_size)
      |> Enum.each(&migrate_tenant(&1, config.migrator))

      :ok
    end
  end

  def tenant_requires_migration?(tenant, latest_version) do
    is_binary(tenant.schema_name) and tenant.schema_name != "" and
      tenant.status == "active" and
      (tenant.tenant_migration_status != "succeeded" or
         tenant.tenant_migration_version != latest_version)
  end

  defp migrate_tenant(tenant, migrator) do
    case migrator.migrate_tenant(tenant) do
      {:error, _reason} -> :error
      _result -> :ok
    end
  end
end
