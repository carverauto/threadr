defmodule Threadr.ControlPlane.Tenant do
  @moduledoc """
  Public control-plane record that owns a dedicated tenant schema.
  """

  use Ash.Resource,
    domain: Threadr.ControlPlane,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "tenants"
    repo Threadr.Repo

    manage_tenant do
      template [:schema_name]
      update? false
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :name,
        :slug,
        :schema_name,
        :subject_name,
        :status,
        :tenant_migration_status,
        :tenant_migration_version,
        :tenant_migrated_at,
        :tenant_migration_error,
        :metadata,
        :kubernetes_namespace
      ]
    end

    update :update do
      primary? true

      accept [
        :name,
        :status,
        :tenant_migration_status,
        :tenant_migration_version,
        :tenant_migrated_at,
        :tenant_migration_error,
        :metadata,
        :kubernetes_namespace
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
    end

    attribute :slug, :string do
      allow_nil? false
    end

    attribute :schema_name, :string do
      allow_nil? false
    end

    attribute :subject_name, :string do
      allow_nil? false
    end

    attribute :status, :string do
      allow_nil? false
      default "active"
    end

    attribute :tenant_migration_status, :string do
      allow_nil? false
      default "pending"
    end

    attribute :tenant_migration_version, :integer
    attribute :tenant_migrated_at, :utc_datetime_usec
    attribute :tenant_migration_error, :string

    attribute :kubernetes_namespace, :string do
      allow_nil? false
      default "threadr"
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
    end

    timestamps()
  end

  relationships do
    has_many :bots, Threadr.ControlPlane.Bot do
      destination_attribute :tenant_id
    end

    has_many :tenant_memberships, Threadr.ControlPlane.TenantMembership do
      destination_attribute :tenant_id
    end
  end

  identities do
    identity :unique_slug, [:slug]
    identity :unique_schema_name, [:schema_name]
    identity :unique_subject_name, [:subject_name]
  end

  policies do
    bypass context_equals(:system, true) do
      authorize_if always()
    end

    policy action(:create) do
      authorize_if actor_present()
    end

    policy action(:read) do
      authorize_if expr(
                     exists(
                       Threadr.ControlPlane.TenantMembership,
                       tenant_id == parent(id) and user_id == ^actor(:id)
                     )
                   )
    end

    policy action([:update, :destroy]) do
      authorize_if {Threadr.ControlPlane.Checks.ManagesTenant, manager?: true}
    end
  end
end
