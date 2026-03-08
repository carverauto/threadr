defmodule Threadr.ML.QAIntent do
  @moduledoc """
  Lightweight routing for question shapes that should use specialized QA paths.
  """

  @type t :: %{
          kind: :talks_about | :knows_about | :says_about,
          actor_ref: String.t(),
          target_ref: String.t() | nil
        }

  @spec classify(String.t()) :: {:ok, t()} | {:error, :not_actor_question}
  def classify(question) when is_binary(question) do
    normalized = normalize_question(question)

    parse_knows_about(normalized) ||
      parse_talks_about(normalized) ||
      parse_says_about(normalized) ||
      {:error, :not_actor_question}
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

  defp parse_knows_about(question) do
    case split_prefix(question, "what do you know about ") do
      {:ok, actor_ref} -> intent(:knows_about, actor_ref)
      :error -> nil
    end
  end

  defp parse_talks_about(question) do
    with {:ok, rest} <- split_prefix(question, "what "),
         {:ok, stem} <-
           suffix_match(
             rest,
             [" mostly talk about", " talk about"],
             &stem_without_suffix(rest, &1)
           ),
         {:ok, actor_ref} <- actor_ref_from_talks_about(stem) do
      intent(:talks_about, actor_ref)
    else
      _ -> nil
    end
  end

  defp parse_says_about(question) do
    with {:ok, rest} <- prefix_match(question, ["what does ", "what did ", "what has "]),
         {:ok, actor_ref, target_ref} <-
           split_between(rest, [" say about ", " been saying about "]) do
      intent(:says_about, actor_ref, target_ref)
    else
      _ -> nil
    end
  end

  defp intent(kind, actor_ref, target_ref \\ nil) do
    actor_ref = normalize_reference(actor_ref)
    target_ref = if is_binary(target_ref), do: normalize_reference(target_ref), else: nil

    if actor_ref == "" or (is_binary(target_ref) and target_ref == "") do
      nil
    else
      {:ok, %{kind: kind, actor_ref: actor_ref, target_ref: target_ref}}
    end
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

  defp stem_without_suffix(value, suffix) do
    value_size = byte_size(value)
    suffix_size = byte_size(suffix)
    {:ok, binary_part(value, 0, value_size - suffix_size)}
  end

  defp actor_ref_from_talks_about(stem) do
    case split_prefix(stem, "does ") do
      {:ok, actor_ref} ->
        {:ok, actor_ref}

      :error ->
        split_after_last(stem, " does ")
    end
  end

  defp split_after_last(value, separator) do
    downcased = String.downcase(value)

    case :binary.matches(downcased, separator) do
      [] ->
        :error

      matches ->
        {index, length} = List.last(matches)
        value_size = byte_size(value)
        {:ok, binary_part(value, index + length, value_size - index - length)}
    end
  end

  defp suffix_match(value, suffixes, result_fun) do
    downcased = String.downcase(value)

    Enum.find_value(suffixes, :error, fn suffix ->
      if String.ends_with?(downcased, suffix) do
        result_fun.(suffix)
      else
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
