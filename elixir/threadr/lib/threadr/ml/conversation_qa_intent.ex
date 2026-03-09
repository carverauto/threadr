defmodule Threadr.ML.ConversationQAIntent do
  @moduledoc """
  Lightweight routing for actor-pair conversation questions.
  """

  @type t :: %{
          kind: :talked_with,
          actor_ref: String.t(),
          target_ref: String.t()
        }

  @spec classify(String.t()) :: {:ok, t()} | {:error, :not_conversation_question}
  def classify(question) when is_binary(question) do
    normalized = normalize_question(question)

    parse_paired_talk_question(normalized) ||
      parse_with_talk_question(normalized) ||
      {:error, :not_conversation_question}
  end

  defp parse_paired_talk_question(question) do
    with {:ok, rest} <- prefix_match(question, ["what did ", "what have ", "what has "]),
         {:ok, actor_ref, remainder} <- split_between(rest, [" and "]),
         {:ok, target_ref, _suffix} <-
           split_between(
             remainder,
             [" talk about", " been talking about", " discuss", " been discussing"]
           ) do
      intent(actor_ref, target_ref)
    else
      _ -> nil
    end
  end

  defp parse_with_talk_question(question) do
    with {:ok, rest} <- prefix_match(question, ["what did ", "what have ", "what has "]),
         {:ok, actor_ref, target_ref} <-
           split_between(rest, [" talk about with ", " been talking about with "]) do
      intent(actor_ref, target_ref)
    else
      _ -> nil
    end
  end

  defp intent(actor_ref, target_ref) do
    actor_ref = normalize_reference(actor_ref)
    target_ref = normalize_reference(target_ref)

    if actor_ref == "" or target_ref == "" do
      nil
    else
      {:ok, %{kind: :talked_with, actor_ref: actor_ref, target_ref: target_ref}}
    end
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

  defp split_prefix(value, prefix) do
    if String.starts_with?(String.downcase(value), prefix) do
      prefix_size = byte_size(prefix)
      value_size = byte_size(value)
      {:ok, binary_part(value, prefix_size, value_size - prefix_size)}
    else
      :error
    end
  end

  defp prefix_match(value, prefixes) do
    Enum.find_value(prefixes, :error, fn prefix ->
      case split_prefix(value, prefix) do
        {:ok, _rest} = result -> result
        :error -> nil
      end
    end)
  end

  defp split_between(value, separators) do
    downcased = String.downcase(value)

    Enum.find_value(separators, :error, fn separator ->
      case :binary.match(downcased, separator) do
        {index, length} ->
          value_size = byte_size(value)

          {:ok, binary_part(value, 0, index),
           binary_part(value, index + length, value_size - index - length)}

        :nomatch ->
          nil
      end
    end)
  end

  defp normalize_reference(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.trim_trailing("?")
    |> String.trim_trailing("!")
    |> String.trim_trailing(".")
    |> trim_matching_quotes()
    |> String.trim()
  end

  defp trim_matching_quotes("\"" <> rest), do: rest |> String.trim_trailing("\"") |> String.trim()
  defp trim_matching_quotes("'" <> rest), do: rest |> String.trim_trailing("'") |> String.trim()
  defp trim_matching_quotes(value), do: value
end
