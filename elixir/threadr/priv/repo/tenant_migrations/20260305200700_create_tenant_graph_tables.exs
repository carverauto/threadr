defmodule Threadr.Repo.TenantMigrations.CreateTenantGraphTables do
  use Ecto.Migration

  def up do
    create_graph_tables()
  end

  def down do
    drop table(:message_embeddings)
    drop table(:relationships)
    drop table(:message_mentions)
    drop table(:messages)
    drop table(:channels)
    drop table(:actors)
  end

  defp create_graph_tables do
    create table(:actors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :platform, :string, null: false
      add :handle, :string, null: false
      add :display_name, :string
      add :external_id, :string
      add :metadata, :map, null: false, default: %{}
      add :last_seen_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:actors, [:platform, :handle])

    create index(:actors, [:platform, :external_id],
             unique: true,
             where: "external_id IS NOT NULL"
           )

    create table(:channels, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :platform, :string, null: false
      add :name, :string, null: false
      add :external_id, :string
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:channels, [:platform, :name])

    create index(:channels, [:platform, :external_id],
             unique: true,
             where: "external_id IS NOT NULL"
           )

    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :external_id, :string
      add :body, :text, null: false
      add :observed_at, :utc_datetime_usec, null: false
      add :raw, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}
      add :actor_id, references(:actors, type: :binary_id, on_delete: :nothing), null: false
      add :channel_id, references(:channels, type: :binary_id, on_delete: :nothing), null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:messages, [:actor_id, :observed_at])
    create index(:messages, [:channel_id, :observed_at])

    create index(:messages, [:channel_id, :external_id],
             unique: true,
             where: "external_id IS NOT NULL"
           )

    create table(:message_mentions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :actor_id, references(:actors, type: :binary_id, on_delete: :delete_all), null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:message_mentions, [:message_id, :actor_id])
    create index(:message_mentions, [:actor_id])

    create table(:relationships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :relationship_type, :string, null: false
      add :weight, :integer, null: false, default: 1
      add :first_seen_at, :utc_datetime_usec, null: false
      add :last_seen_at, :utc_datetime_usec, null: false
      add :metadata, :map, null: false, default: %{}

      add :from_actor_id, references(:actors, type: :binary_id, on_delete: :delete_all),
        null: false

      add :to_actor_id, references(:actors, type: :binary_id, on_delete: :delete_all), null: false
      add :source_message_id, references(:messages, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:relationships, [:from_actor_id])
    create index(:relationships, [:to_actor_id])
    create unique_index(:relationships, [:from_actor_id, :to_actor_id, :relationship_type])
    create constraint(:relationships, :relationships_weight_must_be_positive, check: "weight > 0")

    create table(:message_embeddings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :model, :string, null: false
      add :dimensions, :integer, null: false
      add :embedding, :vector, null: false
      add :metadata, :map, null: false, default: %{}

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:message_embeddings, [:message_id])
    create unique_index(:message_embeddings, [:message_id, :model])

    create constraint(:message_embeddings, :message_embeddings_dimensions_must_be_positive,
             check: "dimensions > 0"
           )
  end
end
