defmodule Threadr.ControlPlane.ApiKey do
  @moduledoc """
  Public API credential owned by a control-plane user.
  """

  use Ash.Resource,
    domain: Threadr.ControlPlane,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [:name, :user_id, :expires_at]

      change {AshAuthentication.Strategy.ApiKey.GenerateApiKey,
              prefix: :threadr, hash: :api_key_hash}
    end

    update :update do
      primary? true

      accept [:name, :expires_at, :revoked_at, :last_used_at]
    end
  end

  postgres do
    table "api_keys"
    repo Threadr.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :api_key_hash, :binary do
      allow_nil? false
      sensitive? true
      public? false
    end

    attribute :expires_at, :utc_datetime_usec do
      public? true
    end

    attribute :last_used_at, :utc_datetime_usec do
      public? true
    end

    attribute :revoked_at, :utc_datetime_usec do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Threadr.ControlPlane.User do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_api_key, [:api_key_hash]
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    bypass context_equals(:system, true) do
      authorize_if always()
    end

    policy action(:read) do
      authorize_if relates_to_actor_via(:user)
    end

    policy action(:create) do
      authorize_if {Threadr.ControlPlane.Checks.ActorMatchesAttribute, field: :user_id}
    end

    policy action(:update) do
      authorize_if {Threadr.ControlPlane.Checks.ActorMatchesAttribute, field: :user_id}
    end
  end
end
