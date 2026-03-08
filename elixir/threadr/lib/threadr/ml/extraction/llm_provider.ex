defmodule Threadr.ML.Extraction.LlmProvider do
  @moduledoc """
  Structured extraction provider backed by the configured generation provider.
  """

  @behaviour Threadr.ML.Extraction.Provider

  alias Threadr.ML.Extraction.{Request, Result}
  alias Threadr.ML.Generation

  @default_system_prompt """
  Extract structured intelligence from the provided chat message.
  Return strict JSON with this shape:
  {
    "entities": [
      {
        "entity_type": "person|channel|topic|system|organization|artifact|time_reference|other",
        "name": "string",
        "canonical_name": "string or null",
        "confidence": 0.0,
        "metadata": {}
      }
    ],
    "facts": [
      {
        "fact_type": "claim|interaction|topic_discussion|time_reference|status_update|access_statement|other",
        "subject": "string",
        "predicate": "string",
        "object": "string",
        "confidence": 0.0,
        "valid_at": "ISO8601 string or null",
        "metadata": {}
      }
    ]
  }
  Rules:
  - Only include facts grounded in the message text.
  - Preserve temporal references when present.
  - Keep names verbatim where possible.
  - Return JSON only, with no markdown fences.
  """

  @impl true
  def extract(%Request{} = request, opts) do
    with {:ok, generation_result} <-
           Generation.complete(build_prompt(request), generation_opts(opts, request)),
         {:ok, payload} <- parse_payload(generation_result.content) do
      {:ok,
       %Result{
         entities: normalize_entities(Map.get(payload, "entities", [])),
         facts: normalize_facts(Map.get(payload, "facts", [])),
         model: generation_result.model,
         provider: generation_result.provider,
         metadata: generation_result.metadata
       }}
    end
  end

  defp build_prompt(%Request{} = request) do
    observed_at =
      case request.observed_at do
        %DateTime{} = value -> DateTime.to_iso8601(value)
        %NaiveDateTime{} = value -> NaiveDateTime.to_iso8601(value)
        nil -> "unknown"
        value -> to_string(value)
      end

    """
    Tenant subject: #{request.tenant_subject_name}
    Message id: #{request.message_id}
    Observed at: #{observed_at}

    Message:
    #{request.body}
    """
  end

  defp generation_opts(opts, request) do
    provider =
      Keyword.get(
        opts,
        :generation_provider,
        Application.get_env(:threadr, Threadr.ML, [])
        |> Keyword.fetch!(:generation)
        |> Keyword.fetch!(:provider)
      )

    [
      provider: provider,
      provider_name: Keyword.get(opts, :provider_name),
      endpoint: Keyword.get(opts, :endpoint),
      model: Keyword.get(opts, :model),
      api_key: Keyword.get(opts, :api_key),
      system_prompt: Keyword.get(opts, :system_prompt, @default_system_prompt),
      temperature: Keyword.get(opts, :temperature, 0.0),
      max_tokens: Keyword.get(opts, :max_tokens, 600),
      timeout: Keyword.get(opts, :timeout)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Keyword.put(:mode, :extraction)
    |> Keyword.put(:context, %{
      "tenant_subject_name" => request.tenant_subject_name,
      "message_id" => request.message_id
    })
  end

  defp parse_payload(content) when is_binary(content) do
    content
    |> strip_code_fences()
    |> Jason.decode()
    |> case do
      {:ok, payload} when is_map(payload) -> {:ok, payload}
      {:ok, payload} -> {:error, {:unexpected_extraction_payload, payload}}
      {:error, reason} -> {:error, {:invalid_extraction_json, reason, content}}
    end
  end

  defp strip_code_fences(content) do
    content
    |> String.trim()
    |> String.trim_leading("```json")
    |> String.trim_leading("```")
    |> String.trim_trailing("```")
    |> String.trim()
  end

  defp normalize_entities(entities) when is_list(entities) do
    entities
    |> Enum.map(&normalize_entity/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_entities(_entities), do: []

  defp normalize_entity(entity) when is_map(entity) do
    name = fetch(entity, "name")
    entity_type = fetch(entity, "entity_type")

    if is_binary(name) and String.trim(name) != "" and is_binary(entity_type) and
         String.trim(entity_type) != "" do
      %{
        entity_type: entity_type,
        name: name,
        canonical_name: blank_to_nil(fetch(entity, "canonical_name")),
        confidence: normalize_confidence(fetch(entity, "confidence")),
        metadata: normalize_map(fetch(entity, "metadata"))
      }
    end
  end

  defp normalize_entity(_entity), do: nil

  defp normalize_facts(facts) when is_list(facts) do
    facts
    |> Enum.map(&normalize_fact/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_facts(_facts), do: []

  defp normalize_fact(fact) when is_map(fact) do
    fact_type = fetch(fact, "fact_type")
    subject = fetch(fact, "subject")
    predicate = fetch(fact, "predicate")
    object = fetch(fact, "object")

    if Enum.all?(
         [fact_type, subject, predicate, object],
         &(is_binary(&1) and String.trim(&1) != "")
       ) do
      %{
        fact_type: fact_type,
        subject: subject,
        predicate: predicate,
        object: object,
        confidence: normalize_confidence(fetch(fact, "confidence")),
        valid_at: blank_to_nil(fetch(fact, "valid_at")),
        metadata: normalize_map(fetch(fact, "metadata"))
      }
    end
  end

  defp normalize_fact(_fact), do: nil

  defp fetch(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, String.to_atom(key))

  defp normalize_confidence(nil), do: 0.5
  defp normalize_confidence(value) when is_float(value), do: clamp_confidence(value)
  defp normalize_confidence(value) when is_integer(value), do: clamp_confidence(value / 1)

  defp normalize_confidence(value) when is_binary(value) do
    case Float.parse(value) do
      {parsed, _} -> clamp_confidence(parsed)
      :error -> 0.5
    end
  end

  defp normalize_confidence(_value), do: 0.5

  defp clamp_confidence(value), do: value |> min(1.0) |> max(0.0)

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: value)

  defp blank_to_nil(value), do: to_string(value)
end
