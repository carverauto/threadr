defmodule Threadr.TenantData.RelationshipObservation do
  @moduledoc """
  Tenant-scoped deduplicated evidence row for inferred or observed relationships.
  """

  use Ash.Resource,
    domain: Threadr.TenantData,
    data_layer: AshPostgres.DataLayer

  multitenancy do
    strategy :context
  end

  postgres do
    table "relationship_observations"
    repo Threadr.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :relationship_type,
        :observed_at,
        :metadata,
        :from_actor_id,
        :to_actor_id,
        :source_message_id
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :relationship_type, :string do
      allow_nil? false
    end

    attribute :observed_at, :utc_datetime_usec do
      allow_nil? false
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :from_actor, Threadr.TenantData.Actor do
      allow_nil? false
      attribute_type :uuid
    end

    belongs_to :to_actor, Threadr.TenantData.Actor do
      allow_nil? false
      attribute_type :uuid
    end

    belongs_to :source_message, Threadr.TenantData.Message do
      allow_nil? false
      attribute_type :uuid
    end
  end

  identities do
    identity :unique_relationship_observation, [
      :relationship_type,
      :source_message_id,
      :from_actor_id,
      :to_actor_id
    ]
  end
end
