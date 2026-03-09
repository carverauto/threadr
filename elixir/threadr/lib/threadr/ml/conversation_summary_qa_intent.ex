defmodule Threadr.ML.ConversationSummaryQAIntent do
  @moduledoc """
  Lightweight routing for time-bounded conversation summary questions.
  """

  @type t :: %{
          kind: :time_bounded_summary
        }

  @spec classify(String.t()) :: {:ok, t()} | {:error, :not_conversation_summary_question}
  def classify(question) when is_binary(question) do
    normalized = normalize_question(question)

    if summary_question?(normalized) do
      {:ok, %{kind: :time_bounded_summary}}
    else
      {:error, :not_conversation_summary_question}
    end
  end

  defp summary_question?(question) do
    starts_with_any?(question, [
      "what happened",
      "what was discussed",
      "what were people talking about",
      "what did people talk about",
      "summarize the conversations",
      "summarize what happened"
    ])
  end

  defp starts_with_any?(value, prefixes) do
    downcased = String.downcase(value)
    Enum.any?(prefixes, &String.starts_with?(downcased, &1))
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
