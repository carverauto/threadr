defmodule Threadr.ML.BotIntent do
  @moduledoc """
  Narrow intent router for direct-addressed bot turns.
  """

  @chat_phrases [
    "hello",
    "hi",
    "hey",
    "yo",
    "sup",
    "how are you",
    "how are you doing",
    "what's up",
    "whats up",
    "good morning",
    "good afternoon",
    "good evening",
    "thanks",
    "thank you"
  ]

  @spec classify(String.t()) :: :chat | :qa
  def classify(text) when is_binary(text) do
    normalized = normalize(text)

    cond do
      normalized == "" -> :qa
      normalized in @chat_phrases -> :chat
      String.ends_with?(normalized, "?") -> :qa
      starts_with_question_word?(normalized) -> :qa
      short_chat_like?(normalized) -> :chat
      true -> :qa
    end
  end

  defp starts_with_question_word?(text) do
    Enum.any?(
      ["who", "what", "when", "where", "why", "how", "which", "tell me", "summarize"],
      &String.starts_with?(text, &1 <> " ")
    )
  end

  defp short_chat_like?(text) do
    text
    |> String.split(~r/\s+/u, trim: true)
    |> length()
    |> Kernel.<=(4)
  end

  defp normalize(text) do
    text
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim_trailing("?")
    |> String.trim_trailing("!")
    |> String.trim_trailing(".")
  end
end
