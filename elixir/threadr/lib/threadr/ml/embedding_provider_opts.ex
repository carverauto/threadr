defmodule Threadr.ML.EmbeddingProviderOpts do
  @moduledoc false

  @prefixed_option_keys [
    :embedding_model,
    :embedding_endpoint,
    :embedding_api_key,
    :embedding_provider_name,
    :document_prefix,
    :query_prefix
  ]

  @direct_option_keys [
    :model,
    :endpoint,
    :api_key,
    :provider_name,
    :document_prefix,
    :query_prefix
  ]

  @spec from_prefixed(keyword(), keyword()) :: keyword()
  def from_prefixed(opts, extra \\ []) when is_list(opts) and is_list(extra) do
    provider =
      Keyword.get(
        opts,
        :embedding_provider,
        Application.get_env(:threadr, Threadr.ML, [])
        |> Keyword.fetch!(:embeddings)
        |> Keyword.fetch!(:provider)
      )

    base =
      opts
      |> Keyword.take(@prefixed_option_keys)
      |> Enum.reduce([provider: provider], fn
        {:embedding_model, value}, acc -> Keyword.put(acc, :model, value)
        {:embedding_endpoint, value}, acc -> Keyword.put(acc, :endpoint, value)
        {:embedding_api_key, value}, acc -> Keyword.put(acc, :api_key, value)
        {:embedding_provider_name, value}, acc -> Keyword.put(acc, :provider_name, value)
        {key, value}, acc -> Keyword.put(acc, key, value)
      end)

    Keyword.merge(base, extra)
  end

  @spec from_direct(keyword()) :: keyword()
  def from_direct(opts) when is_list(opts) do
    opts
    |> Keyword.take(@direct_option_keys)
  end
end
