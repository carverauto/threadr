defmodule Threadr.ControlPlane.TenantLlmConfig do
  @moduledoc """
  Tenant-scoped external LLM configuration for QA and summarization flows.
  """

  use Ash.Resource,
    domain: Threadr.ControlPlane,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "tenant_llm_configs"
    repo Threadr.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :tenant_id,
        :use_system,
        :provider_name,
        :endpoint,
        :model,
        :api_key,
        :system_prompt,
        :temperature,
        :max_tokens
      ]
    end

    update :update do
      primary? true

      accept [
        :use_system,
        :provider_name,
        :endpoint,
        :model,
        :api_key,
        :system_prompt,
        :temperature,
        :max_tokens
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :use_system, :boolean do
      allow_nil? false
      default true
      public? true
    end

    attribute :provider_name, :string do
      allow_nil? false
      default "openai"
      public? true
    end

    attribute :endpoint, :string do
      public? true
    end

    attribute :model, :string do
      public? true
    end

    attribute :api_key, :string do
      sensitive? true
      public? false
    end

    attribute :system_prompt, :string do
      public? true
    end

    attribute :temperature, :float do
      public? true
    end

    attribute :max_tokens, :integer do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :tenant, Threadr.ControlPlane.Tenant do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_tenant_llm_config, [:tenant_id]
  end

  policies do
    bypass context_equals(:system, true) do
      authorize_if always()
    end

    policy action(:read) do
      authorize_if {Threadr.ControlPlane.Checks.ManagesTenant, manager?: true}
    end

    policy action([:create, :update, :destroy]) do
      authorize_if {Threadr.ControlPlane.Checks.ManagesTenant, manager?: true}
    end
  end
end
