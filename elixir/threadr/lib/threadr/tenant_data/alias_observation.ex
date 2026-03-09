defmodule Threadr.TenantData.AliasObservation do
  @moduledoc """
  Tenant-scoped evidence that an alias value was observed on a specific message.
  """

  use Ash.Resource,
    domain: Threadr.TenantData,
    data_layer: AshPostgres.DataLayer

  multitenancy do
    strategy :context
  end

  postgres do
    table "alias_observations"
    repo Threadr.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :observed_at,
        :source_event_type,
        :platform_account_id,
        :metadata,
        :alias_id,
        :actor_id,
        :channel_id,
        :source_message_id,
        :source_context_event_id
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :observed_at, :utc_datetime_usec do
      allow_nil? false
    end

    attribute :source_event_type, :string do
      allow_nil? false
    end

    attribute :platform_account_id, :string

    attribute :metadata, :map do
      allow_nil? false
      default %{}
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :alias, Threadr.TenantData.Alias do
      allow_nil? false
    end

    belongs_to :actor, Threadr.TenantData.Actor do
      allow_nil? false
    end

    belongs_to :channel, Threadr.TenantData.Channel

    belongs_to :source_message, Threadr.TenantData.Message
    belongs_to :source_context_event, Threadr.TenantData.ContextEvent
  end

  identities do
    identity :unique_alias_message_observation, [:alias_id, :source_message_id]
    identity :unique_alias_context_observation, [:alias_id, :source_context_event_id]
  end
end
