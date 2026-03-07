defmodule Threadr.ControlPlane.User do
  @moduledoc """
  Public control-plane user with password and API key authentication.
  """

  use Ash.Resource,
    domain: Threadr.ControlPlane,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  actions do
    defaults [:read]

    create :create_bootstrap_user do
      accept [:email, :name, :is_operator_admin, :must_rotate_password]

      argument :password, :string do
        allow_nil? false
        sensitive? true
        constraints min_length: 12
      end

      change Threadr.ControlPlane.Changes.NormalizeEmail
      change {AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password}
    end

    update :update do
      primary? true
      accept [:email, :name]
      require_atomic? false
      change Threadr.ControlPlane.Changes.NormalizeEmail
    end

    update :change_password do
      accept []
      require_atomic? false

      argument :current_password, :string do
        allow_nil? false
        sensitive? true
      end

      argument :password, :string do
        allow_nil? false
        sensitive? true
        constraints min_length: 12
      end

      argument :password_confirmation, :string do
        allow_nil? false
        sensitive? true
      end

      validate confirm(:password, :password_confirmation)

      validate {AshAuthentication.Strategy.Password.PasswordValidation,
                strategy_name: :password, password_argument: :current_password}

      change {AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password}
      change set_attribute(:must_rotate_password, false)
    end

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    read :operator_admins do
      filter expr(is_operator_admin == true)
    end

    read :sign_in_with_api_key do
      argument :api_key, :string, allow_nil?: false
      prepare AshAuthentication.Strategy.ApiKey.SignInPreparation
    end
  end

  authentication do
    session_identifier :jti

    tokens do
      enabled? true
      token_resource Threadr.ControlPlane.Token
      store_all_tokens? true
      require_token_presence_for_authentication? true

      signing_secret fn _, _ ->
        {:ok, Application.fetch_env!(:threadr, :token_signing_secret)}
      end
    end

    strategies do
      password :password do
        identity_field :email
        hashed_password_field :hashed_password
        register_action_accept [:name]
        sign_in_tokens_enabled? true
        confirmation_required? false
      end

      api_key :api_key do
        api_key_relationship :valid_api_keys
        api_key_hash_attribute :api_key_hash
      end
    end
  end

  postgres do
    table "users"
    repo Threadr.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :name, :string do
      allow_nil? true
      public? true
    end

    attribute :is_operator_admin, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :must_rotate_password, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :hashed_password, :string do
      allow_nil? false
      sensitive? true
      public? false
    end

    timestamps()
  end

  relationships do
    has_many :api_keys, Threadr.ControlPlane.ApiKey do
      destination_attribute :user_id
      public? true
    end

    has_many :tenant_memberships, Threadr.ControlPlane.TenantMembership do
      destination_attribute :user_id
      public? true
    end

    has_many :valid_api_keys, Threadr.ControlPlane.ApiKey do
      destination_attribute :user_id
      filter expr(is_nil(revoked_at) and (is_nil(expires_at) or expires_at > now()))
      public? false
    end
  end

  identities do
    identity :unique_email, [:email]
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    bypass context_equals(:system, true) do
      authorize_if always()
    end

    policy action([
             :register_with_password,
             :sign_in_with_password,
             :sign_in_with_api_key,
             :get_by_subject
           ]) do
      authorize_if always()
    end

    policy action([:read, :update, :change_password]) do
      authorize_if expr(id == ^actor(:id))
    end
  end
end
