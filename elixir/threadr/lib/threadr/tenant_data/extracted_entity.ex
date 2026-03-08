defmodule Threadr.TenantData.ExtractedEntity do
  @moduledoc """
  Tenant-scoped structured entities extracted from message content.
  """

  use Ash.Resource,
    domain: Threadr.TenantData,
    data_layer: AshPostgres.DataLayer

  multitenancy do
    strategy :context
  end

  postgres do
    table "extracted_entities"
    repo Threadr.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:entity_type, :name, :canonical_name, :confidence, :metadata, :source_message_id]
    end

    update :update do
      primary? true
      accept [:canonical_name, :confidence, :metadata]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :entity_type, :string do
      allow_nil? false
    end

    attribute :name, :string do
      allow_nil? false
    end

    attribute :canonical_name, :string

    attribute :confidence, :float do
      allow_nil? false
      default 0.5
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
    end

    timestamps()
  end

  relationships do
    belongs_to :source_message, Threadr.TenantData.Message do
      allow_nil? false
    end
  end

  identities do
    identity :unique_message_entity, [:source_message_id, :entity_type, :name]
  end
end
