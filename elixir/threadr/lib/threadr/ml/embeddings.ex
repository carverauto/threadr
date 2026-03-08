defmodule Threadr.ML.Embeddings do
  @moduledoc """
  Local embedding generation and publication for tenant-scoped messages.
  """

  import Ash.Expr
  require Ash.Query

  alias Threadr.Events
  alias Threadr.ML.EmbeddingProviderOpts
  alias Threadr.TenantData.Message

  def embed_query(text, opts \\ []) when is_binary(text) do
    provider = Keyword.get(opts, :provider, provider())
    provider.embed_query(text, provider_opts(opts))
  end

  def generate_for_message(%Message{} = message, tenant_subject_name, opts \\ []) do
    provider = Keyword.get(opts, :provider, provider())

    with {:ok, embedding_result} <- provider.embed_document(message.body, provider_opts(opts)),
         envelope <- build_processing_result(message, tenant_subject_name, embedding_result),
         :ok <- publish(envelope, opts) do
      {:ok, envelope}
    end
  end

  def generate_for_message_id(message_id, tenant_subject_name, tenant_schema, opts \\ []) do
    with {:ok, message} <- fetch_message(message_id, tenant_schema) do
      generate_for_message(message, tenant_subject_name, opts)
    end
  end

  defp fetch_message(message_id, tenant_schema) do
    query =
      Message
      |> Ash.Query.filter(expr(id == ^message_id or external_id == ^message_id))

    case Ash.read_one(query, tenant: tenant_schema) do
      {:ok, nil} -> {:error, {:message_not_found, message_id}}
      result -> result
    end
  end

  defp build_processing_result(message, tenant_subject_name, embedding_result) do
    Events.build_processing_result(
      %{
        pipeline: "embeddings",
        status: "completed",
        completed_at: DateTime.utc_now(),
        message_id: message.external_id || message.id,
        payload: %{
          "model" => embedding_result.model,
          "provider" => embedding_result.provider,
          "embedding" => embedding_result.embedding
        },
        metrics: Map.get(embedding_result, :metadata, %{})
      },
      tenant_subject_name
    )
  end

  defp publish(envelope, opts) do
    case Keyword.get(opts, :publisher, Threadr.Messaging.Publisher) do
      {module, arg} -> module.publish(envelope, arg)
      module -> module.publish(envelope)
    end
  end

  defp provider do
    Application.get_env(:threadr, Threadr.ML, [])
    |> Keyword.fetch!(:embeddings)
    |> Keyword.fetch!(:provider)
  end

  defp provider_opts(opts) do
    EmbeddingProviderOpts.from_direct(opts)
  end
end
