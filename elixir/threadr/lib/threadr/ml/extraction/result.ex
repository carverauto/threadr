defmodule Threadr.ML.Extraction.Result do
  @moduledoc """
  Provider-agnostic structured extraction result.
  """

  @enforce_keys [:entities, :facts, :model, :provider]
  defstruct [:entities, :facts, :model, :provider, metadata: %{}]

  @type entity :: %{
          required(:entity_type) => String.t(),
          required(:name) => String.t(),
          optional(:canonical_name) => String.t() | nil,
          optional(:confidence) => float(),
          optional(:metadata) => map()
        }

  @type fact :: %{
          required(:fact_type) => String.t(),
          required(:subject) => String.t(),
          required(:predicate) => String.t(),
          required(:object) => String.t(),
          optional(:confidence) => float(),
          optional(:valid_at) => String.t() | nil,
          optional(:metadata) => map()
        }

  @type t :: %__MODULE__{
          entities: [entity()],
          facts: [fact()],
          model: String.t(),
          provider: String.t(),
          metadata: map()
        }
end
