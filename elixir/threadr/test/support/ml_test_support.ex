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

  @impl true
  def embed_query(text, opts) do
    {:ok,
     %{
       embedding: [0.4, 0.5, 0.6],
       model: Keyword.get(opts, :model, "test-embedding-model"),
       provider: "test",
       metadata: %{"text_length" => String.length(text), "input_type" => "query"}
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

defmodule Threadr.TestExtractionProvider do
  @behaviour Threadr.ML.Extraction.Provider

  alias Threadr.ML.Extraction.Result

  @impl true
  def extract(_request, opts) do
    {:ok,
     %Result{
       entities: [
         %{
           entity_type: "person",
           name: "Alice",
           canonical_name: "Alice",
           confidence: 0.98,
           metadata: %{}
         },
         %{
           entity_type: "person",
           name: "Bob",
           canonical_name: "Bob",
           confidence: 0.97,
           metadata: %{}
         }
       ],
       facts: [
         %{
           fact_type: "access_statement",
           subject: "Bob",
           predicate: "reported",
           object: "payroll access was limited",
           confidence: 0.94,
           valid_at: "2026-03-05T12:00:00Z",
           metadata: %{"topic" => "payroll"}
         }
       ],
       model: Keyword.get(opts, :model, "test-llm"),
       provider: "test",
       metadata: %{}
     }}
  end
end
