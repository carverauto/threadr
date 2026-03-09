defmodule Threadr.ML.QAOrchestrator do
  @moduledoc """
  Shared routing between actor-specific QA and generic tenant QA strategies.
  """

  alias Threadr.ML.{
    ActorQA,
    ConversationQA,
    ConversationSummaryQA,
    GraphRAG,
    QARequest,
    SemanticQA
  }

  @type ensure_embeddings_fun :: (map(), QARequest.t() -> :ok | {:error, term()})

  @spec answer_question(map(), QARequest.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def answer_question(tenant, %QARequest{} = request, opts \\ [])
      when is_map(tenant) and is_list(opts) do
    ensure_embeddings = Keyword.fetch!(opts, :ensure_embeddings)
    runtime_opts = QARequest.to_runtime_opts(request)

    case ConversationQA.answer_question(tenant.subject_name, request.question, runtime_opts) do
      {:ok, result} ->
        {:ok, Map.put(result, :mode, :conversation_qa)}

      {:error, :not_conversation_question} ->
        case ActorQA.answer_question(tenant.subject_name, request.question, runtime_opts) do
          {:ok, result} ->
            {:ok, Map.put(result, :mode, :actor_qa)}

          {:error, :not_actor_question} ->
            case ConversationSummaryQA.answer_question(
                   tenant.subject_name,
                   request.question,
                   runtime_opts
                 ) do
              {:ok, result} ->
                {:ok, Map.put(result, :mode, :conversation_summary_qa)}

              {:error, :not_conversation_summary_question} ->
                fallback_answer(tenant, request, ensure_embeddings)
            end
        end
    end
  end

  defp fallback_answer(tenant, %QARequest{strategy: :bot} = request, ensure_embeddings) do
    with :ok <- ensure_embeddings.(tenant, request) do
      case GraphRAG.answer_question(tenant.subject_name, request) do
        {:ok, result} ->
          {:ok, Map.put(result, :mode, :graph_rag)}

        {:error, :generation_provider_not_configured} = error ->
          error

        {:error, _reason} ->
          answer_with_semantic_qa(tenant, request)
      end
    end
  end

  defp fallback_answer(tenant, %QARequest{strategy: :user} = request, ensure_embeddings) do
    with :ok <- ensure_embeddings.(tenant, request) do
      answer_with_semantic_qa(tenant, request)
    end
  end

  defp answer_with_semantic_qa(tenant, %QARequest{} = request) do
    case SemanticQA.answer_question(
           tenant.subject_name,
           request.question,
           QARequest.to_runtime_opts(request)
         ) do
      {:ok, result} ->
        {:ok, Map.put(result, :mode, :semantic_qa)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
