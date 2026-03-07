defmodule Threadr.TenantData.Message do
  @moduledoc """
  Tenant-scoped normalized chat message.
  """

  use Ash.Resource,
    domain: Threadr.TenantData,
    data_layer: AshPostgres.DataLayer

  multitenancy do
    strategy :context
  end

  postgres do
    table "messages"
    repo Threadr.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:external_id, :body, :observed_at, :raw, :metadata, :actor_id, :channel_id]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :external_id, :string

    attribute :body, :string do
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
    belongs_to :actor, Threadr.TenantData.Actor do
      allow_nil? false
    end

    belongs_to :channel, Threadr.TenantData.Channel do
      allow_nil? false
    end
  end
end
