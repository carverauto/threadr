defmodule Threadr.TenantData.Conversation do
  @moduledoc """
  Tenant-scoped reconstructed conversation state.
  """

  use Ash.Resource,
    domain: Threadr.TenantData,
    data_layer: AshPostgres.DataLayer

  multitenancy do
    strategy :context
  end

  postgres do
    table "conversations"
    repo Threadr.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :platform,
        :lifecycle_state,
        :opened_at,
        :last_message_at,
        :dormant_at,
        :closed_at,
        :participant_summary,
        :entity_summary,
        :open_pending_item_count,
        :topic_summary,
        :confidence_summary,
        :reconstruction_version,
        :metadata,
        :channel_id,
        :starter_message_id,
        :most_recent_message_id
      ]
    end

    update :update do
      primary? true

      accept [
        :lifecycle_state,
        :last_message_at,
        :dormant_at,
        :closed_at,
        :participant_summary,
        :entity_summary,
        :open_pending_item_count,
        :topic_summary,
        :confidence_summary,
        :reconstruction_version,
        :metadata,
        :most_recent_message_id
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :platform, :string do
      allow_nil? false
    end

    attribute :lifecycle_state, :string do
      allow_nil? false
    end

    attribute :opened_at, :utc_datetime_usec do
      allow_nil? false
    end

    attribute :last_message_at, :utc_datetime_usec do
      allow_nil? false
    end

    attribute :dormant_at, :utc_datetime_usec
    attribute :closed_at, :utc_datetime_usec

    attribute :participant_summary, :map do
      allow_nil? false
      default %{}
    end

    attribute :entity_summary, :map do
      allow_nil? false
      default %{}
    end

    attribute :open_pending_item_count, :integer do
      allow_nil? false
      default 0
    end

    attribute :topic_summary, :string

    attribute :confidence_summary, :map do
      allow_nil? false
      default %{}
    end

    attribute :reconstruction_version, :string do
      allow_nil? false
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
    end

    timestamps()
  end

  relationships do
    belongs_to :channel, Threadr.TenantData.Channel do
      allow_nil? false
      attribute_type :uuid
    end

    belongs_to :starter_message, Threadr.TenantData.Message do
      allow_nil? false
      attribute_type :uuid
    end

    belongs_to :most_recent_message, Threadr.TenantData.Message do
      allow_nil? false
      attribute_type :uuid
    end
  end
end
