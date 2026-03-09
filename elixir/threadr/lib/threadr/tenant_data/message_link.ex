defmodule Threadr.TenantData.MessageLink do
  @moduledoc """
  Tenant-scoped scored message-to-message reconstruction link.
  """

  use Ash.Resource,
    domain: Threadr.TenantData,
    data_layer: AshPostgres.DataLayer

  multitenancy do
    strategy :context
  end

  postgres do
    table "message_links"
    repo Threadr.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :link_type,
        :score,
        :confidence_band,
        :winning_decision_version,
        :competing_candidate_margin,
        :evidence,
        :inferred_at,
        :inferred_by,
        :metadata,
        :source_message_id,
        :target_message_id
      ]
    end

    update :update do
      primary? true

      accept [
        :score,
        :confidence_band,
        :winning_decision_version,
        :competing_candidate_margin,
        :evidence,
        :inferred_at,
        :inferred_by,
        :metadata
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :link_type, :string do
      allow_nil? false
    end

    attribute :score, :float do
      allow_nil? false
    end

    attribute :confidence_band, :string do
      allow_nil? false
    end

    attribute :winning_decision_version, :string do
      allow_nil? false
    end

    attribute :competing_candidate_margin, :float do
      allow_nil? false
      default 0.0
    end

    attribute :evidence, {:array, :map} do
      allow_nil? false
      default []
    end

    attribute :inferred_at, :utc_datetime_usec do
      allow_nil? false
    end

    attribute :inferred_by, :string do
      allow_nil? false
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
    end

    timestamps()
  end

  relationships do
    belongs_to :source_message, Threadr.TenantData.Message do
      allow_nil? false
      attribute_type :uuid
    end

    belongs_to :target_message, Threadr.TenantData.Message do
      allow_nil? false
      attribute_type :uuid
    end
  end

  identities do
    identity :unique_message_link, [:source_message_id, :target_message_id, :link_type]
  end
end
