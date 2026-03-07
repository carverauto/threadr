defmodule Threadr.Repo.TenantMigrations.CreateExtractedEntitiesAndFacts do
  use Ecto.Migration

  def up do
    create table(:extracted_entities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :entity_type, :string, null: false
      add :name, :string, null: false
      add :canonical_name, :string
      add :confidence, :float, null: false, default: 0.5
      add :metadata, :map, null: false, default: %{}

      add :source_message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:extracted_entities, [:source_message_id])
    create unique_index(:extracted_entities, [:source_message_id, :entity_type, :name])

    create constraint(:extracted_entities, :extracted_entities_confidence_between_zero_and_one,
             check: "confidence >= 0 AND confidence <= 1"
           )

    create table(:extracted_facts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :fact_type, :string, null: false
      add :subject, :string, null: false
      add :predicate, :string, null: false
      add :object, :text, null: false
      add :confidence, :float, null: false, default: 0.5
      add :valid_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      add :source_message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:extracted_facts, [:source_message_id])
    create index(:extracted_facts, [:fact_type])
    create index(:extracted_facts, [:subject])

    create unique_index(
             :extracted_facts,
             [:source_message_id, :fact_type, :subject, :predicate, :object]
           )

    create constraint(:extracted_facts, :extracted_facts_confidence_between_zero_and_one,
             check: "confidence >= 0 AND confidence <= 1"
           )
  end

  def down do
    drop table(:extracted_facts)
    drop table(:extracted_entities)
  end
end
