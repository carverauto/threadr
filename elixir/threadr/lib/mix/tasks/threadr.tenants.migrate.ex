defmodule Mix.Tasks.Threadr.Tenants.Migrate do
  @shortdoc "Applies tenant-schema migrations to existing tenants"
  @moduledoc """
  Applies tenant-schema migrations to one tenant or all tenants.

  Examples:

      mix threadr.tenants.migrate --all
      mix threadr.tenants.migrate --tenant-subject acme-threat-intel
      mix threadr.tenants.migrate --tenant-schema tenant_acme_threat_intel
  """

  use Mix.Task

  alias Threadr.ControlPlane.TenantMigrations

  @switches [
    all: :boolean,
    tenant_subject: :string,
    tenant_schema: :string
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _argv, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    Mix.Task.run("app.start")

    case migration_target(opts) do
      {:all} ->
        case TenantMigrations.migrate_all() do
          migrated when is_list(migrated) ->
            print_results(migrated)

          {:error, reason} ->
            Mix.raise("failed to migrate tenants: #{inspect(reason)}")
        end

      {:subject_name, subject_name} ->
        case TenantMigrations.migrate_by_subject_name(subject_name) do
          {:ok, migrated} -> print_results([migrated])
          {:error, reason} -> Mix.raise("failed to migrate tenant: #{inspect(reason)}")
        end

      {:schema_name, schema_name} ->
        case TenantMigrations.migrate_by_schema_name(schema_name) do
          {:ok, migrated} -> print_results([migrated])
          {:error, reason} -> Mix.raise("failed to migrate tenant: #{inspect(reason)}")
        end
    end
  end

  defp migration_target(opts) do
    case {opts[:all], opts[:tenant_subject], opts[:tenant_schema]} do
      {true, nil, nil} ->
        {:all}

      {nil, subject_name, nil} when is_binary(subject_name) ->
        {:subject_name, subject_name}

      {nil, nil, schema_name} when is_binary(schema_name) ->
        {:schema_name, schema_name}

      _ ->
        Mix.raise("specify exactly one of --all, --tenant-subject, or --tenant-schema")
    end
  end

  defp print_results(results) do
    Mix.shell().info("Tenant migrations applied: #{length(results)}")

    Enum.each(results, fn result ->
      Mix.shell().info(
        "- #{result.subject_name} (#{result.schema_name}) [#{result.tenant_id}] status=#{result.tenant_migration_status} version=#{result.tenant_migration_version}"
      )
    end)
  end
end
