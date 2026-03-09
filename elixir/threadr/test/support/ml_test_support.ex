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

defmodule Threadr.TestEmbeddingOptsProvider do
  @behaviour Threadr.ML.Embeddings.Provider

  @impl true
  def embed_document(text, opts) do
    {:ok,
     %{
       embedding: [0.1, 0.2, 0.3],
       model: Keyword.get(opts, :model, "test-embedding-model"),
       provider: "test-opts",
       metadata: build_metadata(text, opts, "document")
     }}
  end

  @impl true
  def embed_query(text, opts) do
    {:ok,
     %{
       embedding: [0.4, 0.5, 0.6],
       model: Keyword.get(opts, :model, "test-embedding-model"),
       provider: "test-opts",
       metadata: build_metadata(text, opts, "query")
     }}
  end

  defp build_metadata(text, opts, input_type) do
    %{
      "text_length" => String.length(text),
      "input_type" => input_type,
      "endpoint" => Keyword.get(opts, :endpoint),
      "api_key" => Keyword.get(opts, :api_key),
      "provider_name" => Keyword.get(opts, :provider_name),
      "document_prefix" => Keyword.get(opts, :document_prefix),
      "query_prefix" => Keyword.get(opts, :query_prefix)
    }
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

defmodule Threadr.TestConversationSummaryProvider do
  @behaviour Threadr.ML.Generation.Provider

  alias Threadr.ML.Generation.Result

  @impl true
  def complete(request, opts) do
    {:ok,
     %Result{
       content:
         """
         TOPIC: web-4 validation
         SUMMARY: Bob asked for web-4 to be validated, and Alice later reported the validation was complete. [M1] [M2]
         """
         |> String.trim(),
       model: Keyword.get(opts, :model, "test-llm"),
       provider: "test-conversation-summary",
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
       dialogue_act: %{
         label: "status_update",
         confidence: 0.96,
         metadata: %{"requires_follow_up" => false}
       },
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

defmodule Threadr.TestExtractionOptsProvider do
  @behaviour Threadr.ML.Extraction.Provider

  alias Threadr.ML.Extraction.Result

  @impl true
  def extract(_request, opts) do
    {:ok,
     %Result{
       dialogue_act: %{
         label: "other",
         confidence: 0.5,
         metadata: %{}
       },
       entities: [],
       facts: [],
       model: Keyword.get(opts, :model, "test-llm"),
       provider: "test-opts",
       metadata: %{
         "provider_name" => Keyword.get(opts, :provider_name),
         "endpoint" => Keyword.get(opts, :endpoint),
         "api_key" => Keyword.get(opts, :api_key),
         "system_prompt" => Keyword.get(opts, :system_prompt),
         "temperature" => Keyword.get(opts, :temperature),
         "max_tokens" => Keyword.get(opts, :max_tokens),
         "timeout" => Keyword.get(opts, :timeout),
         "generation_provider" => inspect(Keyword.get(opts, :generation_provider))
       }
     }}
  end
end

defmodule Threadr.TestTimeoutExtractionProvider do
  @behaviour Threadr.ML.Extraction.Provider

  @impl true
  def extract(_request, _opts) do
    {:error, {:generation_failed, "timeout"}}
  end
end
