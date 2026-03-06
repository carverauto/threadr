defmodule Threadr.Repo.TenantMigrations.CreateTenantCommandExecutions do
  use Ecto.Migration

  def up do
    create table(:command_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :external_id, :string, null: false
      add :platform, :string, null: false
      add :command, :string, null: false
      add :target, :string
      add :args, :map, null: false, default: %{}
      add :status, :string, null: false, default: "received"
      add :worker_id, :string
      add :claimed_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :last_error, :text
      add :metadata, :map, null: false, default: %{}
      add :issued_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:command_executions, [:external_id])
    create index(:command_executions, [:platform, :command, :issued_at])
    create index(:command_executions, [:status, :issued_at])
  end

  def down do
    drop table(:command_executions)
  end
end
