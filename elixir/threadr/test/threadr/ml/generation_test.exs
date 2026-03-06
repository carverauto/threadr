defmodule Threadr.ML.GenerationTest do
  use ExUnit.Case, async: true

  alias Threadr.ML.Generation

  test "completes prompts through the configured provider boundary" do
    assert {:ok, result} =
             Generation.complete(
               "What does Alice talk about?",
               provider: Threadr.TestGenerationProvider,
               model: "test-chat",
               system_prompt: "Answer briefly"
             )

    assert result.provider == "test"
    assert result.model == "test-chat"
    assert result.content == "answer: What does Alice talk about?"
    assert result.metadata["system_prompt"] == "Answer briefly"
    assert result.metadata["mode"] == :qa
  end

  test "returns a provider error when generation is disabled" do
    assert {:error, :generation_provider_not_configured} =
             Generation.complete(
               "Hello",
               provider: Threadr.ML.Generation.NoopProvider
             )
  end

  test "builds a summarization request through the generic interface" do
    assert {:ok, result} =
             Generation.summarize(
               "Alice discussed incident response and malware clusters.",
               provider: Threadr.TestGenerationProvider
             )

    assert result.metadata["mode"] == :summarization
  end

  test "builds a QA request with explicit context through the generic interface" do
    assert {:ok, result} =
             Generation.answer_question(
               "What does Alice know about Bob?",
               "Alice mentioned Bob in incident response planning.",
               provider: Threadr.TestGenerationProvider
             )

    assert result.metadata["mode"] == :qa
    assert result.metadata["context"]["question"] == "What does Alice know about Bob?"
  end

  test "passes provider-agnostic runtime options through the boundary" do
    assert {:ok, result} =
             Generation.complete(
               "What happened?",
               provider: Threadr.TestGenerationProvider,
               model: "test-chat",
               provider_name: "openai-compatible",
               temperature: 0.1,
               max_tokens: 128,
               timeout: 10_000
             )

    assert result.provider == "test"
    assert result.model == "test-chat"
  end
end
