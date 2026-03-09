defmodule Threadr.Repo.TenantMigrations.MakeAliasObservationsContextAware do
  use Ecto.Migration

  def up do
    alter table(:alias_observations) do
      modify :channel_id, :binary_id, null: true
      modify :source_message_id, :binary_id, null: true

      add :source_context_event_id,
          references(:context_events, type: :binary_id, on_delete: :delete_all)
    end

    drop_if_exists index(:alias_observations, [:source_context_event_id])
    create index(:alias_observations, [:source_context_event_id])

    drop_if_exists unique_index(:alias_observations, [:alias_id, :source_context_event_id],
                     name: :alias_observations_unique_alias_context_index
                   )

    create unique_index(:alias_observations, [:alias_id, :source_context_event_id],
             name: :alias_observations_unique_alias_context_index
           )
  end

  def down do
    drop_if_exists index(:alias_observations, [:source_context_event_id])

    drop_if_exists unique_index(:alias_observations, [:alias_id, :source_context_event_id],
                     name: :alias_observations_unique_alias_context_index
                   )

    alter table(:alias_observations) do
      remove :source_context_event_id
      modify :source_message_id, :binary_id, null: false
      modify :channel_id, :binary_id, null: false
    end
  end
end
