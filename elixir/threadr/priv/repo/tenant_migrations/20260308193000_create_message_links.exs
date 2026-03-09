defmodule Threadr.Repo.TenantMigrations.CreateMessageLinks do
  use Ecto.Migration

  def up do
    create table(:message_links, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :link_type, :string, null: false
      add :score, :float, null: false
      add :confidence_band, :string, null: false
      add :winning_decision_version, :string, null: false
      add :competing_candidate_margin, :float, null: false, default: 0.0
      add :evidence, {:array, :map}, null: false, default: []
      add :inferred_at, :utc_datetime_usec, null: false
      add :inferred_by, :string, null: false
      add :metadata, :map, null: false, default: %{}

      add :source_message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :target_message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create index(:message_links, [:source_message_id])
    create index(:message_links, [:target_message_id])
    create index(:message_links, [:link_type])
    create index(:message_links, [:confidence_band])

    create unique_index(:message_links, [:source_message_id, :target_message_id, :link_type],
             name: :message_links_unique_source_target_type_index
           )
  end

  def down do
    drop table(:message_links)
  end
end
