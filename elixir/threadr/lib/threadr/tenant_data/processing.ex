defmodule Threadr.TenantData.Processing do
  @moduledoc """
  Persists tenant-scoped processing results into Ash resources.
  """

  import Ash.Expr
  require Ash.Query

  alias Threadr.Events.{Envelope, ProcessingResult}
  alias Threadr.Messaging.Topology
  alias Threadr.TenantData.{Message, MessageEmbedding}

  def persist_envelope(
        %Envelope{type: "processing.result", data: %ProcessingResult{} = result} = envelope
      ) do
    with {:ok, tenant_subject_name} <- Topology.tenant_subject_name_from_subject(envelope.subject),
         {:ok, tenant} <-
           Threadr.ControlPlane.get_tenant_by_subject_name(
             tenant_subject_name,
             context: %{system: true}
           ),
         {:ok, persisted_result} <-
           persist_processing_result(result, envelope, tenant.schema_name) do
      {:ok, persisted_result}
    end
  end

  def persist_envelope(%Envelope{type: type}) do
    {:error, {:unsupported_envelope_type, type}}
  end

  def persist_processing_result(
        %ProcessingResult{pipeline: "embeddings", status: "completed"} = result,
        %Envelope{} = envelope,
        tenant_schema
      ) do
    with {:ok, message} <- fetch_message(result.message_id, tenant_schema),
         {:ok, embedding} <- upsert_embedding(message.id, result, envelope, tenant_schema) do
      {:ok, embedding}
    end
  end

  def persist_processing_result(%ProcessingResult{} = result, _envelope, _tenant_schema) do
    {:error, {:unsupported_processing_result, result.pipeline, result.status}}
  end

  defp fetch_message(nil, _tenant_schema), do: {:error, :missing_message_id}

  defp fetch_message(message_id, tenant_schema) when is_binary(message_id) do
    query =
      Message
      |> Ash.Query.filter(expr(external_id == ^message_id))

    case Ash.read_one(query, tenant: tenant_schema) do
      {:ok, nil} -> fetch_message_by_uuid(message_id, tenant_schema)
      {:ok, message} -> {:ok, message}
      error -> error
    end
  end

  defp fetch_message_by_uuid(message_id, tenant_schema) do
    case Ecto.UUID.cast(message_id) do
      {:ok, uuid} ->
        query =
          Message
          |> Ash.Query.filter(expr(id == ^uuid))

        case Ash.read_one(query, tenant: tenant_schema) do
          {:ok, nil} -> {:error, {:message_not_found, message_id}}
          result -> result
        end

      :error ->
        {:error, {:message_not_found, message_id}}
    end
  end

  defp upsert_embedding(message_id, result, envelope, tenant_schema) do
    with {:ok, model} <- fetch_required(result.payload, "model"),
         {:ok, embedding} <- fetch_embedding(result.payload) do
      attrs = %{
        model: model,
        dimensions: length(embedding),
        embedding: embedding,
        metadata: embedding_metadata(result, envelope),
        message_id: message_id
      }

      query =
        MessageEmbedding
        |> Ash.Query.filter(expr(message_id == ^message_id and model == ^model))

      case Ash.read_one(query, tenant: tenant_schema) do
        {:ok, nil} ->
          MessageEmbedding
          |> Ash.Changeset.for_create(:create, attrs, tenant: tenant_schema)
          |> Ash.create()

        {:ok, message_embedding} ->
          message_embedding
          |> Ash.Changeset.for_update(
            :update,
            Map.take(attrs, [:dimensions, :embedding, :metadata]),
            tenant: tenant_schema
          )
          |> Ash.update()

        error ->
          error
      end
    end
  end

  defp embedding_metadata(result, envelope) do
    %{
      "pipeline" => result.pipeline,
      "status" => result.status,
      "completed_at" => DateTime.to_iso8601(result.completed_at),
      "metrics" => stringify_map(result.metrics),
      "payload" => result.payload |> stringify_map() |> Map.drop(["embedding"]),
      "source" => envelope.source,
      "subject" => envelope.subject
    }
  end

  defp fetch_embedding(payload) do
    case Map.get(payload, "embedding") || Map.get(payload, :embedding) do
      embedding when is_list(embedding) -> {:ok, embedding}
      _ -> {:error, :missing_embedding}
    end
  end

  defp fetch_required(payload, key) do
    atom_key =
      try do
        String.to_existing_atom(key)
      rescue
        ArgumentError -> nil
      end

    case Map.get(payload, key) || (atom_key && Map.get(payload, atom_key)) do
      value when is_binary(value) -> {:ok, value}
      _ -> {:error, {:missing_payload_key, key}}
    end
  end

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
