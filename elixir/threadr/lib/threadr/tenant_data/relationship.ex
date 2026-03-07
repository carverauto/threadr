defmodule Threadr.TenantData.Relationship do
  @moduledoc """
  Tenant-scoped weighted inferred relationship between two actors.
  """

  use Ash.Resource,
    domain: Threadr.TenantData,
    data_layer: AshPostgres.DataLayer

  multitenancy do
    strategy :context
  end

  postgres do
    table "relationships"
    repo Threadr.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :relationship_type,
        :weight,
        :first_seen_at,
        :last_seen_at,
        :metadata,
        :from_actor_id,
        :to_actor_id,
        :source_message_id
      ]
    end

    update :update do
      primary? true
      accept [:weight, :last_seen_at, :metadata, :source_message_id]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :relationship_type, :string do
      allow_nil? false
    end

    attribute :weight, :integer do
      allow_nil? false
      default 1
    end

    attribute :first_seen_at, :utc_datetime_usec do
      allow_nil? false
    end

    attribute :last_seen_at, :utc_datetime_usec do
      allow_nil? false
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
    end

    timestamps()
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

    belongs_to :source_message, Threadr.TenantData.Message
  end

  identities do
    identity :unique_actor_relationship, [:from_actor_id, :to_actor_id, :relationship_type]
  end
end
