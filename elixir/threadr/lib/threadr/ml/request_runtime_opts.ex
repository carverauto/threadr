defmodule Threadr.ML.RequestRuntimeOpts do
  @moduledoc false

  @common_option_keys [
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
    :generation_timeout
  ]

  @requester_option_keys [
    :requester_actor_handle,
    :requester_actor_display_name,
    :requester_external_id
  ]

  @spec common_keys() :: [atom()]
  def common_keys, do: @common_option_keys

  @spec qa_keys() :: [atom()]
  def qa_keys, do: @common_option_keys ++ @requester_option_keys

  @spec take(keyword(), [atom()]) :: keyword()
  def take(opts, keys) when is_list(opts) and is_list(keys) do
    Keyword.take(opts, keys)
  end

  @spec drop(keyword(), [atom()]) :: keyword()
  def drop(opts, keys) when is_list(opts) and is_list(keys) do
    Keyword.drop(opts, keys)
  end

  @spec merge(map(), keyword(), [atom()]) :: map()
  def merge(request, opts, keys) when is_map(request) and is_list(opts) and is_list(keys) do
    Enum.reduce(keys, request, fn key, acc ->
      case Keyword.fetch(opts, key) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end

  @spec to_keyword(map(), [atom()]) :: keyword()
  def to_keyword(request, keys) when is_map(request) and is_list(keys) do
    keys
    |> Enum.reduce([], fn key, acc ->
      case Map.get(request, key) do
        nil -> acc
        value -> Keyword.put(acc, key, value)
      end
    end)
    |> Enum.reverse()
  end
end
