defmodule Threadr.TenantData.CommandExecution do
  @moduledoc """
  Tenant-scoped persisted ingest command envelope.
  """

  use Ash.Resource,
    domain: Threadr.TenantData,
    data_layer: AshPostgres.DataLayer

  multitenancy do
    strategy :context
  end

  postgres do
    table "command_executions"
    repo Threadr.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :external_id,
        :platform,
        :command,
        :target,
        :args,
        :status,
        :metadata,
        :issued_at,
        :worker_id,
        :claimed_at,
        :completed_at,
        :last_error
      ]
    end

    update :update do
      primary? true

      accept [
        :target,
        :args,
        :status,
        :metadata,
        :issued_at,
        :worker_id,
        :claimed_at,
        :completed_at,
        :last_error
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :external_id, :string do
      allow_nil? false
    end

    attribute :platform, :string do
      allow_nil? false
    end

    attribute :command, :string do
      allow_nil? false
    end

    attribute :target, :string

    attribute :args, :map do
      allow_nil? false
      default %{}
    end

    attribute :status, :string do
      allow_nil? false
      default "received"
    end

    attribute :worker_id, :string
    attribute :claimed_at, :utc_datetime_usec
    attribute :completed_at, :utc_datetime_usec
    attribute :last_error, :string

    attribute :metadata, :map do
      allow_nil? false
      default %{}
    end

    attribute :issued_at, :utc_datetime_usec do
      allow_nil? false
    end

    timestamps()
  end

  identities do
    identity :unique_external_id, [:external_id]
  end
end
