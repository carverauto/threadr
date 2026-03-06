defmodule Threadr.ML.Embeddings.BumblebeeProvider do
  @moduledoc """
  Local sentence embedding provider backed by Bumblebee.
  """

  @behaviour Threadr.ML.Embeddings.Provider

  @cache_key {__MODULE__, :serving}

  @impl true
  def embed_document(text, opts) when is_binary(text) do
    text = String.trim(text)

    if text == "" do
      {:error, :blank_text}
    else
      config = config(opts)
      serving = fetch_serving(config)
      input = config[:document_prefix] <> text

      case Nx.Serving.run(serving, input) do
        %{embedding: embedding} ->
          {:ok,
           %{
             embedding: Nx.to_flat_list(embedding),
             model: config[:model],
             provider: "bumblebee",
             metadata: %{"document_prefix" => config[:document_prefix]}
           }}

        result ->
          {:error, {:unexpected_embedding_result, result}}
      end
    end
  rescue
    error ->
      {:error, {:embedding_failed, Exception.message(error)}}
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
    {:ok, model_info} =
      Bumblebee.load_model({:hf, config[:model]}, architecture: :for_embedding)

    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, config[:model]})

    Bumblebee.Text.text_embedding(model_info, tokenizer,
      output_attribute: :embedding,
      output_pool: :mean_pooling,
      embedding_processor: :l2_norm
    )
  end

  defp config(opts) do
    Application.get_env(:threadr, Threadr.ML, [])
    |> Keyword.fetch!(:embeddings)
    |> Keyword.merge(opts)
  end
end
