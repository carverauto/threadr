defmodule Threadr.Repo.Migrations.AddTenantMigrationTrackingToTenants do
  use Ecto.Migration

  def change do
    alter table(:tenants) do
      add :tenant_migration_status, :string, null: false, default: "pending"
      add :tenant_migration_version, :bigint
      add :tenant_migrated_at, :utc_datetime_usec
      add :tenant_migration_error, :text
    end

    create index(:tenants, [:tenant_migration_status])
  end
end
