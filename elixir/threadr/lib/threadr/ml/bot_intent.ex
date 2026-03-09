defmodule Threadr.ML.BotIntent do
  @moduledoc """
  Narrow intent router for direct-addressed bot turns.
  """

  alias Threadr.ML.{
    ConversationQAIntent,
    ConversationSummaryQAIntent,
    InteractionQAIntent,
    QAIntent
  }

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
  @tenant_context_markers [
    "today",
    "yesterday",
    "last week",
    "last month",
    "this channel",
    "in the channel",
    "mentioned",
    "mentions",
    "talk about",
    "talked about",
    "been talking about",
    "talk with",
    "talk to",
    "talks with",
    "talks to",
    "mostly talk",
    "who does ",
    "who do i ",
    "who all",
    "what did ",
    "what have ",
    "what has ",
    "what were ",
    "what was said",
    "conversation",
    "know about",
    "said about"
  ]

  @spec classify(String.t()) :: :chat | :qa
  def classify(text) when is_binary(text) do
    normalized = normalize(text)

    cond do
      normalized == "" ->
        :qa

      normalized in @chat_phrases ->
        :chat

      qa_intent?(normalized) ->
        :qa

      tenant_context_question?(normalized) ->
        :qa

      true ->
        :chat
    end
  end

  defp qa_intent?(text) do
    match?({:ok, _}, InteractionQAIntent.classify(text)) or
      match?({:ok, _}, ConversationQAIntent.classify(text)) or
      match?({:ok, _}, QAIntent.classify(text)) or
      match?({:ok, _}, ConversationSummaryQAIntent.classify(text))
  end

  defp tenant_context_question?(text) do
    Enum.any?(@tenant_context_markers, &String.contains?(text, &1))
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
