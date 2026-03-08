defmodule Threadr.ML.SemanticQA do
  @moduledoc """
  Tenant-scoped semantic retrieval plus question answering over embedded messages.
  """

  import Ecto.Query
  import Pgvector.Ecto.Query

  alias Threadr.CompareDelta
  alias Threadr.ControlPlane
  alias Threadr.ML.{EmbeddingProviderOpts, Embeddings, Generation, GenerationProviderOpts}
  alias Threadr.Repo

  @default_limit 5

  def answer_question(tenant_subject_name, question, opts \\ [])
      when is_binary(tenant_subject_name) and is_binary(question) do
    with {:ok, tenant} <-
           ControlPlane.get_tenant_by_subject_name(tenant_subject_name, context: %{system: true}),
         {:ok, matches, query_result} <-
           search_messages_in_schema(tenant.schema_name, question, opts),
         citations = build_citations(matches, tenant.schema_name),
         facts_over_time = facts_over_time(citations),
         {:ok, generation_result} <-
           Generation.answer_question(question, build_context(citations), generation_opts(opts)) do
      {:ok,
       %{
         tenant_subject_name: tenant.subject_name,
         tenant_schema: tenant.schema_name,
         question: question,
         query: query_result,
         matches: matches,
         citations: citations,
         facts_over_time: facts_over_time,
         context: build_context(citations),
         answer: generation_result
       }}
    end
  end

  def search_messages(tenant_subject_name, question, opts \\ [])
      when is_binary(tenant_subject_name) and is_binary(question) do
    with {:ok, tenant} <-
           ControlPlane.get_tenant_by_subject_name(tenant_subject_name, context: %{system: true}),
         {:ok, matches, query_result} <-
           search_messages_in_schema(tenant.schema_name, question, opts),
         citations = build_citations(matches, tenant.schema_name) do
      {:ok,
       %{
         tenant_subject_name: tenant.subject_name,
         tenant_schema: tenant.schema_name,
         question: question,
         query: query_result,
         matches: matches,
         citations: citations,
         facts_over_time: facts_over_time(citations),
         context: build_context(citations)
       }}
    end
  end

  def compare_windows(
        tenant_subject_name,
        question,
        baseline_window,
        comparison_window,
        opts \\ []
      )
      when is_binary(tenant_subject_name) and is_binary(question) and is_map(baseline_window) and
             is_map(comparison_window) do
    with {:ok, tenant} <-
           ControlPlane.get_tenant_by_subject_name(tenant_subject_name, context: %{system: true}),
         {:ok, baseline} <-
           search_messages(
             tenant.subject_name,
             question,
             Keyword.merge(opts,
               since: Map.get(baseline_window, :since),
               until: Map.get(baseline_window, :until)
             )
           ),
         {:ok, comparison} <-
           search_messages(
             tenant.subject_name,
             question,
             Keyword.merge(opts,
               since: Map.get(comparison_window, :since),
               until: Map.get(comparison_window, :until)
             )
           ),
         {:ok, generation_result} <-
           Generation.complete(
             build_comparison_prompt(
               question,
               baseline,
               comparison,
               baseline_window,
               comparison_window
             ),
             generation_opts(opts)
           ),
         delta <-
           CompareDelta.build(
             baseline_entities(baseline),
             baseline_entities(comparison),
             baseline_facts(baseline),
             baseline_facts(comparison)
           ) do
      {:ok,
       %{
         tenant_subject_name: tenant.subject_name,
         tenant_schema: tenant.schema_name,
         question: question,
         baseline: baseline,
         comparison: comparison,
         entity_delta: delta.entity_delta,
         fact_delta: delta.fact_delta,
         context:
           build_comparison_context(baseline, comparison, baseline_window, comparison_window),
         answer: generation_result
       }}
    end
  end

  def build_context(citations) when is_list(citations) do
    citations
    |> Enum.map(fn citation ->
      timestamp =
        case citation.observed_at do
          %DateTime{} = observed_at -> DateTime.to_iso8601(observed_at)
          value -> to_string(value)
        end

      "[#{citation.label}] [#{timestamp}] ##{citation.channel_name} #{citation.actor_handle}: #{citation.body}"
      |> append_entities(citation)
      |> append_facts(citation)
    end)
    |> Enum.join("\n\n")
  end

  defp build_comparison_prompt(question, baseline, comparison, baseline_window, comparison_window) do
    """
    Question:
    #{question}

    Baseline Window:
    #{window_label(baseline_window)}
    #{baseline.context}

    Comparison Window:
    #{window_label(comparison_window)}
    #{comparison.context}

    Explain what changed between the baseline and comparison windows using only this context.
    """
  end

  defp build_comparison_context(baseline, comparison, baseline_window, comparison_window) do
    """
    Baseline Window:
    #{window_label(baseline_window)}
    #{baseline.context}

    Comparison Window:
    #{window_label(comparison_window)}
    #{comparison.context}
    """
  end

  defp baseline_entities(result) do
    result
    |> Map.get(:citations, [])
    |> Enum.flat_map(&Map.get(&1, :extracted_entities, []))
  end

  defp baseline_facts(result) do
    result
    |> Map.get(:citations, [])
    |> Enum.flat_map(&Map.get(&1, :extracted_facts, []))
  end

  defp window_label(window) do
    "#{format_window_value(Map.get(window, :since))} -> #{format_window_value(Map.get(window, :until))}"
  end

  defp format_window_value(nil), do: "open"
  defp format_window_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp format_window_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp format_window_value(value), do: to_string(value)

  defp search_messages_in_schema(tenant_schema, question, opts) do
    with {:ok, query_embedding} <- Embeddings.embed_query(question, embedding_opts(opts)) do
      {:ok, query_vector} = Ash.Vector.new(query_embedding.embedding)
      model = Keyword.get(opts, :embedding_model, default_embedding_model())
      limit = Keyword.get(opts, :limit, @default_limit)

      matches =
        from(me in "message_embeddings",
          join: m in "messages",
          on: m.id == me.message_id,
          join: a in "actors",
          on: a.id == m.actor_id,
          join: c in "channels",
          on: c.id == m.channel_id,
          where: me.model == ^model,
          order_by: cosine_distance(me.embedding, ^query_vector),
          limit: ^limit,
          select: %{
            message_id: m.id,
            external_id: m.external_id,
            body: m.body,
            observed_at: m.observed_at,
            actor_handle: a.handle,
            actor_display_name: a.display_name,
            channel_name: c.name,
            model: me.model,
            distance: cosine_distance(me.embedding, ^query_vector)
          }
        )
        |> Repo.all(prefix: tenant_schema)
        |> Enum.map(&normalize_match/1)
        |> maybe_filter_since(Keyword.get(opts, :since))
        |> maybe_filter_until(Keyword.get(opts, :until))

      case matches do
        [] ->
          {:error, :no_message_embeddings}

        _ ->
          {:ok, matches,
           %{
             model: model,
             provider: query_embedding.provider,
             metadata: Map.get(query_embedding, :metadata, %{})
           }}
      end
    end
  end

  defp normalize_match(match) do
    distance = normalize_distance(match.distance)

    match
    |> Map.update!(:message_id, &normalize_identifier/1)
    |> Map.update!(:external_id, &normalize_identifier/1)
    |> Map.put(:distance, distance)
    |> Map.put(:similarity, 1.0 - distance)
  end

  defp build_citations(matches, tenant_schema) do
    entities_by_message =
      fetch_entities_by_message(tenant_schema, Enum.map(matches, & &1.message_id))

    facts_by_message = fetch_facts_by_message(tenant_schema, Enum.map(matches, & &1.message_id))

    matches
    |> Enum.with_index(1)
    |> Enum.map(fn {match, index} ->
      %{
        label: "C#{index}",
        rank: index,
        message_id: match.message_id,
        external_id: match.external_id,
        body: match.body,
        observed_at: match.observed_at,
        actor_handle: match.actor_handle,
        actor_display_name: match.actor_display_name,
        channel_name: match.channel_name,
        similarity: match.similarity,
        extracted_entities: Map.get(entities_by_message, match.message_id, []),
        extracted_facts: Map.get(facts_by_message, match.message_id, [])
      }
    end)
  end

  defp fetch_entities_by_message(_tenant_schema, []), do: %{}

  defp fetch_entities_by_message(tenant_schema, message_ids) do
    dumped_ids = Enum.map(message_ids, &dump_uuid!/1)

    query =
      from(e in "extracted_entities",
        where: e.source_message_id in ^dumped_ids,
        order_by: [desc: e.confidence, asc: e.name],
        select: %{
          source_message_id: e.source_message_id,
          entity_type: e.entity_type,
          name: e.name,
          canonical_name: e.canonical_name,
          confidence: e.confidence
        }
      )

    safe_extraction_query(query, tenant_schema)
  end

  defp fetch_facts_by_message(_tenant_schema, []), do: %{}

  defp fetch_facts_by_message(tenant_schema, message_ids) do
    dumped_ids = Enum.map(message_ids, &dump_uuid!/1)

    query =
      from(f in "extracted_facts",
        where: f.source_message_id in ^dumped_ids,
        order_by: [desc: f.confidence, asc: f.fact_type],
        select: %{
          source_message_id: f.source_message_id,
          fact_type: f.fact_type,
          subject: f.subject,
          predicate: f.predicate,
          object: f.object,
          confidence: f.confidence,
          valid_at: f.valid_at
        }
      )

    safe_extraction_query(query, tenant_schema)
  end

  defp safe_extraction_query(query, tenant_schema) do
    query
    |> Repo.all(prefix: tenant_schema)
    |> Enum.map(&normalize_extracted_map/1)
    |> Enum.group_by(& &1.source_message_id)
  rescue
    error in Postgrex.Error ->
      if missing_extraction_table?(error) do
        %{}
      else
        reraise error, __STACKTRACE__
      end
  end

  defp missing_extraction_table?(%Postgrex.Error{postgres: %{code: :undefined_table}}), do: true
  defp missing_extraction_table?(%Postgrex.Error{postgres: %{code: "42P01"}}), do: true
  defp missing_extraction_table?(_error), do: false

  defp normalize_distance(%Decimal{} = distance), do: Decimal.to_float(distance)
  defp normalize_distance(distance) when is_float(distance), do: distance
  defp normalize_distance(distance) when is_integer(distance), do: distance / 1

  defp normalize_identifier(nil), do: nil

  defp normalize_identifier(value) when is_binary(value) do
    if String.valid?(value) do
      value
    else
      case Ecto.UUID.load(value) do
        {:ok, uuid} -> uuid
        :error -> Base.encode16(value, case: :lower)
      end
    end
  end

  defp normalize_identifier(value), do: to_string(value)

  defp normalize_extracted_map(map) do
    map
    |> Enum.map(fn
      {:valid_at, %DateTime{} = value} -> {:valid_at, DateTime.to_iso8601(value)}
      {:valid_at, %NaiveDateTime{} = value} -> {:valid_at, NaiveDateTime.to_iso8601(value)}
      {key, value} -> {key, normalize_identifier(value)}
    end)
    |> Map.new()
  end

  defp dump_uuid!(value) when is_binary(value), do: Ecto.UUID.dump!(value)
  defp dump_uuid!(value), do: value

  defp append_entities(line, %{extracted_entities: []}), do: line

  defp append_entities(line, %{extracted_entities: entities}) do
    suffix =
      entities
      |> Enum.map(fn entity ->
        "#{entity.entity_type}=#{entity.canonical_name || entity.name}"
      end)
      |> Enum.join(", ")

    line <> "\nEntities: " <> suffix
  end

  defp append_facts(line, %{extracted_facts: []}), do: line

  defp append_facts(line, %{extracted_facts: facts}) do
    suffix =
      facts
      |> Enum.map(fn fact ->
        base = "#{fact.subject} #{fact.predicate} #{fact.object}"

        case fact.valid_at do
          nil -> base
          value -> base <> " @ " <> value
        end
      end)
      |> Enum.join(" | ")

    line <> "\nFacts: " <> suffix
  end

  defp default_embedding_model do
    Application.get_env(:threadr, Threadr.ML, [])
    |> Keyword.fetch!(:embeddings)
    |> Keyword.fetch!(:model)
  end

  defp embedding_opts(opts) do
    EmbeddingProviderOpts.from_prefixed(opts)
  end

  defp generation_opts(opts) do
    GenerationProviderOpts.from_prefixed(opts)
  end

  defp maybe_filter_since(matches, nil), do: matches

  defp maybe_filter_since(matches, %NaiveDateTime{} = since) do
    Enum.filter(matches, &compare_observed_at(&1.observed_at, since, :gte))
  end

  defp maybe_filter_since(matches, %DateTime{} = since) do
    Enum.filter(matches, &compare_observed_at(&1.observed_at, since, :gte))
  end

  defp maybe_filter_until(matches, nil), do: matches

  defp maybe_filter_until(matches, %NaiveDateTime{} = until) do
    Enum.filter(matches, &compare_observed_at(&1.observed_at, until, :lte))
  end

  defp maybe_filter_until(matches, %DateTime{} = until) do
    Enum.filter(matches, &compare_observed_at(&1.observed_at, until, :lte))
  end

  defp compare_observed_at(%DateTime{} = observed_at, %DateTime{} = value, :gte),
    do: DateTime.compare(observed_at, value) in [:gt, :eq]

  defp compare_observed_at(%DateTime{} = observed_at, %DateTime{} = value, :lte),
    do: DateTime.compare(observed_at, value) in [:lt, :eq]

  defp compare_observed_at(%NaiveDateTime{} = observed_at, %NaiveDateTime{} = value, :gte),
    do: NaiveDateTime.compare(observed_at, value) in [:gt, :eq]

  defp compare_observed_at(%NaiveDateTime{} = observed_at, %NaiveDateTime{} = value, :lte),
    do: NaiveDateTime.compare(observed_at, value) in [:lt, :eq]

  defp compare_observed_at(%DateTime{} = observed_at, %NaiveDateTime{} = value, op),
    do: compare_observed_at(observed_at, DateTime.from_naive!(value, "Etc/UTC"), op)

  defp compare_observed_at(%NaiveDateTime{} = observed_at, %DateTime{} = value, op),
    do: compare_observed_at(DateTime.from_naive!(observed_at, "Etc/UTC"), value, op)

  defp compare_observed_at(_observed_at, _value, _op), do: false

  defp facts_over_time(citations) do
    citations
    |> Enum.flat_map(fn citation ->
      observed_at = citation.observed_at

      Enum.map(Map.get(citation, :extracted_facts, []), fn fact ->
        %{
          day: fact_day(fact, observed_at),
          fact_type: fact[:fact_type],
          subject: fact[:subject],
          predicate: fact[:predicate],
          object: fact[:object]
        }
      end)
    end)
    |> Enum.group_by(& &1.day)
    |> Enum.map(fn {day, facts} ->
      {{subject, predicate, object}, grouped} =
        facts
        |> Enum.group_by(fn fact -> {fact.subject, fact.predicate, fact.object} end)
        |> Enum.max_by(fn {_key, rows} -> length(rows) end, fn -> {{"", "", ""}, []} end)

      %{
        day: Date.to_iso8601(day),
        fact_count: length(facts),
        fact_type_count: facts |> Enum.map(& &1.fact_type) |> Enum.uniq() |> length(),
        top_fact: Enum.join(Enum.reject([subject, predicate, object], &(&1 in [nil, ""])), " "),
        top_fact_count: length(grouped)
      }
    end)
    |> Enum.sort_by(& &1.day, :desc)
  end

  defp fact_day(%{valid_at: valid_at}, observed_at) when is_binary(valid_at) do
    case Date.from_iso8601(String.slice(valid_at, 0, 10)) do
      {:ok, date} -> date
      _ -> observed_day(observed_at)
    end
  end

  defp fact_day(_fact, observed_at), do: observed_day(observed_at)

  defp observed_day(%DateTime{} = observed_at), do: DateTime.to_date(observed_at)
  defp observed_day(%NaiveDateTime{} = observed_at), do: NaiveDateTime.to_date(observed_at)
  defp observed_day(_value), do: ~D[1970-01-01]
end
