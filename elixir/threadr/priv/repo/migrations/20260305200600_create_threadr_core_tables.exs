defmodule Threadr.Repo.Migrations.CreateThreadrCoreTables do
  use Ecto.Migration

  def change do
    create table(:tenants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :schema_name, :string, null: false
      add :subject_name, :string, null: false
      add :status, :string, null: false, default: "active"
      add :kubernetes_namespace, :string, null: false, default: "threadr"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tenants, [:slug])
    create unique_index(:tenants, [:schema_name])
    create unique_index(:tenants, [:subject_name])

    create table(:bots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :platform, :string, null: false
      add :desired_state, :string, null: false, default: "running"
      add :status, :string, null: false, default: "pending"
      add :channels, {:array, :text}, null: false, default: []
      add :settings, :map, null: false, default: %{}
      add :deployment_name, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:bots, [:tenant_id])
    create unique_index(:bots, [:tenant_id, :name])
  end
end
