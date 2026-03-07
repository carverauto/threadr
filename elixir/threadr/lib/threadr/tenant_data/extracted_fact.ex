defmodule Threadr.TenantData.ExtractedFact do
  @moduledoc """
  Tenant-scoped structured temporal facts extracted from message content.
  """

  use Ash.Resource,
    domain: Threadr.TenantData,
    data_layer: AshPostgres.DataLayer

  multitenancy do
    strategy :context
  end

  postgres do
    table "extracted_facts"
    repo Threadr.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :fact_type,
        :subject,
        :predicate,
        :object,
        :confidence,
        :valid_at,
        :metadata,
        :source_message_id
      ]
    end

    update :update do
      primary? true
      accept [:confidence, :valid_at, :metadata]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :fact_type, :string do
      allow_nil? false
    end

    attribute :subject, :string do
      allow_nil? false
    end

    attribute :predicate, :string do
      allow_nil? false
    end

    attribute :object, :string do
      allow_nil? false
    end

    attribute :confidence, :float do
      allow_nil? false
      default 0.5
    end

    attribute :valid_at, :utc_datetime_usec

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
    identity :unique_message_fact, [:source_message_id, :fact_type, :subject, :predicate, :object]
  end
end
