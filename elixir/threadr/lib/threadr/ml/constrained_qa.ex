defmodule Threadr.ML.ConstrainedQA do
  @moduledoc """
  Generic constrained retrieval for actor/time/channel topical questions.
  """

  import Ecto.Query

  alias Threadr.ControlPlane

  alias Threadr.ML.{
    ActorReference,
    ConversationQAIntent,
    Generation,
    GenerationProviderOpts,
    ReconstructionQuery,
    SemanticQA
  }

  alias Threadr.Repo

  @default_limit 8
  @pair_message_window_seconds 300
  @pair_cluster_gap_seconds 600
  @pair_cluster_scan_limit 96
  @stopwords MapSet.new([
               "about",
               "after",
               "again",
               "been",
               "being",
               "between",
               "both",
               "could",
               "from",
               "have",
               "just",
               "like",
               "more",
               "much",
               "really",
               "said",
               "some",
               "that",
               "than",
               "their",
               "them",
               "then",
               "they",
               "this",
               "today",
               "were",
               "what",
               "when",
               "with",
               "would",
               "yeah",
               "your"
             ])
  @default_system_prompt """
  Extract retrieval constraints from the user's tenant QA question.
  Return strict JSON only with this shape:
  {
    "route": "constrained_qa|fallback",
    "actors": ["string"],
    "counterpart_actors": ["string"],
    "literal_terms": ["string"],
    "literal_match": "all|any|none",
    "time_scope": "today|yesterday|none",
    "scope_current_channel": true,
    "focus": "topics|summary|activity|unknown"
  }
  Use "literal_terms" for exact lexical questions like who mentioned a term, how many jokes there were, or who said a phrase.
  Use "literal_match":"all" when all listed terms should appear in the same message.
  Use "constrained_qa" when the question can be answered from a filtered slice of tenant messages based on actor, time, or current-channel scope.
  Use "fallback" for greetings, drawing requests, relationship ranking questions, graph questions, or questions that need a different specialized path.
  """

  def answer_question(tenant_subject_name, question, opts \\ [])
      when is_binary(tenant_subject_name) and is_binary(question) do
    with {:ok, tenant} <-
           ControlPlane.get_tenant_by_subject_name(tenant_subject_name, context: %{system: true}),
         {:ok, result} <- answer_with_constraints(tenant, question, opts) do
      {:ok, result}
    else
      {:error, :fallback} -> {:error, :not_constrained_question}
      {:error, :no_constrained_matches} -> {:error, :not_constrained_question}
      {:error, {:actor_not_found, _actor_ref}} -> {:error, :not_constrained_question}
      {:error, {:ambiguous_actor, _actor_ref, _matches}} -> {:error, :not_constrained_question}
    end
  end

  defp answer_with_constraints(tenant, question, opts) do
    with {:ok, constraints} <- resolve_question_constraints(tenant.schema_name, question, opts),
         {:ok, matches, query} <- retrieve_matches(tenant.schema_name, constraints, opts) do
      build_answer(tenant, question, constraints, matches, query, opts)
    end
  end

  defp resolve_question_constraints(tenant_schema, question, opts) do
    case ConversationQAIntent.classify(question) do
      {:ok, %{kind: :talked_with, actor_ref: actor_ref, target_ref: target_ref}} ->
        with {:ok, actor} <- ActorReference.resolve(tenant_schema, actor_ref, opts),
             {:ok, target_actor} <- ActorReference.resolve(tenant_schema, target_ref, opts) do
          {:ok,
           %{
             actors: [actor],
             counterpart_actors: [target_actor],
             literal_terms: [],
             literal_match: "all",
             time_scope: infer_time_scope(question),
             scope_current_channel: Keyword.get(opts, :requester_channel_name) != nil,
             focus: "topics",
             requester_channel_name: Keyword.get(opts, :requester_channel_name),
             pair_required: true
           }}
        end

      {:error, :not_conversation_question} ->
        with {:ok, constraints} <- extract_constraints(question, opts),
             {:ok, resolved} <- resolve_constraints(tenant_schema, constraints, opts) do
          {:ok, Map.put(resolved, :pair_required, false)}
        end
    end
  end

  defp build_answer(tenant, question, constraints, matches, query, opts) do
    citations = build_citations(matches)
    context = build_context(question, constraints, citations)

    with {:ok, answer} <- Generation.answer_question(question, context, generation_opts(opts)) do
      {:ok,
       %{
         tenant_subject_name: tenant.subject_name,
         tenant_schema: tenant.schema_name,
         question: question,
         query:
           query
           |> Map.put(:mode, "constrained_qa")
           |> Map.put(:focus, constraints.focus)
           |> Map.put(:scope_current_channel, constraints.scope_current_channel),
         matches: matches,
         citations: citations,
         facts_over_time: [],
         context: context,
         answer: answer
       }}
    end
  end

  defp extract_constraints(question, opts) do
    with {:ok, result} <-
           Generation.complete(
             constraint_prompt(question, opts),
             extraction_generation_opts(opts)
           ),
         {:ok, payload} <- parse_payload(result.content),
         "constrained_qa" <- Map.get(payload, "route") do
      {:ok,
       %{
         actors: normalize_refs(Map.get(payload, "actors", [])),
         counterpart_actors: normalize_refs(Map.get(payload, "counterpart_actors", [])),
         literal_terms: normalize_literal_terms(Map.get(payload, "literal_terms", [])),
         literal_match: normalize_literal_match(Map.get(payload, "literal_match")),
         time_scope: normalize_time_scope(Map.get(payload, "time_scope")),
         scope_current_channel: Map.get(payload, "scope_current_channel") == true,
         focus: normalize_focus(Map.get(payload, "focus"))
       }}
    else
      "fallback" -> {:error, :fallback}
      {:error, _reason} -> {:error, :fallback}
      _ -> {:error, :fallback}
    end
  end

  defp resolve_constraints(tenant_schema, constraints, opts) do
    with {:ok, actors} <- resolve_actor_refs(tenant_schema, constraints.actors, opts),
         {:ok, counterpart_actors} <-
           resolve_actor_refs(tenant_schema, constraints.counterpart_actors, opts) do
      {:ok,
       constraints
       |> Map.put(:actors, actors)
       |> Map.put(:counterpart_actors, counterpart_actors)
       |> Map.put(
         :requester_channel_name,
         if(constraints.scope_current_channel, do: Keyword.get(opts, :requester_channel_name))
       )}
    end
  end

  defp retrieve_matches(
         tenant_schema,
         %{actors: actors, counterpart_actors: counterparts} = constraints,
         opts
       )
       when actors != [] and counterparts != [] do
    case fetch_pair_matches(tenant_schema, actors, counterparts, constraints, opts) do
      nil ->
        if Map.get(constraints, :pair_required, false) do
          {:error, :no_constrained_matches}
        else
          fallback_matches = fetch_direct_matches(tenant_schema, constraints, opts)

          if fallback_matches == [] do
            {:error, :no_constrained_matches}
          else
            {:ok, fallback_matches,
             query_metadata(constraints, "actor_messages_about_counterpart")}
          end
        end

      {retrieval, matches} ->
        {:ok, matches, query_metadata(constraints, retrieval)}
    end
  end

  defp retrieve_matches(tenant_schema, constraints, opts) do
    matches =
      if constraints.literal_terms != [] do
        fetch_literal_matches(tenant_schema, constraints, opts)
      else
        fetch_direct_matches(tenant_schema, constraints, opts)
      end

    if matches == [] do
      {:error, :no_constrained_matches}
    else
      retrieval =
        if constraints.literal_terms != [] do
          "literal_term_messages"
        else
          "filtered_messages"
        end

      {:ok, matches, query_metadata(constraints, retrieval)}
    end
  end

  defp fetch_pair_matches(tenant_schema, actors, counterparts, constraints, opts) do
    shared_matches =
      fetch_shared_conversation_matches(tenant_schema, actors, counterparts, constraints, opts)

    case ensure_pair_presence(shared_matches, actors, counterparts) do
      [] ->
        case fetch_mutual_direct_matches(tenant_schema, actors, counterparts, constraints, opts) do
          [] -> fetch_topical_pair_matches(tenant_schema, actors, counterparts, constraints, opts)
          matches -> {"paired_actor_messages", matches}
        end

      matches ->
        {"shared_conversation_messages", matches}
    end
  end

  defp fetch_direct_matches(tenant_schema, constraints, opts) do
    limit = Keyword.get(opts, :limit, @default_limit)
    actor_ids = Enum.map(constraints.actors, &dump_uuid!(&1.id))
    counterpart_patterns = counterpart_patterns(constraints.counterpart_actors)

    from(m in "messages",
      join: a in "actors",
      on: a.id == m.actor_id,
      join: c in "channels",
      on: c.id == m.channel_id,
      where: ^actor_filter(actor_ids),
      where: ^channel_filter(constraints.requester_channel_name),
      where: ^counterpart_filter(counterpart_patterns),
      order_by: [desc: m.observed_at, desc: m.id],
      limit: ^limit,
      select: %{
        message_id: m.id,
        external_id: m.external_id,
        body: m.body,
        observed_at: m.observed_at,
        actor_handle: a.handle,
        actor_display_name: a.display_name,
        channel_name: c.name
      }
    )
    |> apply_time_scope(constraints.time_scope)
    |> Repo.all(prefix: tenant_schema)
    |> Enum.map(&normalize_match/1)
  end

  defp fetch_literal_matches(tenant_schema, constraints, opts) do
    limit = Keyword.get(opts, :limit, @default_limit)
    actor_ids = Enum.map(constraints.actors, &dump_uuid!(&1.id))
    literal_filter = literal_filter(constraints.literal_terms, constraints.literal_match)

    from(m in "messages",
      join: a in "actors",
      on: a.id == m.actor_id,
      join: c in "channels",
      on: c.id == m.channel_id,
      where: ^actor_filter(actor_ids),
      where: ^channel_filter(constraints.requester_channel_name),
      where: ^literal_filter,
      order_by: [desc: m.observed_at, desc: m.id],
      limit: ^limit,
      select: %{
        message_id: m.id,
        external_id: m.external_id,
        body: m.body,
        observed_at: m.observed_at,
        actor_handle: a.handle,
        actor_display_name: a.display_name,
        channel_name: c.name
      }
    )
    |> apply_time_scope(constraints.time_scope)
    |> Repo.all(prefix: tenant_schema)
    |> Enum.map(&normalize_match/1)
  end

  defp fetch_mutual_direct_matches(tenant_schema, actors, counterparts, constraints, opts) do
    limit = Keyword.get(opts, :limit, @default_limit)
    actor_ids = Enum.map(actors, &dump_uuid!(&1.id))
    counterpart_ids = Enum.map(counterparts, &dump_uuid!(&1.id))
    actor_patterns = counterpart_patterns(actors)
    counterpart_patterns = counterpart_patterns(counterparts)

    actor_side =
      dynamic(
        [m, _a, _c],
        m.actor_id in ^actor_ids and ^pattern_filter(counterpart_patterns)
      )

    counterpart_side =
      dynamic(
        [m, _a, _c],
        m.actor_id in ^counterpart_ids and ^pattern_filter(actor_patterns)
      )

    seed_matches =
      from(m in "messages",
        join: a in "actors",
        on: a.id == m.actor_id,
        join: c in "channels",
        on: c.id == m.channel_id,
        where: ^channel_filter(constraints.requester_channel_name),
        where: ^dynamic(^actor_side or ^counterpart_side),
        order_by: [desc: m.observed_at, desc: m.id],
        limit: ^(limit * 2),
        select: %{
          message_id: m.id,
          external_id: m.external_id,
          body: m.body,
          observed_at: m.observed_at,
          actor_handle: a.handle,
          actor_display_name: a.display_name,
          channel_name: c.name
        }
      )
      |> apply_time_scope(constraints.time_scope)
      |> Repo.all(prefix: tenant_schema)
      |> Enum.map(&normalize_match/1)

    if seed_matches == [] do
      []
    else
      pair_actor_ids = actor_ids ++ counterpart_ids

      from(m in "messages",
        join: a in "actors",
        on: a.id == m.actor_id,
        join: c in "channels",
        on: c.id == m.channel_id,
        where: ^channel_filter(constraints.requester_channel_name),
        where: m.actor_id in ^pair_actor_ids,
        order_by: [desc: m.observed_at, desc: m.id],
        limit: ^(limit * 8),
        select: %{
          message_id: m.id,
          external_id: m.external_id,
          body: m.body,
          observed_at: m.observed_at,
          actor_handle: a.handle,
          actor_display_name: a.display_name,
          channel_name: c.name
        }
      )
      |> apply_time_scope(constraints.time_scope)
      |> Repo.all(prefix: tenant_schema)
      |> Enum.map(&normalize_match/1)
      |> Enum.filter(&within_pair_window?(&1, seed_matches))
      |> Enum.sort_by(& &1.observed_at, {:desc, NaiveDateTime})
      |> ensure_pair_presence(actors, counterparts)
      |> Enum.take(limit * 2)
    end
  end

  defp fetch_shared_conversation_matches(tenant_schema, actors, counterparts, constraints, opts) do
    limit = Keyword.get(opts, :limit, @default_limit)
    actor_member_ids = Enum.map(actors, & &1.id)
    counterpart_member_ids = Enum.map(counterparts, & &1.id)
    allowed_actor_ids = Enum.map(actors ++ counterparts, &dump_uuid!(&1.id))

    from(c in "conversations",
      join: cm_actor in "conversation_memberships",
      on: cm_actor.conversation_id == c.id and cm_actor.member_kind == "actor",
      join: cm_counterpart in "conversation_memberships",
      on: cm_counterpart.conversation_id == c.id and cm_counterpart.member_kind == "actor",
      join: cm_message in "conversation_memberships",
      on: cm_message.conversation_id == c.id and cm_message.member_kind == "message",
      join: m in "messages",
      on: m.id == type(cm_message.member_id, :binary_id),
      join: a in "actors",
      on: a.id == m.actor_id,
      join: ch in "channels",
      on: ch.id == m.channel_id,
      where:
        cm_actor.member_id in ^actor_member_ids and
          cm_counterpart.member_id in ^counterpart_member_ids,
      where: m.actor_id in ^allowed_actor_ids,
      where: ^shared_channel_filter(constraints.requester_channel_name),
      order_by: [desc: m.observed_at, desc: m.id],
      limit: ^limit,
      select: %{
        message_id: m.id,
        external_id: m.external_id,
        body: m.body,
        observed_at: m.observed_at,
        actor_handle: a.handle,
        actor_display_name: a.display_name,
        channel_name: ch.name
      }
    )
    |> apply_conversation_time_scope(constraints.time_scope)
    |> ReconstructionQuery.all(tenant_schema)
    |> Enum.map(&normalize_match/1)
    |> Enum.uniq_by(& &1.message_id)
  end

  defp fetch_topical_pair_matches(tenant_schema, actors, counterparts, constraints, opts) do
    limit = Keyword.get(opts, :limit, @default_limit)
    scan_limit = max(limit * 12, @pair_cluster_scan_limit)
    pair_actor_ids = Enum.map(actors ++ counterparts, &dump_uuid!(&1.id))

    matches =
      from(m in "messages",
        join: a in "actors",
        on: a.id == m.actor_id,
        join: c in "channels",
        on: c.id == m.channel_id,
        where: ^channel_filter(constraints.requester_channel_name),
        where: m.actor_id in ^pair_actor_ids,
        order_by: [desc: m.observed_at, desc: m.id],
        limit: ^scan_limit,
        select: %{
          message_id: m.id,
          external_id: m.external_id,
          body: m.body,
          observed_at: m.observed_at,
          actor_handle: a.handle,
          actor_display_name: a.display_name,
          channel_name: c.name
        }
      )
      |> apply_time_scope(constraints.time_scope)
      |> Repo.all(prefix: tenant_schema)
      |> Enum.map(&normalize_match/1)
      |> Enum.sort_by(&{&1.channel_name, &1.observed_at, &1.message_id}, :asc)

    actor_handles = actor_identifiers(actors)
    counterpart_handles = actor_identifiers(counterparts)

    matches
    |> topical_pair_clusters(actor_handles, counterpart_handles)
    |> Enum.max_by(& &1.score, fn -> nil end)
    |> case do
      nil ->
        nil

      cluster ->
        {"topical_pair_messages", Enum.take(cluster.matches, limit * 2)}
    end
  end

  defp topical_pair_clusters(matches, actor_handles, counterpart_handles) do
    matches
    |> Enum.chunk_while(
      nil,
      fn match, cluster ->
        current_cluster = cluster || new_pair_cluster(match)

        if cluster == nil do
          {:cont, current_cluster}
        else
          if pair_cluster_continuation?(current_cluster, match) do
            {:cont, append_pair_cluster(current_cluster, match)}
          else
            {:cont, finalize_pair_cluster(current_cluster, actor_handles, counterpart_handles),
             new_pair_cluster(match)}
          end
        end
      end,
      fn
        nil ->
          {:cont, []}

        cluster ->
          {:cont, finalize_pair_cluster(cluster, actor_handles, counterpart_handles), []}
      end
    )
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  defp new_pair_cluster(match) do
    %{
      channel_name: match.channel_name,
      last_observed_at: match.observed_at,
      matches: [match]
    }
  end

  defp append_pair_cluster(cluster, match) do
    %{
      cluster
      | last_observed_at: match.observed_at,
        matches: cluster.matches ++ [match]
    }
  end

  defp pair_cluster_continuation?(cluster, match) do
    cluster.channel_name == match.channel_name and
      NaiveDateTime.diff(match.observed_at, cluster.last_observed_at, :second) <=
        @pair_cluster_gap_seconds
  end

  defp finalize_pair_cluster(cluster, actor_handles, counterpart_handles) do
    matches = cluster.matches

    with true <- pair_cluster_has_both_sides?(matches, actor_handles, counterpart_handles),
         {score, overlap_count, alternations, cross_mentions} when score > 0 <-
           score_pair_cluster(matches, actor_handles, counterpart_handles) do
      [
        %{
          matches: matches,
          score: score,
          overlap_count: overlap_count,
          alternations: alternations,
          cross_mentions: cross_mentions
        }
      ]
    else
      _ -> []
    end
  end

  defp pair_cluster_has_both_sides?(matches, actor_handles, counterpart_handles) do
    sides =
      matches
      |> Enum.map(&match_side(&1, actor_handles, counterpart_handles))
      |> MapSet.new()

    MapSet.member?(sides, :actor) and MapSet.member?(sides, :counterpart)
  end

  defp score_pair_cluster(matches, actor_handles, counterpart_handles) do
    actor_messages =
      Enum.filter(matches, &(match_side(&1, actor_handles, counterpart_handles) == :actor))

    counterpart_messages =
      Enum.filter(matches, &(match_side(&1, actor_handles, counterpart_handles) == :counterpart))

    actor_tokens =
      actor_messages
      |> Enum.flat_map(&message_tokens(&1.body))
      |> MapSet.new()

    counterpart_tokens =
      counterpart_messages
      |> Enum.flat_map(&message_tokens(&1.body))
      |> MapSet.new()

    overlap_count = MapSet.intersection(actor_tokens, counterpart_tokens) |> MapSet.size()
    alternations = pair_alternations(matches, actor_handles, counterpart_handles)

    cross_mentions =
      Enum.count(actor_messages, &mentions_any?(&1.body, counterpart_handles)) +
        Enum.count(counterpart_messages, &mentions_any?(&1.body, actor_handles))

    message_count = length(matches)

    score =
      cond do
        overlap_count > 0 ->
          overlap_count * 4 + alternations * 2 + min(message_count, 6) + cross_mentions

        alternations >= 3 and cross_mentions > 0 ->
          alternations * 2 + min(message_count, 4) + cross_mentions

        true ->
          0
      end

    {score, overlap_count, alternations, cross_mentions}
  end

  defp pair_alternations(matches, actor_handles, counterpart_handles) do
    matches
    |> Enum.map(&match_side(&1, actor_handles, counterpart_handles))
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.count(fn [left, right] ->
      left != :unknown and right != :unknown and left != right
    end)
  end

  defp match_side(match, actor_handles, counterpart_handles) do
    actor_handle = normalize_identifier_token(match.actor_handle)
    display_name = normalize_identifier_token(match.actor_display_name)

    cond do
      MapSet.member?(actor_handles, actor_handle) or MapSet.member?(actor_handles, display_name) ->
        :actor

      MapSet.member?(counterpart_handles, actor_handle) or
          MapSet.member?(counterpart_handles, display_name) ->
        :counterpart

      true ->
        :unknown
    end
  end

  defp actor_identifiers(actors) do
    actors
    |> Enum.flat_map(fn actor -> [actor.handle, actor.display_name] end)
    |> Enum.map(&normalize_identifier_token/1)
    |> Enum.reject(&(&1 == ""))
    |> MapSet.new()
  end

  defp mentions_any?(body, identifiers) when is_binary(body) do
    downcased = String.downcase(body)
    Enum.any?(identifiers, &(&1 != "" and String.contains?(downcased, &1)))
  end

  defp message_tokens(body) when is_binary(body) do
    body
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, " ")
    |> String.split()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.length(&1) < 3))
    |> Enum.reject(&MapSet.member?(@stopwords, &1))
    |> Enum.uniq()
  end

  defp message_tokens(_body), do: []

  defp normalize_identifier_token(nil), do: ""

  defp normalize_identifier_token(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp ensure_pair_presence(matches, actors, counterparts) do
    actor_handles = MapSet.new(Enum.map(actors, &String.downcase(&1.handle)))
    counterpart_handles = MapSet.new(Enum.map(counterparts, &String.downcase(&1.handle)))

    present_handles =
      matches
      |> Enum.map(&String.downcase(&1.actor_handle))
      |> MapSet.new()

    if MapSet.disjoint?(present_handles, actor_handles) or
         MapSet.disjoint?(present_handles, counterpart_handles) do
      []
    else
      matches
    end
  end

  defp within_pair_window?(match, seed_matches) do
    Enum.any?(seed_matches, fn seed ->
      abs(NaiveDateTime.diff(match.observed_at, seed.observed_at, :second)) <=
        @pair_message_window_seconds
    end)
  end

  defp query_metadata(constraints, retrieval) do
    %{
      retrieval: retrieval,
      actor_handles: Enum.map(constraints.actors, & &1.handle),
      counterpart_actor_handles: Enum.map(constraints.counterpart_actors, & &1.handle),
      literal_terms: constraints.literal_terms,
      literal_match: constraints.literal_match,
      time_scope: constraints.time_scope,
      channel_name: constraints.requester_channel_name
    }
  end

  defp build_citations(matches) do
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
        similarity: 1.0,
        extracted_entities: [],
        extracted_facts: []
      }
    end)
  end

  defp build_context(question, constraints, citations) do
    [
      "Constrained tenant QA from a filtered message slice.",
      "Question: #{question}",
      constraint_summary(constraints),
      SemanticQA.build_context(citations)
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n\n")
  end

  defp constraint_summary(constraints) do
    parts =
      []
      |> maybe_put_summary("Actors", Enum.map(constraints.actors, & &1.handle))
      |> maybe_put_summary(
        "Counterpart actors",
        Enum.map(constraints.counterpart_actors, & &1.handle)
      )
      |> maybe_put_summary("Literal terms", constraints.literal_terms)
      |> maybe_put_summary(
        "Time scope",
        constraints.time_scope != :none && Atom.to_string(constraints.time_scope)
      )
      |> maybe_put_summary("Channel", constraints.requester_channel_name)

    if parts == [] do
      nil
    else
      Enum.join(parts, "\n")
    end
  end

  defp maybe_put_summary(parts, _label, false), do: parts
  defp maybe_put_summary(parts, _label, nil), do: parts
  defp maybe_put_summary(parts, _label, []), do: parts

  defp maybe_put_summary(parts, label, values) when is_list(values) do
    parts ++ ["#{label}: #{Enum.join(values, ", ")}"]
  end

  defp maybe_put_summary(parts, label, value), do: parts ++ ["#{label}: #{value}"]

  defp normalize_refs(values) when is_list(values) do
    values
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_refs(_value), do: []

  defp normalize_literal_terms(values) when is_list(values) do
    values
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_literal_terms(_value), do: []

  defp normalize_time_scope("today"), do: :today
  defp normalize_time_scope("yesterday"), do: :yesterday
  defp normalize_time_scope(_value), do: :none

  defp normalize_literal_match(value) when value in ["all", "any"], do: value
  defp normalize_literal_match(_value), do: "all"

  defp normalize_focus(value) when value in ["topics", "summary", "activity"], do: value
  defp normalize_focus(_value), do: "unknown"

  defp resolve_actor_refs(_tenant_schema, [], _opts), do: {:ok, []}

  defp resolve_actor_refs(tenant_schema, refs, opts) do
    refs
    |> Enum.reduce_while({:ok, []}, fn ref, {:ok, actors} ->
      case ActorReference.resolve(tenant_schema, ref, opts) do
        {:ok, actor} -> {:cont, {:ok, [actor | actors]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, actors} -> {:ok, Enum.reverse(actors) |> Enum.uniq_by(& &1.id)}
      error -> error
    end
  end

  defp counterpart_patterns(counterparts) do
    counterparts
    |> Enum.flat_map(fn actor -> [actor.handle, actor.display_name] end)
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.map(&"%#{&1}%")
  end

  defp actor_filter([]), do: dynamic(true)
  defp actor_filter(actor_ids), do: dynamic([m, _a, _c], m.actor_id in ^actor_ids)

  defp channel_filter(nil), do: dynamic(true)

  defp channel_filter(channel_name) do
    normalized = String.downcase(String.trim(channel_name))
    dynamic([_m, _a, c], fragment("lower(?) = ?", c.name, ^normalized))
  end

  defp shared_channel_filter(nil), do: dynamic(true)

  defp shared_channel_filter(channel_name) do
    normalized = String.downcase(String.trim(channel_name))

    dynamic(
      [_c, _cm_actor, _cm_counterpart, _cm_message, _m, _a, ch],
      fragment("lower(?) = ?", ch.name, ^normalized)
    )
  end

  defp counterpart_filter([]), do: dynamic(true)

  defp counterpart_filter(patterns) do
    pattern_filter(patterns)
  end

  defp pattern_filter([]), do: dynamic(true)

  defp pattern_filter(patterns) do
    Enum.reduce(patterns, dynamic(false), fn pattern, acc ->
      dynamic([m, _a, _c], ^acc or ilike(m.body, ^pattern))
    end)
  end

  defp literal_filter([], _match_mode), do: dynamic(true)

  defp literal_filter(terms, "any") do
    terms
    |> Enum.map(&"%#{&1}%")
    |> Enum.reduce(dynamic(false), fn pattern, acc ->
      dynamic([m, _a, _c], ^acc or ilike(m.body, ^pattern))
    end)
  end

  defp literal_filter(terms, _match_mode) do
    terms
    |> Enum.map(&"%#{&1}%")
    |> Enum.reduce(dynamic(true), fn pattern, acc ->
      dynamic([m, _a, _c], ^acc and ilike(m.body, ^pattern))
    end)
  end

  defp infer_time_scope(question) do
    downcased = String.downcase(question)

    cond do
      String.contains?(downcased, "today") -> :today
      String.contains?(downcased, "yesterday") -> :yesterday
      true -> :none
    end
  end

  defp apply_time_scope(query, :today) do
    {since, until} = today_bounds()
    where(query, [m, _a, _c], m.observed_at >= ^since and m.observed_at <= ^until)
  end

  defp apply_time_scope(query, :yesterday) do
    {since, until} = yesterday_bounds()
    where(query, [m, _a, _c], m.observed_at >= ^since and m.observed_at <= ^until)
  end

  defp apply_time_scope(query, :none), do: query

  defp apply_conversation_time_scope(query, :today) do
    {since, until} = today_bounds()

    where(
      query,
      [c, _cm_actor, _cm_counterpart, _cm_message, m, _a, _ch],
      m.observed_at >= ^since and m.observed_at <= ^until
    )
  end

  defp apply_conversation_time_scope(query, :yesterday) do
    {since, until} = yesterday_bounds()

    where(
      query,
      [c, _cm_actor, _cm_counterpart, _cm_message, m, _a, _ch],
      m.observed_at >= ^since and m.observed_at <= ^until
    )
  end

  defp apply_conversation_time_scope(query, :none), do: query

  defp today_bounds do
    date = Date.utc_today()
    since = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    until = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
    {since, until}
  end

  defp yesterday_bounds do
    date = Date.add(Date.utc_today(), -1)
    since = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    until = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
    {since, until}
  end

  defp extraction_generation_opts(opts) do
    GenerationProviderOpts.from_prefixed(
      opts,
      mode: :routing,
      system_prompt: @default_system_prompt,
      temperature: 0.0,
      max_tokens: 250
    )
  end

  defp generation_opts(opts), do: GenerationProviderOpts.from_prefixed(opts)

  defp constraint_prompt(question, opts) do
    """
    Question: #{question}
    Requester actor handle: #{Keyword.get(opts, :requester_actor_handle) || "unknown"}
    Current channel name: #{Keyword.get(opts, :requester_channel_name) || "unknown"}
    """
  end

  defp parse_payload(content) when is_binary(content) do
    content
    |> String.trim()
    |> String.trim_leading("```json")
    |> String.trim_leading("```")
    |> String.trim_trailing("```")
    |> String.trim()
    |> Jason.decode()
    |> case do
      {:ok, payload} when is_map(payload) -> {:ok, payload}
      _ -> {:error, :invalid_payload}
    end
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

  defp dump_uuid!(value) when is_binary(value), do: Ecto.UUID.dump!(value)
  defp dump_uuid!(value), do: value

  defp blank?(value), do: value in [nil, ""]
end
