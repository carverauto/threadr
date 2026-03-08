defmodule Threadr.ML.ExtractionProviderOptsTest do
  use ExUnit.Case, async: true

  alias Threadr.ML.ExtractionProviderOpts

  test "maps generation runtime opts into direct extraction provider opts" do
    opts =
      ExtractionProviderOpts.from_generation_runtime(
        generation_provider: Threadr.TestGenerationProvider,
        generation_provider_name: "custom-llm",
        generation_endpoint: "https://llm.example.test",
        generation_model: "test-chat",
        generation_api_key: "top-secret",
        generation_system_prompt: "ignored",
        generation_temperature: 0.2,
        generation_max_tokens: 123,
        generation_timeout: 45_000
      )

    assert opts == [
             timeout: 45_000,
             api_key: "top-secret",
             model: "test-chat",
             endpoint: "https://llm.example.test",
             provider_name: "custom-llm",
             generation_provider: Threadr.TestGenerationProvider
           ]
  end

  test "builds generation opts with extraction defaults" do
    opts =
      ExtractionProviderOpts.to_generation_opts(
        [model: "test-chat", generation_provider: Threadr.TestGenerationProvider],
        [mode: :extraction],
        system_prompt: "Extract facts",
        temperature: 0.0,
        max_tokens: 600
      )

    assert Keyword.get(opts, :provider) == Threadr.TestGenerationProvider
    assert Keyword.get(opts, :model) == "test-chat"
    assert Keyword.get(opts, :system_prompt) == "Extract facts"
    assert Keyword.get(opts, :temperature) == 0.0
    assert Keyword.get(opts, :max_tokens) == 600
    assert Keyword.get(opts, :mode) == :extraction
  end
end
