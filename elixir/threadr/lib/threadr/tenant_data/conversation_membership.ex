defmodule Threadr.TenantData.ConversationMembership do
  @moduledoc """
  Tenant-scoped membership evidence for reconstructed conversations.
  """

  use Ash.Resource,
    domain: Threadr.TenantData,
    data_layer: AshPostgres.DataLayer

  multitenancy do
    strategy :context
  end

  postgres do
    table "conversation_memberships"
    repo Threadr.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :member_kind,
        :member_id,
        :role,
        :score,
        :join_reason,
        :evidence,
        :attached_at,
        :detached_at,
        :metadata,
        :conversation_id
      ]
    end

    update :update do
      primary? true

      accept [:role, :score, :join_reason, :evidence, :detached_at, :metadata]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :member_kind, :string do
      allow_nil? false
    end

    attribute :member_id, :string do
      allow_nil? false
    end

    attribute :role, :string do
      allow_nil? false
    end

    attribute :score, :float do
      allow_nil? false
      default 1.0
    end

    attribute :join_reason, :string do
      allow_nil? false
    end

    attribute :evidence, {:array, :map} do
      allow_nil? false
      default []
    end

    attribute :attached_at, :utc_datetime_usec do
      allow_nil? false
    end

    attribute :detached_at, :utc_datetime_usec

    attribute :metadata, :map do
      allow_nil? false
      default %{}
    end

    timestamps()
  end

  relationships do
    belongs_to :conversation, Threadr.TenantData.Conversation do
      allow_nil? false
      attribute_type :uuid
    end
  end

  identities do
    identity :unique_conversation_member, [:conversation_id, :member_kind, :member_id]
  end
end
