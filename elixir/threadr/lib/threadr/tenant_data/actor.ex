defmodule Threadr.TenantData.Actor do
  @moduledoc """
  Tenant-scoped actor observed in chat data.
  """

  use Ash.Resource,
    domain: Threadr.TenantData,
    data_layer: AshPostgres.DataLayer

  multitenancy do
    strategy :context
  end

  postgres do
    table "actors"
    repo Threadr.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:platform, :handle, :display_name, :external_id, :metadata, :last_seen_at]
    end

    update :update do
      primary? true
      accept [:display_name, :external_id, :metadata, :last_seen_at]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :platform, :string do
      allow_nil? false
    end

    attribute :handle, :string do
      allow_nil? false
    end

    attribute :display_name, :string
    attribute :external_id, :string

    attribute :metadata, :map do
      allow_nil? false
      default %{}
    end

    attribute :last_seen_at, :utc_datetime_usec

    timestamps()
  end

  identities do
    identity :unique_platform_handle, [:platform, :handle]
  end
end
