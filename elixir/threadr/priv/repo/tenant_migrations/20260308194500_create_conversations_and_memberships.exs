defmodule Threadr.Repo.TenantMigrations.CreateConversationsAndMemberships do
  use Ecto.Migration

  def up do
    create table(:conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :platform, :string, null: false
      add :lifecycle_state, :string, null: false
      add :opened_at, :utc_datetime_usec, null: false
      add :last_message_at, :utc_datetime_usec, null: false
      add :dormant_at, :utc_datetime_usec
      add :closed_at, :utc_datetime_usec
      add :participant_summary, :map, null: false, default: %{}
      add :entity_summary, :map, null: false, default: %{}
      add :open_pending_item_count, :integer, null: false, default: 0
      add :topic_summary, :text
      add :confidence_summary, :map, null: false, default: %{}
      add :reconstruction_version, :string, null: false
      add :metadata, :map, null: false, default: %{}

      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all),
        null: false

      add :starter_message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :most_recent_message_id,
          references(:messages, type: :binary_id, on_delete: :delete_all), null: false

      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create index(:conversations, [:channel_id])
    create index(:conversations, [:lifecycle_state])
    create index(:conversations, [:starter_message_id])
    create index(:conversations, [:most_recent_message_id])

    create table(:conversation_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :member_kind, :string, null: false
      add :member_id, :string, null: false
      add :role, :string, null: false
      add :score, :float, null: false, default: 1.0
      add :join_reason, :string, null: false
      add :evidence, {:array, :map}, null: false, default: []
      add :attached_at, :utc_datetime_usec, null: false
      add :detached_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create index(:conversation_memberships, [:conversation_id])
    create index(:conversation_memberships, [:member_kind, :member_id])

    create unique_index(:conversation_memberships, [:conversation_id, :member_kind, :member_id],
             name: :conversation_memberships_unique_member_index
           )
  end

  def down do
    drop table(:conversation_memberships)
    drop table(:conversations)
  end
end
