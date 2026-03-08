defmodule Threadr.ML.ExtractionProviderOpts do
  @moduledoc false

  @direct_option_keys [
    :provider_name,
    :endpoint,
    :model,
    :api_key,
    :system_prompt,
    :temperature,
    :max_tokens,
    :timeout,
    :generation_provider
  ]

  @spec take_direct(keyword()) :: keyword()
  def take_direct(opts) when is_list(opts) do
    Keyword.take(opts, @direct_option_keys)
  end

  @spec from_generation_runtime(keyword()) :: keyword()
  def from_generation_runtime(generation_opts) when is_list(generation_opts) do
    []
    |> maybe_put(:generation_provider, Keyword.get(generation_opts, :generation_provider))
    |> maybe_put(:provider_name, Keyword.get(generation_opts, :generation_provider_name))
    |> maybe_put(:endpoint, Keyword.get(generation_opts, :generation_endpoint))
    |> maybe_put(:model, Keyword.get(generation_opts, :generation_model))
    |> maybe_put(:api_key, Keyword.get(generation_opts, :generation_api_key))
    |> maybe_put(:timeout, Keyword.get(generation_opts, :generation_timeout))
  end

  @spec to_generation_opts(keyword(), keyword(), keyword()) :: keyword()
  def to_generation_opts(opts, extra \\ [], defaults \\ [])
      when is_list(opts) and is_list(extra) and is_list(defaults) do
    provider =
      Keyword.get(
        opts,
        :generation_provider,
        Application.get_env(:threadr, Threadr.ML, [])
        |> Keyword.fetch!(:generation)
        |> Keyword.fetch!(:provider)
      )

    [
      provider: provider,
      provider_name: Keyword.get(opts, :provider_name),
      endpoint: Keyword.get(opts, :endpoint),
      model: Keyword.get(opts, :model),
      api_key: Keyword.get(opts, :api_key),
      system_prompt: Keyword.get(opts, :system_prompt, Keyword.get(defaults, :system_prompt)),
      temperature: Keyword.get(opts, :temperature, Keyword.get(defaults, :temperature)),
      max_tokens: Keyword.get(opts, :max_tokens, Keyword.get(defaults, :max_tokens)),
      timeout: Keyword.get(opts, :timeout)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Keyword.merge(extra)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
