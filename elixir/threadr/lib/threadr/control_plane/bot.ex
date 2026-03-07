defmodule Threadr.ControlPlane.Bot do
  @moduledoc """
  Public control-plane record for tenant-managed bot workloads.
  """

  use Ash.Resource,
    domain: Threadr.ControlPlane,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "bots"
    repo Threadr.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :name,
        :platform,
        :desired_state,
        :channels,
        :settings,
        :deployment_name,
        :desired_generation,
        :observed_generation,
        :tenant_id
      ]

      change Threadr.ControlPlane.Changes.NormalizeAndValidateBotConfig
    end

    update :update do
      primary? true
      require_atomic? false

      accept [
        :desired_state,
        :channels,
        :settings,
        :deployment_name,
        :desired_generation,
        :observed_generation
      ]

      change Threadr.ControlPlane.Changes.NormalizeAndValidateBotConfig
    end

    update :request_reconcile do
      require_atomic? false
      accept [:deployment_name]
      change Threadr.ControlPlane.Changes.RequestBotReconcile
    end

    update :report_status do
      require_atomic? false

      argument :target_status, Threadr.ControlPlane.BotStatus do
        allow_nil? false
      end

      accept [
        :deployment_name,
        :status_reason,
        :status_metadata,
        :last_observed_at,
        :observed_generation
      ]

      change Threadr.ControlPlane.Changes.ReportBotStatus
    end

    update :begin_delete do
      require_atomic? false
      accept [:status_reason, :status_metadata]
      change Threadr.ControlPlane.Changes.BeginBotDelete
    end

    update :finalize_delete do
      require_atomic? false

      accept [
        :deployment_name,
        :status_reason,
        :status_metadata,
        :last_observed_at,
        :observed_generation
      ]

      change Threadr.ControlPlane.Changes.FinalizeBotDelete
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
    end

    attribute :platform, :string do
      allow_nil? false
    end

    attribute :desired_state, :string do
      allow_nil? false
      default "running"
    end

    attribute :status, Threadr.ControlPlane.BotStatus do
      allow_nil? false
      default :pending
    end

    attribute :status_reason, :string

    attribute :status_metadata, :map do
      allow_nil? false
      default %{}
    end

    attribute :last_observed_at, :utc_datetime_usec

    attribute :desired_generation, :integer do
      allow_nil? false
      default 0
    end

    attribute :observed_generation, :integer

    attribute :channels, {:array, :string} do
      allow_nil? false
      default []
    end

    attribute :settings, :map do
      allow_nil? false
      default %{}
    end

    attribute :deployment_name, :string

    timestamps()
  end

  state_machine do
    state_attribute(:status)
    initial_states([:pending])
    default_initial_state(:pending)
    extra_states([:reconciling, :running, :stopped, :degraded, :deleting, :deleted, :error])

    transitions do
      transition(:request_reconcile,
        from: [:pending, :running, :stopped, :degraded, :error],
        to: :reconciling
      )

      transition(:report_status,
        from: [:pending, :reconciling, :running, :stopped, :degraded, :error, :deleting],
        to: [:reconciling, :running, :stopped, :degraded, :error, :deleting]
      )

      transition(:begin_delete,
        from: [:pending, :reconciling, :running, :stopped, :degraded, :error],
        to: :deleting
      )

      transition(:finalize_delete, from: [:deleting], to: :deleted)
    end
  end

  relationships do
    belongs_to :tenant, Threadr.ControlPlane.Tenant do
      allow_nil? false
    end
  end

  identities do
    identity :unique_bot_name_per_tenant, [:tenant_id, :name]
  end

  policies do
    bypass context_equals(:system, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via([:tenant, :tenant_memberships, :user])
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if {Threadr.ControlPlane.Checks.ManagesTenant, manager?: true}
    end
  end
end
