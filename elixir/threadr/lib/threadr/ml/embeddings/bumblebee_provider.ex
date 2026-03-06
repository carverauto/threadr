defmodule Threadr.ML.Embeddings.BumblebeeProvider do
  @moduledoc """
  Local sentence embedding provider backed by Bumblebee.
  """

  @behaviour Threadr.ML.Embeddings.Provider

  @cache_key {__MODULE__, :serving}

  @impl true
  def embed_document(text, opts) when is_binary(text) do
    embed(text, :document, opts)
  end

  @impl true
  def embed_query(text, opts) when is_binary(text) do
    embed(text, :query, opts)
  end

  defp fetch_serving(config) do
    model_name = config[:model]

    case :persistent_term.get(@cache_key, nil) do
      %{model: model, serving: serving} when model == model_name ->
        serving

      _ ->
        serving = load_serving!(config)
        :persistent_term.put(@cache_key, %{model: model_name, serving: serving})
        serving
    end
  end

  defp load_serving!(config) do
    {:ok, model_info} = Bumblebee.load_model({:hf, config[:model]})

    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, config[:model]})

    Bumblebee.Text.text_embedding(model_info, tokenizer, embedding_processor: :l2_norm)
  end

  defp config(opts) do
    Application.get_env(:threadr, Threadr.ML, [])
    |> Keyword.fetch!(:embeddings)
    |> Keyword.merge(opts)
  end

  defp embed(text, input_type, opts) do
    text = String.trim(text)

    if text == "" do
      {:error, :blank_text}
    else
      config = config(opts)
      prefix = input_prefix(config, input_type)
      serving = fetch_serving(config)

      case Nx.Serving.run(serving, prefix <> text) do
        %{embedding: embedding} ->
          {:ok,
           %{
             embedding: Nx.to_flat_list(embedding),
             model: config[:model],
             provider: "bumblebee",
             metadata: %{
               "input_type" => Atom.to_string(input_type),
               "prefix" => prefix
             }
           }}

        result ->
          {:error, {:unexpected_embedding_result, result}}
      end
    end
  rescue
    error ->
      {:error, {:embedding_failed, Exception.message(error)}}
  end

  defp input_prefix(config, :document), do: config[:document_prefix] || ""
  defp input_prefix(config, :query), do: config[:query_prefix] || ""
end
