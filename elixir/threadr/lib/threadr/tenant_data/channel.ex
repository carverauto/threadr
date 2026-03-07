defmodule Threadr.TenantData.Channel do
  @moduledoc """
  Tenant-scoped chat channel or room.
  """

  use Ash.Resource,
    domain: Threadr.TenantData,
    data_layer: AshPostgres.DataLayer

  multitenancy do
    strategy :context
  end

  postgres do
    table "channels"
    repo Threadr.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:platform, :name, :external_id, :metadata]
    end

    update :update do
      primary? true
      accept [:external_id, :metadata]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :platform, :string do
      allow_nil? false
    end

    attribute :name, :string do
      allow_nil? false
    end

    attribute :external_id, :string

    attribute :metadata, :map do
      allow_nil? false
      default %{}
    end

    timestamps()
  end

  identities do
    identity :unique_platform_name, [:platform, :name]
  end
end
