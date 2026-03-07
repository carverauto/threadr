defmodule Threadr.ControlPlane.SystemLlmConfig do
  @moduledoc """
  Operator-managed default external LLM configuration for QA and summarization flows.
  """

  use Ash.Resource,
    domain: Threadr.ControlPlane,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "system_llm_configs"
    repo Threadr.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :scope,
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

    attribute :scope, :string do
      allow_nil? false
      default "default"
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

  identities do
    identity :unique_scope, [:scope]
  end

  policies do
    bypass context_equals(:system, true) do
      authorize_if always()
    end
  end
end
