defmodule Threadr.ML.Embeddings.HashProvider do
  @moduledoc """
  Deterministic lexical embedding provider for local development and demo data.

  This is not a semantic model. It exists so the QA UI can work immediately in
  local environments without waiting on a heavyweight model runtime.
  """

  @behaviour Threadr.ML.Embeddings.Provider

  @default_dimensions 384
  @default_model "term-hash-384-v1"

  @impl true
  def embed_document(text, opts) when is_binary(text) do
    embed(text, :document, opts)
  end

  @impl true
  def embed_query(text, opts) when is_binary(text) do
    embed(text, :query, opts)
  end

  defp embed(text, input_type, opts) do
    text = String.trim(text)

    if text == "" do
      {:error, :blank_text}
    else
      dimensions = Keyword.get(opts, :dimensions, @default_dimensions)
      vector = vectorize(text, dimensions)

      {:ok,
       %{
         embedding: vector,
         model: Keyword.get(opts, :model, @default_model),
         provider: "hash",
         metadata: %{
           "dimensions" => dimensions,
           "input_type" => Atom.to_string(input_type),
           "token_count" => length(tokenize(text))
         }
       }}
    end
  end

  defp vectorize(text, dimensions) do
    values = :array.new(dimensions, default: 0.0)

    values =
      text
      |> tokenize()
      |> Enum.reduce(values, fn token, acc ->
        index = :erlang.phash2(token, dimensions)
        current = :array.get(index, acc)
        :array.set(index, current + 1.0, acc)
      end)

    values
    |> :array.to_list()
    |> normalize()
  end

  defp tokenize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9#._-]+/u, " ")
    |> String.split(~r/\s+/, trim: true)
  end

  defp normalize(values) do
    magnitude =
      values
      |> Enum.reduce(0.0, fn value, acc -> acc + value * value end)
      |> :math.sqrt()

    if magnitude == 0.0 do
      values
    else
      Enum.map(values, &(&1 / magnitude))
    end
  end
end
