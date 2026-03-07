defmodule Threadr.ControlPlane.BotReconcileOperation do
  @moduledoc """
  Durable outbox record for bot reconciliation intents.
  """

  use Ash.Resource,
    domain: Threadr.ControlPlane,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "bot_reconcile_operations"
    repo Threadr.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :tenant_id,
        :bot_id,
        :operation,
        :status,
        :payload,
        :attempt_count,
        :last_error,
        :dispatched_at,
        :next_attempt_at
      ]
    end

    update :update do
      primary? true

      accept [:status, :attempt_count, :last_error, :dispatched_at, :payload, :next_attempt_at]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :operation, :string do
      allow_nil? false
    end

    attribute :status, :string do
      allow_nil? false
      default "pending"
    end

    attribute :payload, :map do
      allow_nil? false
      default %{}
    end

    attribute :attempt_count, :integer do
      allow_nil? false
      default 0
    end

    attribute :last_error, :string
    attribute :dispatched_at, :utc_datetime_usec
    attribute :next_attempt_at, :utc_datetime_usec

    timestamps()
  end

  relationships do
    belongs_to :tenant, Threadr.ControlPlane.Tenant do
      allow_nil? false
    end

    belongs_to :bot, Threadr.ControlPlane.Bot
  end
end
