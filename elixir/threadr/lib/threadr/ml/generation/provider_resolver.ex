defmodule Threadr.ML.Generation.ProviderResolver do
  @moduledoc """
  Maps supported system LLM provider names to concrete adapter modules.
  """

  alias Threadr.ML.Generation.{
    AnthropicProvider,
    ChatCompletionsProvider,
    GeminiProvider
  }

  @supported ~w(anthropic gemini openai)

  def supported_provider_names, do: @supported

  def resolve(nil), do: {:error, :unsupported_generation_provider}

  def resolve(provider_name) when is_binary(provider_name) do
    case String.downcase(String.trim(provider_name)) do
      "openai" -> {:ok, ChatCompletionsProvider}
      "anthropic" -> {:ok, AnthropicProvider}
      "gemini" -> {:ok, GeminiProvider}
      _ -> {:error, :unsupported_generation_provider}
    end
  end

  def default_endpoint("openai"), do: "https://api.openai.com/v1/chat/completions"
  def default_endpoint("anthropic"), do: "https://api.anthropic.com/v1/messages"

  def default_endpoint("gemini"),
    do:
      "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

  def default_endpoint(_provider_name), do: nil
end
