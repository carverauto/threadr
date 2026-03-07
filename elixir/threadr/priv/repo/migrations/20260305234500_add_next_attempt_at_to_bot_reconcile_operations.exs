defmodule Threadr.Repo.Migrations.AddNextAttemptAtToBotReconcileOperations do
  use Ecto.Migration

  def change do
    alter table(:bot_reconcile_operations) do
      add :next_attempt_at, :utc_datetime_usec
    end

    create index(:bot_reconcile_operations, [:status, :next_attempt_at, :inserted_at])
  end
end
