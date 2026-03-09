defmodule Threadr.Repo.TenantMigrations.CreatePendingItems do
  use Ecto.Migration

  def up do
    create table(:pending_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :item_kind, :string, null: false
      add :status, :string, null: false
      add :owner_actor_ids, {:array, :string}, null: false, default: []
      add :referenced_entity_ids, {:array, :string}, null: false, default: []
      add :opened_at, :utc_datetime_usec, null: false
      add :resolved_at, :utc_datetime_usec
      add :summary_text, :text, null: false
      add :confidence, :float, null: false, default: 0.5
      add :supporting_evidence, {:array, :map}, null: false, default: []
      add :metadata, :map, null: false, default: %{}

      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :opener_message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :resolver_message_id, references(:messages, type: :binary_id, on_delete: :nilify_all)

      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create index(:pending_items, [:conversation_id])
    create index(:pending_items, [:status])
    create index(:pending_items, [:resolver_message_id])

    create unique_index(:pending_items, [:opener_message_id],
             name: :pending_items_unique_opener_message_index
           )
  end

  def down do
    drop table(:pending_items)
  end
end
