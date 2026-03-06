defmodule Threadr.TestEmbeddingProvider do
  @behaviour Threadr.ML.Embeddings.Provider

  @impl true
  def embed_document(text, opts) do
    {:ok,
     %{
       embedding: [0.1, 0.2, 0.3],
       model: Keyword.get(opts, :model, "test-embedding-model"),
       provider: "test",
       metadata: %{"text_length" => String.length(text)}
     }}
  end
end

defmodule Threadr.TestGenerationProvider do
  @behaviour Threadr.ML.Generation.Provider

  alias Threadr.ML.Generation.Result

  @impl true
  def complete(request, opts) do
    {:ok,
     %Result{
       content: "answer: #{request.prompt}",
       model: Keyword.get(opts, :model, "test-llm"),
       provider: "test",
       metadata: %{
         "system_prompt" => request.system_prompt || Keyword.get(opts, :system_prompt),
         "mode" => request.mode,
         "context" => request.context
       }
     }}
  end
end
