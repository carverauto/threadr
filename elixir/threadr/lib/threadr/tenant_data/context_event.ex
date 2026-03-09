defmodule Threadr.TenantData.ContextEvent do
  @moduledoc """
  Tenant-scoped normalized non-message chat context event.
  """

  use Ash.Resource,
    domain: Threadr.TenantData,
    data_layer: AshPostgres.DataLayer

  multitenancy do
    strategy :context
  end

  postgres do
    table "context_events"
    repo Threadr.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :external_id,
        :platform,
        :event_type,
        :observed_at,
        :raw,
        :metadata,
        :actor_id,
        :channel_id,
        :source_message_id
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :external_id, :string do
      allow_nil? false
    end

    attribute :platform, :string do
      allow_nil? false
    end

    attribute :event_type, :string do
      allow_nil? false
    end

    attribute :observed_at, :utc_datetime_usec do
      allow_nil? false
    end

    attribute :raw, :map do
      allow_nil? false
      default %{}
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :actor, Threadr.TenantData.Actor
    belongs_to :channel, Threadr.TenantData.Channel
    belongs_to :source_message, Threadr.TenantData.Message
  end

  identities do
    identity :unique_external_context_event, [:external_id]
  end
end
