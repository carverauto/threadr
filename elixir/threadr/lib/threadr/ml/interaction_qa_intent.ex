defmodule Threadr.ML.InteractionQAIntent do
  @moduledoc """
  Lightweight routing for actor interaction partner questions.
  """

  @type t :: %{
          kind: :interaction_partners,
          actor_ref: String.t()
        }

  @suffixes [
    " mostly talk with",
    " mostly talk to",
    " talk with the most",
    " talk to the most",
    " mostly talks with",
    " mostly talks to",
    " talks with the most",
    " talks to the most"
  ]

  @spec classify(String.t()) :: {:ok, t()} | {:error, :not_interaction_question}
  def classify(question) when is_binary(question) do
    normalized = normalize_question(question)

    parse_reference(normalized, "who does ") ||
      parse_reference(normalized, "who do ") ||
      {:error, :not_interaction_question}
  end

  defp parse_reference(question, prefix) do
    with {:ok, rest} <- split_prefix(question, prefix),
         {:ok, actor_ref} <- strip_suffix(rest, @suffixes) do
      actor_ref = normalize_reference(actor_ref)

      if actor_ref == "" do
        nil
      else
        {:ok, %{kind: :interaction_partners, actor_ref: actor_ref}}
      end
    else
      _ -> nil
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

  defp strip_suffix(value, suffixes) do
    downcased = String.downcase(value)

    Enum.find_value(suffixes, :error, fn suffix ->
      if String.ends_with?(downcased, suffix) do
        value_size = byte_size(value)
        suffix_size = byte_size(suffix)
        {:ok, binary_part(value, 0, value_size - suffix_size)}
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
    |> String.trim()
  end
end
