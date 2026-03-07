defmodule Threadr.Repo.TenantMigrations.CreateRelationshipObservations do
  use Ecto.Migration

  def up do
    create table(:relationship_observations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :relationship_type, :string, null: false
      add :observed_at, :utc_datetime_usec, null: false
      add :metadata, :map, null: false, default: %{}

      add :from_actor_id, references(:actors, type: :binary_id, on_delete: :delete_all),
        null: false

      add :to_actor_id, references(:actors, type: :binary_id, on_delete: :delete_all), null: false

      add :source_message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:relationship_observations, [:source_message_id])
    create index(:relationship_observations, [:from_actor_id])
    create index(:relationship_observations, [:to_actor_id])

    create unique_index(
             :relationship_observations,
             [:relationship_type, :source_message_id, :from_actor_id, :to_actor_id],
             name: :relationship_observations_unique_observation_index
           )
  end

  def down do
    drop table(:relationship_observations)
  end
end
