defmodule Threadr.TenantData.PendingItem do
  @moduledoc """
  Tenant-scoped unresolved conversational item.
  """

  use Ash.Resource,
    domain: Threadr.TenantData,
    data_layer: AshPostgres.DataLayer

  multitenancy do
    strategy :context
  end

  postgres do
    table "pending_items"
    repo Threadr.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :item_kind,
        :status,
        :owner_actor_ids,
        :referenced_entity_ids,
        :opened_at,
        :resolved_at,
        :summary_text,
        :confidence,
        :supporting_evidence,
        :metadata,
        :conversation_id,
        :opener_message_id,
        :resolver_message_id
      ]
    end

    update :update do
      primary? true

      accept [
        :status,
        :owner_actor_ids,
        :referenced_entity_ids,
        :resolved_at,
        :summary_text,
        :confidence,
        :supporting_evidence,
        :metadata,
        :resolver_message_id
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :item_kind, :string do
      allow_nil? false
    end

    attribute :status, :string do
      allow_nil? false
    end

    attribute :owner_actor_ids, {:array, :string} do
      allow_nil? false
      default []
    end

    attribute :referenced_entity_ids, {:array, :string} do
      allow_nil? false
      default []
    end

    attribute :opened_at, :utc_datetime_usec do
      allow_nil? false
    end

    attribute :resolved_at, :utc_datetime_usec

    attribute :summary_text, :string do
      allow_nil? false
    end

    attribute :confidence, :float do
      allow_nil? false
      default 0.5
    end

    attribute :supporting_evidence, {:array, :map} do
      allow_nil? false
      default []
    end

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

    belongs_to :opener_message, Threadr.TenantData.Message do
      allow_nil? false
      attribute_type :uuid
    end

    belongs_to :resolver_message, Threadr.TenantData.Message do
      attribute_type :uuid
    end
  end

  identities do
    identity :unique_opener_message_pending_item, [:opener_message_id]
  end
end
