defmodule Threadr.Repo.Migrations.AddBotControllerContracts do
  use Ecto.Migration

  def change do
    alter table(:bots) do
      add :desired_generation, :bigint, null: false, default: 0
      add :observed_generation, :bigint
    end

    create table(:bot_controller_contracts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :bot_id, references(:bots, type: :binary_id, on_delete: :delete_all), null: false
      add :generation, :bigint, null: false
      add :operation, :string, null: false
      add :deployment_name, :string, null: false
      add :namespace, :string, null: false
      add :contract, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:bot_controller_contracts, [:bot_id])
    create index(:bot_controller_contracts, [:tenant_id])
    create index(:bot_controller_contracts, [:updated_at])
  end
end
