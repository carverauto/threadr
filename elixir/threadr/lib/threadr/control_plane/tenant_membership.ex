defmodule Threadr.ControlPlane.TenantMembership do
  @moduledoc """
  Joins users to tenants for SaaS access control.
  """

  use Ash.Resource,
    domain: Threadr.ControlPlane,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:role, :tenant_id, :user_id]
    end

    update :update do
      primary? true
      accept [:role]
    end
  end

  postgres do
    table "tenant_memberships"
    repo Threadr.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :string do
      allow_nil? false
      default "member"
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :tenant, Threadr.ControlPlane.Tenant do
      allow_nil? false
      public? true
    end

    belongs_to :user, Threadr.ControlPlane.User do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_user_tenant, [:user_id, :tenant_id]
  end

  policies do
    bypass context_equals(:system, true) do
      authorize_if always()
    end

    policy action(:read) do
      authorize_if expr(user_id == ^actor(:id))

      authorize_if expr(
                     exists(
                       tenant.tenant_memberships,
                       user_id == ^actor(:id) and role in ["owner", "admin"]
                     )
                   )
    end

    policy action([:create, :update, :destroy]) do
      authorize_if {Threadr.ControlPlane.Checks.ManagesTenant, manager?: true}
    end
  end
end
