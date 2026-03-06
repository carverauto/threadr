defmodule Threadr.Repo.Migrations.CreateBotReconcileOperations do
  use Ecto.Migration

  def change do
    create table(:bot_reconcile_operations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      add :bot_id, references(:bots, type: :binary_id, on_delete: :nilify_all)

      add :operation, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :payload, :map, null: false, default: %{}
      add :attempt_count, :integer, null: false, default: 0
      add :last_error, :text
      add :dispatched_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:bot_reconcile_operations, [:tenant_id])
    create index(:bot_reconcile_operations, [:bot_id])
    create index(:bot_reconcile_operations, [:status, :inserted_at])
  end
end
