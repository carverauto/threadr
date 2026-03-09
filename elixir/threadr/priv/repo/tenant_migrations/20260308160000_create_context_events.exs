defmodule Threadr.Repo.TenantMigrations.CreateContextEvents do
  use Ecto.Migration

  def up do
    create table(:context_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :external_id, :string, null: false
      add :platform, :string, null: false
      add :event_type, :string, null: false
      add :observed_at, :utc_datetime_usec, null: false
      add :raw, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}
      add :actor_id, references(:actors, type: :binary_id, on_delete: :nilify_all)
      add :channel_id, references(:channels, type: :binary_id, on_delete: :nilify_all)
      add :source_message_id, references(:messages, type: :binary_id, on_delete: :nilify_all)
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:context_events, [:external_id],
             name: :context_events_unique_external_id_index
           )

    create index(:context_events, [:event_type])
    create index(:context_events, [:actor_id])
    create index(:context_events, [:channel_id])
    create index(:context_events, [:source_message_id])
  end

  def down do
    drop table(:context_events)
  end
end
