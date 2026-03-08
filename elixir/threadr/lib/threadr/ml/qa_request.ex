defmodule Threadr.ML.QARequest do
  @moduledoc """
  Structured request parameters for tenant QA flows.
  """

  @runtime_option_keys [
    :limit,
    :graph_message_limit,
    :embedding_provider,
    :embedding_model,
    :embedding_endpoint,
    :embedding_api_key,
    :embedding_provider_name,
    :document_prefix,
    :query_prefix,
    :since,
    :until,
    :generation_provider,
    :generation_model,
    :generation_endpoint,
    :generation_api_key,
    :generation_system_prompt,
    :generation_provider_name,
    :generation_temperature,
    :generation_max_tokens,
    :generation_timeout,
    :requester_actor_handle,
    :requester_actor_display_name,
    :requester_external_id
  ]

  @enforce_keys [:question, :strategy]
  defstruct [:question, :strategy] ++ @runtime_option_keys

  @type strategy :: :bot | :user

  @type t :: %__MODULE__{
          question: String.t(),
          strategy: strategy(),
          limit: integer() | nil,
          graph_message_limit: integer() | nil,
          embedding_provider: module() | nil,
          embedding_model: String.t() | nil,
          embedding_endpoint: String.t() | nil,
          embedding_api_key: String.t() | nil,
          embedding_provider_name: String.t() | nil,
          document_prefix: String.t() | nil,
          query_prefix: String.t() | nil,
          since: DateTime.t() | NaiveDateTime.t() | nil,
          until: DateTime.t() | NaiveDateTime.t() | nil,
          generation_provider: module() | nil,
          generation_model: String.t() | nil,
          generation_endpoint: String.t() | nil,
          generation_api_key: String.t() | nil,
          generation_system_prompt: String.t() | nil,
          generation_provider_name: String.t() | nil,
          generation_temperature: number() | nil,
          generation_max_tokens: integer() | nil,
          generation_timeout: integer() | nil,
          requester_actor_handle: String.t() | nil,
          requester_actor_display_name: String.t() | nil,
          requester_external_id: String.t() | nil
        }

  @spec new(String.t(), strategy(), keyword()) :: t()
  def new(question, strategy, opts \\ [])
      when is_binary(question) and strategy in [:bot, :user] and is_list(opts) do
    %__MODULE__{question: question, strategy: strategy}
    |> merge_runtime_opts(opts)
  end

  @spec merge_runtime_opts(t(), keyword()) :: t()
  def merge_runtime_opts(%__MODULE__{} = request, opts) when is_list(opts) do
    Enum.reduce(@runtime_option_keys, request, fn key, acc ->
      case Keyword.fetch(opts, key) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end

  @spec to_runtime_opts(t()) :: keyword()
  def to_runtime_opts(%__MODULE__{} = request) do
    @runtime_option_keys
    |> Enum.reduce([], fn key, acc ->
      case Map.get(request, key) do
        nil -> acc
        value -> Keyword.put(acc, key, value)
      end
    end)
    |> Enum.reverse()
  end
end
