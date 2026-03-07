defmodule Threadr.TenantData.MessageEmbedding do
  @moduledoc """
  Tenant-scoped vector embedding attached to a message.
  """

  use Ash.Resource,
    domain: Threadr.TenantData,
    data_layer: AshPostgres.DataLayer

  multitenancy do
    strategy :context
  end

  postgres do
    table "message_embeddings"
    repo Threadr.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:model, :dimensions, :embedding, :metadata, :message_id]
    end

    update :update do
      primary? true
      accept [:dimensions, :embedding, :metadata]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :model, :string do
      allow_nil? false
    end

    attribute :dimensions, :integer do
      allow_nil? false
    end

    attribute :embedding, :vector do
      allow_nil? false
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
    end

    timestamps()
  end

  relationships do
    belongs_to :message, Threadr.TenantData.Message do
      allow_nil? false
    end
  end

  identities do
    identity :unique_message_model, [:message_id, :model]
  end
end
