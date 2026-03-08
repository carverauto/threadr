defmodule Threadr.ML.ActorQA do
  @moduledoc """
  Actor-centric QA for questions about what a known actor talks about, says about
  another actor, or what the tenant history knows about that actor.
  """

  import Ecto.Query

  alias Threadr.ControlPlane
  alias Threadr.ML.{Generation, QAIntent, SemanticQA}
  alias Threadr.ML.Generation.Result
  alias Threadr.Repo

  @default_limit 8
  @minimum_actor_messages 3
  @minimum_actor_profile_messages 3
  @minimum_targeted_messages 1

  @type intent :: QAIntent.t()

  def answer_question(tenant_subject_name, question, opts \\ [])
      when is_binary(tenant_subject_name) and is_binary(question) do
    with {:ok, tenant} <-
           ControlPlane.get_tenant_by_subject_name(tenant_subject_name, context: %{system: true}),
         {:ok, intent} <- QAIntent.classify(question) do
      build_answer(tenant, question, intent, opts)
    end
  end

  defp build_answer(tenant, question, intent, opts) do
    case resolve_actor_reference(tenant.schema_name, intent.actor_ref, opts) do
      {:ok, actor} ->
        build_answer_with_actor(tenant, question, intent, actor, opts)

      {:error, {:actor_not_found, actor_ref}} ->
        {:ok, actor_not_found_result(tenant, question, intent, actor_ref)}

      {:error, {:ambiguous_actor, actor_ref, matches}} ->
        {:ok, ambiguous_actor_result(tenant, question, intent, actor_ref, matches)}
    end
  end

  defp build_answer_with_actor(tenant, question, intent, actor, opts) do
    case resolve_target_actor(tenant.schema_name, intent, opts) do
      {:ok, target_actor} ->
        do_build_answer_with_actors(tenant, question, intent, actor, target_actor, opts)

      {:error, {:actor_not_found, actor_ref}} ->
        {:ok, actor_not_found_result(tenant, question, intent, actor_ref)}

      {:error, {:ambiguous_actor, actor_ref, matches}} ->
        {:ok, ambiguous_actor_result(tenant, question, intent, actor_ref, matches)}
    end
  end

  defp do_build_answer_with_actors(tenant, question, intent, actor, target_actor, opts) do
    limit = actor_limit(opts)
    actor_stats = actor_message_stats(tenant.schema_name, actor)

    {matches, query_metadata, stats} =
      case intent.kind do
        :talks_about ->
          actor_messages = fetch_actor_messages(tenant.schema_name, actor, limit, opts)

          {actor_messages,
           %{
             retrieval: "actor_messages",
             actor_message_count: actor_stats.message_count,
             actor_mention_count: 0
           }, actor_stats}

        :knows_about ->
          actor_messages = fetch_actor_messages(tenant.schema_name, actor, limit, opts)
          mention_matches = fetch_mentions_about_actor(tenant.schema_name, actor, limit, opts)

          {combine_matches(actor_messages, mention_matches, limit),
           %{
             retrieval: "actor_messages_plus_mentions",
             actor_message_count: actor_stats.message_count,
             actor_mention_count: mention_message_count(tenant.schema_name, actor, opts)
           }, actor_stats}

        :says_about ->
          targeted_matches =
            fetch_actor_messages_about_actor(
              tenant.schema_name,
              actor,
              target_actor,
              limit,
              opts
            )

          {targeted_matches,
           %{
             retrieval: "actor_messages_about_target",
             actor_message_count: actor_stats.message_count,
             actor_mention_count: length(targeted_matches)
           }, actor_stats}
      end

    if sufficient_evidence?(intent.kind, stats, matches) do
      citations = build_citations(matches, tenant.schema_name)

      context =
        build_actor_context(
          question,
          intent,
          actor,
          target_actor,
          stats,
          query_metadata,
          citations
        )

      with {:ok, answer} <- Generation.answer_question(question, context, generation_opts(opts)) do
        {:ok,
         %{
           tenant_subject_name: tenant.subject_name,
           tenant_schema: tenant.schema_name,
           question: question,
           query:
             query_metadata
             |> Map.put(:kind, intent.kind)
             |> Map.put(:actor_handle, actor.handle)
             |> maybe_put_target_handle(target_actor)
             |> Map.put(:mode, "actor_qa")
             |> Map.put(:evidence_count, length(matches)),
           matches: matches,
           citations: citations,
           facts_over_time: facts_over_time(citations),
           context: context,
           answer: answer
         }}
      end
    else
      {:ok,
       insufficient_evidence_result(tenant, question, intent, actor, target_actor, stats, matches)}
    end
  end

  defp resolve_target_actor(_tenant_schema, %{target_ref: nil}, _opts), do: {:ok, nil}

  defp resolve_target_actor(tenant_schema, %{target_ref: target_ref}, opts) do
    resolve_actor_reference(tenant_schema, target_ref, opts)
  end

  defp resolve_actor_reference(tenant_schema, raw_ref, opts) do
    refs = actor_reference_candidates(raw_ref, opts)

    Enum.reduce_while(refs, {:error, {:actor_not_found, normalize_actor_ref(raw_ref)}}, fn ref,
                                                                                           _acc ->
      case lookup_actor_reference(tenant_schema, ref) do
        {:ok, _actor} = result -> {:halt, result}
        {:error, {:ambiguous_actor, _, _}} = result -> {:halt, result}
        {:error, {:actor_not_found, _}} -> {:cont, {:error, {:actor_not_found, ref}}}
      end
    end)
  end

  defp lookup_actor_reference(tenant_schema, ref) do
    handle_matches =
      from(a in "actors",
        where: fragment("lower(?) = lower(?)", a.handle, ^ref),
        select: %{
          id: a.id,
          handle: a.handle,
          display_name: a.display_name,
          external_id: a.external_id,
          platform: a.platform
        }
      )
      |> Repo.all(prefix: tenant_schema)

    case uniq_actor_matches(handle_matches) do
      [actor] ->
        {:ok, actor}

      [_ | _] = matches ->
        {:error, {:ambiguous_actor, ref, matches}}

      [] ->
        external_matches =
          from(a in "actors",
            where: a.external_id == ^discord_or_plain_external_id(ref),
            select: %{
              id: a.id,
              handle: a.handle,
              display_name: a.display_name,
              external_id: a.external_id,
              platform: a.platform
            }
          )
          |> Repo.all(prefix: tenant_schema)

        case uniq_actor_matches(external_matches) do
          [actor] ->
            {:ok, actor}

          [_ | _] = matches ->
            {:error, {:ambiguous_actor, ref, matches}}

          [] ->
            display_matches =
              from(a in "actors",
                where: not is_nil(a.display_name),
                where: fragment("lower(?) = lower(?)", a.display_name, ^ref),
                select: %{
                  id: a.id,
                  handle: a.handle,
                  display_name: a.display_name,
                  external_id: a.external_id,
                  platform: a.platform
                }
              )
              |> Repo.all(prefix: tenant_schema)

            case uniq_actor_matches(display_matches) do
              [actor] -> {:ok, actor}
              [_ | _] = matches -> {:error, {:ambiguous_actor, ref, matches}}
              [] -> {:error, {:actor_not_found, ref}}
            end
        end
    end
  end

  defp actor_message_stats(tenant_schema, actor) do
    dumped_actor_id = dump_uuid!(actor.id)

    from(m in "messages",
      where: m.actor_id == ^dumped_actor_id,
      select: %{
        message_count: count(m.id),
        channel_count: count(m.channel_id, :distinct),
        first_observed_at: min(m.observed_at),
        last_observed_at: max(m.observed_at)
      }
    )
    |> Repo.one(prefix: tenant_schema)
    |> Map.put_new(:message_count, 0)
    |> Map.put_new(:channel_count, 0)
  end

  defp mention_message_count(tenant_schema, actor, opts) do
    dumped_actor_id = dump_uuid!(actor.id)
    mention_patterns = actor_body_patterns(actor)

    base_query =
      from(m in "messages",
        left_join: mm in "message_mentions",
        on: mm.message_id == m.id and mm.actor_id == ^dumped_actor_id,
        where: m.actor_id != ^dumped_actor_id
      )
      |> apply_time_bounds(opts)

    mention_dynamic = actor_reference_dynamic_for_count(mention_patterns)

    from([m, mm] in base_query,
      where: ^dynamic([m, mm], not is_nil(mm.id) or ^mention_dynamic),
      select: count(m.id)
    )
    |> Repo.one(prefix: tenant_schema)
    |> Kernel.||(0)
  end

  defp fetch_actor_messages(tenant_schema, actor, limit, opts) do
    dumped_actor_id = dump_uuid!(actor.id)

    from(m in "messages",
      join: a in "actors",
      on: a.id == m.actor_id,
      join: c in "channels",
      on: c.id == m.channel_id,
      where: m.actor_id == ^dumped_actor_id,
      order_by: [desc: m.observed_at],
      limit: ^limit,
      select: %{
        message_id: m.id,
        external_id: m.external_id,
        body: m.body,
        observed_at: m.observed_at,
        actor_handle: a.handle,
        actor_display_name: a.display_name,
        channel_name: c.name,
        model: "actor-centric",
        distance: nil,
        similarity: 1.0,
        evidence_type: "actor_message"
      }
    )
    |> apply_time_bounds(opts)
    |> Repo.all(prefix: tenant_schema)
    |> Enum.map(&normalize_match/1)
  end

  defp fetch_mentions_about_actor(tenant_schema, actor, limit, opts) do
    dumped_actor_id = dump_uuid!(actor.id)
    mention_patterns = actor_body_patterns(actor)
    mention_dynamic = actor_reference_dynamic_for_joined_query(mention_patterns)

    from(m in "messages",
      join: a in "actors",
      on: a.id == m.actor_id,
      join: c in "channels",
      on: c.id == m.channel_id,
      left_join: mm in "message_mentions",
      on: mm.message_id == m.id and mm.actor_id == ^dumped_actor_id,
      where: m.actor_id != ^dumped_actor_id,
      where: ^dynamic([m, a, c, mm], not is_nil(mm.id) or ^mention_dynamic),
      order_by: [desc: m.observed_at],
      limit: ^limit,
      select: %{
        message_id: m.id,
        external_id: m.external_id,
        body: m.body,
        observed_at: m.observed_at,
        actor_handle: a.handle,
        actor_display_name: a.display_name,
        channel_name: c.name,
        model: "actor-centric",
        distance: nil,
        similarity: 0.95,
        evidence_type: "actor_mention"
      }
    )
    |> apply_time_bounds(opts)
    |> Repo.all(prefix: tenant_schema)
    |> Enum.map(&normalize_match/1)
  end

  defp fetch_actor_messages_about_actor(tenant_schema, actor, target_actor, limit, opts) do
    dumped_actor_id = dump_uuid!(actor.id)
    dumped_target_actor_id = dump_uuid!(target_actor.id)
    mention_patterns = actor_body_patterns(target_actor)
    mention_dynamic = actor_reference_dynamic_for_joined_query(mention_patterns)

    from(m in "messages",
      join: a in "actors",
      on: a.id == m.actor_id,
      join: c in "channels",
      on: c.id == m.channel_id,
      left_join: mm in "message_mentions",
      on: mm.message_id == m.id and mm.actor_id == ^dumped_target_actor_id,
      where: m.actor_id == ^dumped_actor_id,
      where: ^dynamic([m, a, c, mm], not is_nil(mm.id) or ^mention_dynamic),
      order_by: [desc: m.observed_at],
      limit: ^limit,
      select: %{
        message_id: m.id,
        external_id: m.external_id,
        body: m.body,
        observed_at: m.observed_at,
        actor_handle: a.handle,
        actor_display_name: a.display_name,
        channel_name: c.name,
        model: "actor-centric",
        distance: nil,
        similarity: 1.0,
        evidence_type: "actor_targeted_message"
      }
    )
    |> apply_time_bounds(opts)
    |> Repo.all(prefix: tenant_schema)
    |> Enum.map(&normalize_match/1)
  end

  defp sufficient_evidence?(:talks_about, %{message_count: actor_message_count}, matches) do
    actor_message_count >= @minimum_actor_messages and length(matches) >= @minimum_actor_messages
  end

  defp sufficient_evidence?(:knows_about, _stats, matches) do
    length(matches) >= @minimum_actor_profile_messages
  end

  defp sufficient_evidence?(:says_about, _stats, matches) do
    length(matches) >= @minimum_targeted_messages
  end

  defp actor_not_found_result(tenant, question, intent, actor_ref) do
    answer =
      static_answer("I can't find actor \"#{actor_ref}\" in the available tenant history.")

    empty_result(tenant, question, intent, answer, %{
      mode: "actor_qa",
      status: "actor_not_found",
      actor_ref: actor_ref
    })
  end

  defp ambiguous_actor_result(tenant, question, intent, actor_ref, matches) do
    candidates =
      matches
      |> Enum.map(& &1.handle)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.take(5)
      |> Enum.join(", ")

    answer =
      static_answer(
        "I found multiple actor matches for \"#{actor_ref}\"#{candidate_suffix(candidates)}, so I can't answer safely yet."
      )

    empty_result(tenant, question, intent, answer, %{
      mode: "actor_qa",
      status: "ambiguous_actor",
      actor_ref: actor_ref,
      candidate_handles: Enum.map(matches, & &1.handle)
    })
  end

  defp insufficient_evidence_result(tenant, question, intent, actor, target_actor, stats, matches) do
    answer_text =
      case intent.kind do
        :says_about ->
          "I found actor \"#{actor.handle}\", but I don't have enough grounded evidence yet to say what #{actor.handle} said about #{target_actor.handle}."

        _ ->
          "I found actor \"#{actor.handle}\", but there isn't enough grounded tenant history yet for a reliable answer."
      end

    answer = static_answer(answer_text)
    citations = build_citations(matches, tenant.schema_name)

    %{
      tenant_subject_name: tenant.subject_name,
      tenant_schema: tenant.schema_name,
      question: question,
      query:
        %{
          mode: "actor_qa",
          kind: intent.kind,
          status: "insufficient_evidence",
          actor_handle: actor.handle,
          actor_message_count: query_actor_message_count(stats),
          evidence_count: length(matches)
        }
        |> maybe_put_target_handle(target_actor),
      matches: matches,
      citations: citations,
      facts_over_time: facts_over_time(citations),
      context: build_actor_context(question, intent, actor, target_actor, stats, %{}, citations),
      answer: answer
    }
  end

  defp empty_result(tenant, question, intent, answer, query) do
    %{
      tenant_subject_name: tenant.subject_name,
      tenant_schema: tenant.schema_name,
      question: question,
      query: Map.put(query, :kind, intent.kind),
      matches: [],
      citations: [],
      facts_over_time: [],
      context: "",
      answer: answer
    }
  end

  defp build_actor_context(
         question,
         intent,
         actor,
         target_actor,
         stats,
         query_metadata,
         citations
       ) do
    header_lines =
      [
        actor_summary_line(intent.kind, actor, target_actor),
        "Question: #{question}",
        actor_history_line(intent.kind, actor, target_actor, stats),
        actor_retrieval_line(query_metadata)
      ]
      |> Enum.reject(&blank?/1)

    evidence =
      case citations do
        [] -> ""
        rows -> SemanticQA.build_context(rows)
      end

    Enum.join(header_lines ++ blankable(evidence), "\n\n")
  end

  defp actor_summary_line(:talks_about, actor, _target_actor),
    do: "Actor-focused QA for what #{actor.handle} talks about."

  defp actor_summary_line(:knows_about, actor, _target_actor),
    do: "Actor-focused QA for what the tenant history knows about #{actor.handle}."

  defp actor_summary_line(:says_about, actor, target_actor),
    do: "Actor-focused QA for what #{actor.handle} said about #{target_actor.handle}."

  defp actor_history_line(_kind, _actor, _target_actor, stats) do
    "Actor history: #{stats.message_count} messages across #{stats.channel_count || 0} channels#{time_range_suffix(stats)}."
  end

  defp actor_retrieval_line(%{
         retrieval: retrieval,
         actor_message_count: message_count,
         actor_mention_count: mention_count
       }) do
    "Evidence retrieval: #{retrieval}; actor_messages=#{message_count}; mention_messages=#{mention_count}."
  end

  defp actor_retrieval_line(_metadata), do: nil

  defp time_range_suffix(%{first_observed_at: nil, last_observed_at: nil}), do: ""

  defp time_range_suffix(%{
         first_observed_at: first_observed_at,
         last_observed_at: last_observed_at
       }) do
    " from #{format_timestamp(first_observed_at)} to #{format_timestamp(last_observed_at)}"
  end

  defp combine_matches(left, right, limit) do
    (left ++ right)
    |> Enum.uniq_by(& &1.message_id)
    |> Enum.sort_by(&sort_key/1, {:desc, DateTime})
    |> Enum.take(limit)
    |> assign_rank_similarity()
  end

  defp assign_rank_similarity(matches) do
    total = max(length(matches), 1)

    Enum.with_index(matches, 1)
    |> Enum.map(fn {match, index} ->
      similarity = 1.0 - (index - 1) / total * 0.1
      Map.put(match, :similarity, Float.round(similarity, 4))
    end)
  end

  defp sort_key(%{observed_at: %DateTime{} = observed_at}), do: observed_at

  defp sort_key(%{observed_at: %NaiveDateTime{} = observed_at}),
    do: DateTime.from_naive!(observed_at, "Etc/UTC")

  defp sort_key(_match), do: DateTime.from_unix!(0)

  defp build_citations(matches, tenant_schema) do
    entities_by_message =
      fetch_entities_by_message(tenant_schema, Enum.map(matches, & &1.message_id))

    facts_by_message =
      fetch_facts_by_message(tenant_schema, Enum.map(matches, & &1.message_id))

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

  defp generation_opts(opts) do
    provider =
      Keyword.get(
        opts,
        :generation_provider,
        Application.get_env(:threadr, Threadr.ML, [])
        |> Keyword.fetch!(:generation)
        |> Keyword.fetch!(:provider)
      )

    opts
    |> Keyword.take([
      :generation_model,
      :generation_endpoint,
      :generation_api_key,
      :generation_system_prompt,
      :generation_provider_name,
      :generation_temperature,
      :generation_max_tokens,
      :generation_timeout
    ])
    |> Enum.reduce([provider: provider], fn
      {:generation_model, value}, acc -> Keyword.put(acc, :model, value)
      {:generation_endpoint, value}, acc -> Keyword.put(acc, :endpoint, value)
      {:generation_api_key, value}, acc -> Keyword.put(acc, :api_key, value)
      {:generation_system_prompt, value}, acc -> Keyword.put(acc, :system_prompt, value)
      {:generation_provider_name, value}, acc -> Keyword.put(acc, :provider_name, value)
      {:generation_temperature, value}, acc -> Keyword.put(acc, :temperature, value)
      {:generation_max_tokens, value}, acc -> Keyword.put(acc, :max_tokens, value)
      {:generation_timeout, value}, acc -> Keyword.put(acc, :timeout, value)
    end)
  end

  defp static_answer(content) do
    %Result{
      content: content,
      model: "threadr-actor-qa",
      provider: "threadr",
      metadata: %{"mode" => "actor_qa"}
    }
  end

  defp apply_time_bounds(query, opts) do
    query
    |> maybe_filter_since(Keyword.get(opts, :since))
    |> maybe_filter_until(Keyword.get(opts, :until))
  end

  defp maybe_filter_since(query, nil), do: query

  defp maybe_filter_since(query, %NaiveDateTime{} = since) do
    maybe_filter_since(query, DateTime.from_naive!(since, "Etc/UTC"))
  end

  defp maybe_filter_since(query, %DateTime{} = since) do
    where(query, [m], m.observed_at >= ^since)
  end

  defp maybe_filter_until(query, nil), do: query

  defp maybe_filter_until(query, %NaiveDateTime{} = until) do
    maybe_filter_until(query, DateTime.from_naive!(until, "Etc/UTC"))
  end

  defp maybe_filter_until(query, %DateTime{} = until) do
    where(query, [m], m.observed_at <= ^until)
  end

  defp actor_reference_dynamic_for_count([]), do: dynamic(false)

  defp actor_reference_dynamic_for_count(patterns) do
    Enum.reduce(patterns, dynamic(false), fn pattern, dynamic_expr ->
      dynamic([m, _mm], ^dynamic_expr or ilike(m.body, ^pattern))
    end)
  end

  defp actor_reference_dynamic_for_joined_query([]), do: dynamic(false)

  defp actor_reference_dynamic_for_joined_query(patterns) do
    Enum.reduce(patterns, dynamic(false), fn pattern, dynamic_expr ->
      dynamic([m, _a, _c, _mm], ^dynamic_expr or ilike(m.body, ^pattern))
    end)
  end

  defp actor_body_patterns(actor) do
    [actor.handle, actor.display_name, actor.external_id]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.length(&1) < 3))
    |> Enum.uniq()
    |> Enum.map(&"%#{&1}%")
  end

  defp actor_reference_candidates(raw_ref, opts) do
    normalized = normalize_actor_ref(raw_ref)

    refs =
      if self_actor_reference?(normalized) do
        requester_reference_candidates(opts) ++ [normalized]
      else
        [normalized, mention_external_id(normalized), last_token_candidate(normalized)]
      end

    refs
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_actor_ref(raw_ref) do
    raw_ref
    |> to_string()
    |> String.trim()
    |> String.trim_trailing("?")
    |> String.trim_trailing("!")
    |> String.trim_trailing(".")
    |> trim_matching_quotes()
    |> String.trim_leading("@")
    |> String.trim()
  end

  defp trim_matching_quotes("\"" <> rest), do: rest |> String.trim_trailing("\"") |> String.trim()
  defp trim_matching_quotes("'" <> rest), do: rest |> String.trim_trailing("'") |> String.trim()
  defp trim_matching_quotes(value), do: value

  defp mention_external_id("<@" <> rest) do
    rest |> String.trim_trailing(">") |> String.trim_leading("!")
  end

  defp mention_external_id(_value), do: nil

  defp discord_or_plain_external_id(value), do: mention_external_id(value) || value

  defp requester_reference_candidates(opts) do
    [
      Keyword.get(opts, :requester_actor_handle),
      Keyword.get(opts, :requester_actor_display_name),
      Keyword.get(opts, :requester_external_id)
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&normalize_actor_ref/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp self_actor_reference?(value) do
    String.downcase(value) in ["i", "me", "myself"]
  end

  defp last_token_candidate(value) do
    value
    |> String.split(~r/\s+/u, trim: true)
    |> List.last()
    |> case do
      ^value -> nil
      token -> token
    end
  end

  defp uniq_actor_matches(matches) do
    matches
    |> Enum.uniq_by(& &1.id)
  end

  defp normalize_match(match) do
    match
    |> Map.update!(:message_id, &normalize_identifier/1)
    |> Map.update!(:external_id, &normalize_identifier/1)
  end

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

  defp missing_extraction_table?(%Postgrex.Error{postgres: %{code: :undefined_table}}), do: true
  defp missing_extraction_table?(%Postgrex.Error{postgres: %{code: "42P01"}}), do: true
  defp missing_extraction_table?(_error), do: false

  defp format_timestamp(nil), do: "unknown"
  defp format_timestamp(%DateTime{} = timestamp), do: DateTime.to_iso8601(timestamp)
  defp format_timestamp(%NaiveDateTime{} = timestamp), do: NaiveDateTime.to_iso8601(timestamp)
  defp format_timestamp(value), do: to_string(value)

  defp query_actor_message_count(%{actor_message_count: actor_message_count}),
    do: actor_message_count

  defp query_actor_message_count(%{message_count: message_count}), do: message_count

  defp maybe_put_target_handle(query, nil), do: query

  defp maybe_put_target_handle(query, target_actor),
    do: Map.put(query, :target_actor_handle, target_actor.handle)

  defp candidate_suffix(""), do: ""
  defp candidate_suffix(candidates), do: " (#{candidates})"

  defp blankable(nil), do: []
  defp blankable(""), do: []
  defp blankable(value), do: [value]

  defp blank?(value), do: value in [nil, ""]

  defp dump_uuid!(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> Ecto.UUID.dump!(uuid)
      :error -> value
    end
  end

  defp dump_uuid!(value), do: value

  defp actor_limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> max(@default_limit)
    |> min(20)
  end
end
