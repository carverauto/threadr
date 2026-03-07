defmodule Threadr.ControlPlane.BotControllerContract do
  @moduledoc """
  Durable desired-state contract that a Kubernetes bot controller can own.
  """

  use Ash.Resource,
    domain: Threadr.ControlPlane,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "bot_controller_contracts"
    repo Threadr.Repo
  end

  actions do
    defaults [:read]

    create :upsert do
      primary? true

      accept [
        :tenant_id,
        :bot_id,
        :generation,
        :operation,
        :deployment_name,
        :namespace,
        :contract
      ]

      upsert? true
      upsert_identity :unique_bot_contract
    end

    update :update do
      primary? true

      accept [
        :generation,
        :operation,
        :deployment_name,
        :namespace,
        :contract
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :generation, :integer do
      allow_nil? false
    end

    attribute :operation, :string do
      allow_nil? false
    end

    attribute :deployment_name, :string do
      allow_nil? false
    end

    attribute :namespace, :string do
      allow_nil? false
    end

    attribute :contract, :map do
      allow_nil? false
      default %{}
    end

    timestamps()
  end

  relationships do
    belongs_to :tenant, Threadr.ControlPlane.Tenant do
      allow_nil? false
    end

    belongs_to :bot, Threadr.ControlPlane.Bot do
      allow_nil? false
    end
  end

  identities do
    identity :unique_bot_contract, [:bot_id]
  end
end
