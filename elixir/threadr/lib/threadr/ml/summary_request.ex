defmodule Threadr.ML.SummaryRequest do
  @moduledoc """
  Structured request parameters for tenant topic summarization flows.
  """

  alias Threadr.ML.RequestRuntimeOpts

  @runtime_option_keys RequestRuntimeOpts.common_keys()

  @enforce_keys [:topic]
  defstruct [:topic] ++ @runtime_option_keys

  @type t :: %__MODULE__{
          topic: String.t(),
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
          generation_timeout: integer() | nil
        }

  @spec new(String.t(), keyword()) :: t()
  def new(topic, opts \\ []) when is_binary(topic) and is_list(opts) do
    %__MODULE__{topic: topic}
    |> merge_runtime_opts(opts)
  end

  @spec merge_runtime_opts(t(), keyword()) :: t()
  def merge_runtime_opts(%__MODULE__{} = request, opts) when is_list(opts) do
    RequestRuntimeOpts.merge(request, opts, @runtime_option_keys)
  end

  @spec to_runtime_opts(t()) :: keyword()
  def to_runtime_opts(%__MODULE__{} = request) do
    RequestRuntimeOpts.to_keyword(request, @runtime_option_keys)
  end
end
