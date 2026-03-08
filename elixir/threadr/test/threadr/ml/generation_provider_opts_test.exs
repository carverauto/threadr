defmodule Threadr.ML.GenerationProviderOptsTest do
  use ExUnit.Case, async: true

  alias Threadr.ML.GenerationProviderOpts

  test "maps prefixed generation runtime opts to provider opts" do
    opts =
      GenerationProviderOpts.from_prefixed(
        [
          generation_provider: Threadr.TestGenerationProvider,
          generation_model: "test-chat",
          generation_endpoint: "https://llm.example.test",
          generation_api_key: "top-secret",
          generation_system_prompt: "Be concise",
          generation_provider_name: "custom-llm",
          generation_temperature: 0.2,
          generation_max_tokens: 123,
          generation_timeout: 45_000
        ],
        context: %{"question" => "what happened?"}
      )

    assert Keyword.get(opts, :provider) == Threadr.TestGenerationProvider
    assert Keyword.get(opts, :model) == "test-chat"
    assert Keyword.get(opts, :endpoint) == "https://llm.example.test"
    assert Keyword.get(opts, :api_key) == "top-secret"
    assert Keyword.get(opts, :system_prompt) == "Be concise"
    assert Keyword.get(opts, :provider_name) == "custom-llm"
    assert Keyword.get(opts, :temperature) == 0.2
    assert Keyword.get(opts, :max_tokens) == 123
    assert Keyword.get(opts, :timeout) == 45_000
    assert Keyword.get(opts, :context) == %{"question" => "what happened?"}
  end
end
