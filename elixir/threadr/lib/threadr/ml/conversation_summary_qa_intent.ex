defmodule Threadr.ML.ConversationSummaryQAIntent do
  @moduledoc """
  Lightweight routing for time-bounded conversation summary questions.
  """

  @type t :: %{
          kind: :time_bounded_summary,
          time_scope: :today | :yesterday | :last_week | :last_month | :none,
          scope_current_channel: boolean()
        }

  @spec classify(String.t()) :: {:ok, t()} | {:error, :not_conversation_summary_question}
  def classify(question) when is_binary(question) do
    normalized = normalize_question(question)

    if summary_question?(normalized) do
      {:ok,
       %{
         kind: :time_bounded_summary,
         time_scope: infer_time_scope(normalized),
         scope_current_channel: current_channel_scope?(normalized)
       }}
    else
      {:error, :not_conversation_summary_question}
    end
  end

  defp summary_question?(question) do
    happened_summary_question?(question) or
      starts_with_any?(question, [
        "what was discussed",
        "what were people talking about",
        "what did people talk about",
        "recap the channel discussions",
        "recap the discussions",
        "recap what people talked about",
        "can you recap the channel discussions",
        "can you recap what people talked about",
        "summarize the conversations",
        "summarize what happened"
      ]) or
      topic_summary_question?(question)
  end

  defp topic_summary_question?(question) do
    summary_verb?(question) and
      summary_subject?(question) and
      infer_time_scope(question) != :none
  end

  defp happened_summary_question?(question) do
    starts_with_any?(question, [
      "what happened today",
      "what happened yesterday",
      "what happened last week",
      "what happened last month",
      "what happened in ",
      "what happened here"
    ])
  end

  defp starts_with_any?(value, prefixes) do
    downcased = String.downcase(value)
    Enum.any?(prefixes, &String.starts_with?(downcased, &1))
  end

  defp infer_time_scope(question) do
    cond do
      String.contains?(question, "today") or String.contains?(question, "todays") -> :today
      String.contains?(question, "yesterday") -> :yesterday
      String.contains?(question, "last week") -> :last_week
      String.contains?(question, "last month") -> :last_month
      true -> :none
    end
  end

  defp current_channel_scope?(question) do
    String.contains?(question, "channel") or
      String.contains?(question, "here") or
      Regex.match?(~r/(?:^|\s)#[^\s]+/u, question)
  end

  defp summary_verb?(question) do
    String.contains?(question, "recap") or
      String.contains?(question, "summarize") or
      String.contains?(question, "summary")
  end

  defp summary_subject?(question) do
    String.contains?(question, "conversations") or
      String.contains?(question, "topics") or
      String.contains?(question, "chats") or
      String.contains?(question, "discussions") or
      String.contains?(question, "talked about") or
      String.contains?(question, "talking about")
  end

  defp normalize_question(question) do
    question
    |> String.trim()
    |> String.trim_trailing("?")
    |> String.trim_trailing("!")
    |> String.trim_trailing(".")
    |> String.split()
    |> Enum.join(" ")
  end
end
