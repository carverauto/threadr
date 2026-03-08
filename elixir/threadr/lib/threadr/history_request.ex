defmodule Threadr.HistoryRequest do
  @moduledoc """
  Structured history filters and compare windows for analyst-facing history flows.
  """

  alias Threadr.TimeWindow

  @option_keys [
    :query,
    :actor_handle,
    :channel_name,
    :entity_name,
    :entity_type,
    :fact_type,
    :limit
  ]

  @compare_option_keys [:compare_since, :compare_until]

  defstruct [
    :query,
    :actor_handle,
    :channel_name,
    :entity_name,
    :entity_type,
    :fact_type,
    :limit,
    window: %TimeWindow{},
    comparison_window: %TimeWindow{},
    ash_opts: []
  ]

  @type t :: %__MODULE__{
          query: String.t() | nil,
          actor_handle: String.t() | nil,
          channel_name: String.t() | nil,
          entity_name: String.t() | nil,
          entity_type: String.t() | nil,
          fact_type: String.t() | nil,
          limit: integer() | nil,
          window: TimeWindow.t(),
          comparison_window: TimeWindow.t(),
          ash_opts: keyword()
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    %__MODULE__{
      query: Keyword.get(opts, :query),
      actor_handle: Keyword.get(opts, :actor_handle),
      channel_name: Keyword.get(opts, :channel_name),
      entity_name: Keyword.get(opts, :entity_name),
      entity_type: Keyword.get(opts, :entity_type),
      fact_type: Keyword.get(opts, :fact_type),
      limit: Keyword.get(opts, :limit),
      window: TimeWindow.from_opts(opts),
      comparison_window: TimeWindow.from_opts(opts, :compare),
      ash_opts: Keyword.drop(opts, @option_keys ++ [:since, :until] ++ @compare_option_keys)
    }
  end

  @spec to_runtime_opts(t()) :: keyword()
  def to_runtime_opts(%__MODULE__{} = request) do
    base =
      []
      |> put_if_present(:query, request.query)
      |> put_if_present(:actor_handle, request.actor_handle)
      |> put_if_present(:channel_name, request.channel_name)
      |> put_if_present(:entity_name, request.entity_name)
      |> put_if_present(:entity_type, request.entity_type)
      |> put_if_present(:fact_type, request.fact_type)
      |> put_if_present(:limit, request.limit)
      |> Enum.reverse()

    base ++ TimeWindow.to_keyword(request.window)
  end

  @spec to_comparison_runtime_opts(t()) :: keyword()
  def to_comparison_runtime_opts(%__MODULE__{} = request) do
    base =
      []
      |> put_if_present(:query, request.query)
      |> put_if_present(:actor_handle, request.actor_handle)
      |> put_if_present(:channel_name, request.channel_name)
      |> put_if_present(:entity_name, request.entity_name)
      |> put_if_present(:entity_type, request.entity_type)
      |> put_if_present(:fact_type, request.fact_type)
      |> put_if_present(:limit, request.limit)
      |> Enum.reverse()

    base ++ TimeWindow.to_keyword(request.comparison_window)
  end

  @spec ash_opts(t()) :: keyword()
  def ash_opts(%__MODULE__{} = request), do: request.ash_opts

  defp put_if_present(opts, _key, nil), do: opts
  defp put_if_present(opts, _key, ""), do: opts
  defp put_if_present(opts, key, value), do: Keyword.put(opts, key, value)
end
