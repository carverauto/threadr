defmodule Threadr.TenantData.Alias do
  @moduledoc """
  Tenant-scoped observed alias value for an actor handle or display identity.
  """

  use Ash.Resource,
    domain: Threadr.TenantData,
    data_layer: AshPostgres.DataLayer

  multitenancy do
    strategy :context
  end

  postgres do
    table "aliases"
    repo Threadr.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :platform,
        :value,
        :normalized_value,
        :alias_kind,
        :metadata,
        :first_seen_at,
        :last_seen_at,
        :actor_id
      ]
    end

    update :update do
      primary? true
      accept [:metadata, :last_seen_at, :actor_id]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :platform, :string do
      allow_nil? false
    end

    attribute :value, :string do
      allow_nil? false
    end

    attribute :normalized_value, :string do
      allow_nil? false
    end

    attribute :alias_kind, :string do
      allow_nil? false
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
    end

    attribute :first_seen_at, :utc_datetime_usec do
      allow_nil? false
    end

    attribute :last_seen_at, :utc_datetime_usec do
      allow_nil? false
    end

    timestamps()
  end

  relationships do
    belongs_to :actor, Threadr.TenantData.Actor
  end

  identities do
    identity :unique_platform_alias_kind_value, [:platform, :alias_kind, :normalized_value]
  end
end
