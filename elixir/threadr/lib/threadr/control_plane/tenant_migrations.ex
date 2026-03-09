defmodule Threadr.ControlPlane.TenantMigrations do
  @moduledoc """
  Utilities for applying tenant-schema migrations to existing tenants.
  """

  alias Threadr.ControlPlane.Service

  @system_opts [context: %{system: true}]

  def migrate_all do
    with {:ok, tenants} <- Threadr.ControlPlane.list_tenants(context: %{system: true}) do
      tenants
      |> Enum.sort_by(& &1.schema_name)
      |> Enum.map(&migrate_tenant/1)
    end
  end

  def migrate_by_subject_name(subject_name) when is_binary(subject_name) do
    with {:ok, tenant} <-
           fetch_tenant(
             fn ->
               Threadr.ControlPlane.get_tenant_by_subject_name(
                 subject_name,
                 context: %{system: true}
               )
             end,
             subject_name
           ) do
      {:ok, migrate_tenant(tenant)}
    end
  end

  def migrate_by_schema_name(schema_name) when is_binary(schema_name) do
    with {:ok, tenant} <-
           fetch_tenant(
             fn ->
               Threadr.ControlPlane.get_tenant_by_schema_name(
                 schema_name,
                 context: %{system: true}
               )
             end,
             schema_name
           ) do
      {:ok, migrate_tenant(tenant)}
    end
  end

  def migrate_tenant(%{schema_name: schema_name} = tenant) when is_binary(schema_name) do
    migrations_path = Threadr.Repo.tenant_migrations_path()
    version = Service.latest_tenant_migration_version()

    with {:ok, tenant} <- Service.mark_tenant_migration_running(tenant, @system_opts),
         {:ok, _, _versions} <-
           Ecto.Migrator.with_repo(Threadr.Repo, fn repo ->
             {:ok, repo,
              Ecto.Migrator.run(repo, migrations_path, :up, all: true, prefix: schema_name)}
           end),
         {:ok, tenant} <- Service.mark_tenant_migration_succeeded(tenant, version, @system_opts) do
      tenant_result(tenant)
    else
      {:error, reason} = error ->
        _ = Service.mark_tenant_migration_failed(tenant, reason, @system_opts)
        error
    end
  rescue
    error ->
      _ = Service.mark_tenant_migration_failed(tenant, error, @system_opts)
      reraise error, __STACKTRACE__
  end

  defp tenant_result(tenant) do
    %{
      tenant_id: tenant.id,
      tenant_name: tenant.name,
      subject_name: tenant.subject_name,
      schema_name: tenant.schema_name,
      tenant_migration_status: tenant.tenant_migration_status,
      tenant_migration_version: tenant.tenant_migration_version,
      tenant_migrated_at: tenant.tenant_migrated_at
    }
  end

  defp fetch_tenant(fetcher, lookup_value) when is_function(fetcher, 0) do
    case fetcher.() do
      {:ok, tenant} when not is_nil(tenant) ->
        {:ok, tenant}

      {:ok, nil} ->
        {:error, {:tenant_not_found, lookup_value}}

      {:error, error} ->
        normalize_fetch_error(error, lookup_value)
    end
  end

  defp normalize_fetch_error(%Ash.Error.Invalid{errors: errors}, lookup_value) do
    if Enum.any?(errors, &match?(%Ash.Error.Query.NotFound{}, &1)) do
      {:error, {:tenant_not_found, lookup_value}}
    else
      {:error, %Ash.Error.Invalid{errors: errors}}
    end
  end

  defp normalize_fetch_error(error, _lookup_value), do: {:error, error}
end
