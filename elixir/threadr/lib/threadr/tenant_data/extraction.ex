defmodule Threadr.TenantData.Extraction do
  @moduledoc """
  Persists structured extraction entities and facts for tenant-scoped messages.
  """

  import Ash.Expr
  require Ash.Query

  alias Threadr.ControlPlane.Analysis
  alias Threadr.ML.{Extraction, ExtractionProviderOpts}
  alias Threadr.TenantData.{ExtractedEntity, ExtractedFact, Message}

  def extract_and_persist_message(
        %Message{} = message,
        tenant_subject_name,
        tenant_schema,
        opts \\ []
      ) do
    with {:ok, runtime_opts} <- extraction_runtime_opts(tenant_subject_name, opts),
         {:ok, result} <- Extraction.extract_message(message, tenant_subject_name, runtime_opts),
         {:ok, persisted} <- persist_result(message.id, result, tenant_schema) do
      {:ok, %{result: result, persisted: persisted}}
    end
  end

  def extract_and_persist_message_id(message_id, tenant_subject_name, tenant_schema, opts \\ []) do
    with {:ok, message} <- fetch_message(message_id, tenant_schema) do
      extract_and_persist_message(message, tenant_subject_name, tenant_schema, opts)
    end
  end

  def persist_result(message_id, result, tenant_schema) do
    with {:ok, entities} <- upsert_entities(message_id, result.entities, tenant_schema),
         {:ok, facts} <- upsert_facts(message_id, result.facts, tenant_schema) do
      {:ok, %{entities: entities, facts: facts}}
    end
  end

  def enabled? do
    Application.get_env(:threadr, Threadr.ML, [])
    |> Keyword.get(:extraction, [])
    |> Keyword.get(:enabled, false)
  end

  defp extraction_runtime_opts(tenant_subject_name, opts) do
    with {:ok, generation_opts} <-
           Analysis.generation_runtime_opts_for_tenant_subject(tenant_subject_name, opts) do
      extraction_config =
        Application.get_env(:threadr, Threadr.ML, [])
        |> Keyword.get(:extraction, [])

      {:ok,
       generation_opts
       |> ExtractionProviderOpts.from_generation_runtime()
       |> Keyword.merge(
         [
           provider: Keyword.get(extraction_config, :provider),
           provider_name: Keyword.get(extraction_config, :provider_name),
           system_prompt: Keyword.get(extraction_config, :system_prompt),
           temperature: Keyword.get(extraction_config, :temperature),
           max_tokens: Keyword.get(extraction_config, :max_tokens),
           timeout: Keyword.get(extraction_config, :timeout)
         ]
         |> Enum.reject(fn {_key, value} -> is_nil(value) end)
       )
       |> Keyword.merge(opts)}
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

  defp upsert_entities(message_id, entities, tenant_schema) do
    entities
    |> Enum.reduce_while({:ok, []}, fn entity, {:ok, persisted} ->
      case upsert_entity(message_id, entity, tenant_schema) do
        {:ok, record} -> {:cont, {:ok, [record | persisted]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, persisted} -> {:ok, Enum.reverse(persisted)}
      error -> error
    end
  end

  defp upsert_entity(message_id, entity, tenant_schema) do
    query =
      ExtractedEntity
      |> Ash.Query.filter(
        expr(
          source_message_id == ^message_id and
            entity_type == ^entity.entity_type and
            name == ^entity.name
        )
      )

    attrs = %{
      entity_type: entity.entity_type,
      name: entity.name,
      canonical_name: entity.canonical_name,
      confidence: entity.confidence,
      metadata: entity.metadata,
      source_message_id: message_id
    }

    case Ash.read_one(query, tenant: tenant_schema) do
      {:ok, nil} ->
        ExtractedEntity
        |> Ash.Changeset.for_create(:create, attrs, tenant: tenant_schema)
        |> Ash.create()

      {:ok, existing} ->
        existing
        |> Ash.Changeset.for_update(
          :update,
          Map.take(attrs, [:canonical_name, :confidence, :metadata]),
          tenant: tenant_schema
        )
        |> Ash.update()

      error ->
        error
    end
  end

  defp upsert_facts(message_id, facts, tenant_schema) do
    facts
    |> Enum.reduce_while({:ok, []}, fn fact, {:ok, persisted} ->
      case upsert_fact(message_id, fact, tenant_schema) do
        {:ok, record} -> {:cont, {:ok, [record | persisted]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, persisted} -> {:ok, Enum.reverse(persisted)}
      error -> error
    end
  end

  defp upsert_fact(message_id, fact, tenant_schema) do
    query =
      ExtractedFact
      |> Ash.Query.filter(
        expr(
          source_message_id == ^message_id and
            fact_type == ^fact.fact_type and
            subject == ^fact.subject and
            predicate == ^fact.predicate and
            object == ^fact.object
        )
      )

    attrs = %{
      fact_type: fact.fact_type,
      subject: fact.subject,
      predicate: fact.predicate,
      object: fact.object,
      confidence: fact.confidence,
      valid_at: parse_valid_at(fact.valid_at),
      metadata: fact.metadata,
      source_message_id: message_id
    }

    case Ash.read_one(query, tenant: tenant_schema) do
      {:ok, nil} ->
        ExtractedFact
        |> Ash.Changeset.for_create(:create, attrs, tenant: tenant_schema)
        |> Ash.create()

      {:ok, existing} ->
        existing
        |> Ash.Changeset.for_update(
          :update,
          Map.take(attrs, [:confidence, :valid_at, :metadata]),
          tenant: tenant_schema
        )
        |> Ash.update()

      error ->
        error
    end
  end

  defp parse_valid_at(nil), do: nil
  defp parse_valid_at(""), do: nil

  defp parse_valid_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp parse_valid_at(%DateTime{} = value), do: value
  defp parse_valid_at(%NaiveDateTime{} = value), do: value
  defp parse_valid_at(_value), do: nil
end
