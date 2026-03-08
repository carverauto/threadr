defmodule Threadr.ML.GenerationProviderOpts do
  @moduledoc false

  @prefixed_option_keys [
    :generation_model,
    :generation_endpoint,
    :generation_api_key,
    :generation_system_prompt,
    :generation_provider_name,
    :generation_temperature,
    :generation_max_tokens,
    :generation_timeout
  ]

  @spec from_prefixed(keyword(), keyword()) :: keyword()
  def from_prefixed(opts, extra \\ []) when is_list(opts) and is_list(extra) do
    provider =
      Keyword.get(
        opts,
        :generation_provider,
        Application.get_env(:threadr, Threadr.ML, [])
        |> Keyword.fetch!(:generation)
        |> Keyword.fetch!(:provider)
      )

    base =
      opts
      |> Keyword.take(@prefixed_option_keys)
      |> Enum.reduce([provider: provider], fn
        {:generation_model, value}, acc -> Keyword.put(acc, :model, value)
        {:generation_endpoint, value}, acc -> Keyword.put(acc, :endpoint, value)
        {:generation_api_key, value}, acc -> Keyword.put(acc, :api_key, value)
        {:generation_system_prompt, value}, acc -> Keyword.put(acc, :system_prompt, value)
        {:generation_provider_name, value}, acc -> Keyword.put(acc, :provider_name, value)
        {:generation_temperature, value}, acc -> Keyword.put(acc, :temperature, value)
        {:generation_max_tokens, value}, acc -> Keyword.put(acc, :max_tokens, value)
        {:generation_timeout, value}, acc -> Keyword.put(acc, :timeout, value)
      end)

    Keyword.merge(base, extra)
  end
end
