defmodule Threadr.Repo.TenantMigrations.CreateAliasesAndAliasObservations do
  use Ecto.Migration

  def up do
    create table(:aliases, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :platform, :string, null: false
      add :value, :string, null: false
      add :normalized_value, :string, null: false
      add :alias_kind, :string, null: false
      add :metadata, :map, null: false, default: %{}
      add :first_seen_at, :utc_datetime_usec, null: false
      add :last_seen_at, :utc_datetime_usec, null: false
      add :actor_id, references(:actors, type: :binary_id, on_delete: :nilify_all)
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create index(:aliases, [:actor_id])

    create unique_index(:aliases, [:platform, :alias_kind, :normalized_value],
             name: :aliases_unique_platform_alias_kind_value_index
           )

    create table(:alias_observations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :observed_at, :utc_datetime_usec, null: false
      add :source_event_type, :string, null: false
      add :platform_account_id, :string
      add :metadata, :map, null: false, default: %{}
      add :alias_id, references(:aliases, type: :binary_id, on_delete: :delete_all), null: false
      add :actor_id, references(:actors, type: :binary_id, on_delete: :delete_all), null: false

      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all),
        null: false

      add :source_message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:alias_observations, [:alias_id])
    create index(:alias_observations, [:actor_id])
    create index(:alias_observations, [:channel_id])
    create index(:alias_observations, [:source_message_id])

    create unique_index(:alias_observations, [:alias_id, :source_message_id],
             name: :alias_observations_unique_alias_message_index
           )
  end

  def down do
    drop table(:alias_observations)
    drop table(:aliases)
  end
end
