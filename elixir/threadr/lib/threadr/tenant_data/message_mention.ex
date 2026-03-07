defmodule Threadr.TenantData.MessageMention do
  @moduledoc """
  Tenant-scoped join resource for message mentions.
  """

  use Ash.Resource,
    domain: Threadr.TenantData,
    data_layer: AshPostgres.DataLayer

  multitenancy do
    strategy :context
  end

  postgres do
    table "message_mentions"
    repo Threadr.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:message_id, :actor_id]
    end
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :message, Threadr.TenantData.Message do
      allow_nil? false
    end

    belongs_to :actor, Threadr.TenantData.Actor do
      allow_nil? false
    end
  end

  identities do
    identity :unique_message_actor, [:message_id, :actor_id]
  end
end
