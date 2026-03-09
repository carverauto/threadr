defmodule Threadr.ML.ConstrainedQA do
  @moduledoc """
  Generic constrained retrieval for actor/time/channel topical questions.
  """

  import Ecto.Query

  alias Threadr.ControlPlane

  alias Threadr.ML.{
    ActorReference,
    Generation,
    GenerationProviderOpts,
    ReconstructionQuery,
    SemanticQA
  }

  alias Threadr.Repo

  @default_limit 8
  @default_system_prompt """
  Extract retrieval constraints from the user's tenant QA question.
  Return strict JSON only with this shape:
  {
    "route": "constrained_qa|fallback",
    "actors": ["string"],
    "counterpart_actors": ["string"],
    "time_scope": "today|yesterday|none",
    "scope_current_channel": true,
    "focus": "topics|summary|activity|unknown"
  }
  Use "constrained_qa" when the question can be answered from a filtered slice of tenant messages based on actor, time, or current-channel scope.
  Use "fallback" for greetings, drawing requests, relationship ranking questions, graph questions, or questions that need a different specialized path.
  """

  def answer_question(tenant_subject_name, question, opts \\ [])
      when is_binary(tenant_subject_name) and is_binary(question) do
    with {:ok, tenant} <-
           ControlPlane.get_tenant_by_subject_name(tenant_subject_name, context: %{system: true}),
         {:ok, constraints} <- extract_constraints(question, opts),
         {:ok, resolved} <- resolve_constraints(tenant.schema_name, constraints, opts),
         {:ok, matches, query} <- retrieve_matches(tenant.schema_name, resolved, opts) do
      build_answer(tenant, question, resolved, matches, query, opts)
    else
      {:error, :fallback} -> {:error, :not_constrained_question}
      {:error, :no_constrained_matches} -> {:error, :not_constrained_question}
      {:error, {:actor_not_found, _actor_ref}} -> {:error, :not_constrained_question}
      {:error, {:ambiguous_actor, _actor_ref, _matches}} -> {:error, :not_constrained_question}
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
    matches =
      fetch_shared_conversation_matches(tenant_schema, actors, counterparts, constraints, opts)

    case matches do
      [] ->
        fallback_matches = fetch_direct_matches(tenant_schema, constraints, opts)

        if fallback_matches == [] do
          {:error, :no_constrained_matches}
        else
          {:ok, fallback_matches, query_metadata(constraints, "actor_messages_about_counterpart")}
        end

      _ ->
        {:ok, matches, query_metadata(constraints, "shared_conversation_messages")}
    end
  end

  defp retrieve_matches(tenant_schema, constraints, opts) do
    matches = fetch_direct_matches(tenant_schema, constraints, opts)

    if matches == [] do
      {:error, :no_constrained_matches}
    else
      {:ok, matches, query_metadata(constraints, "filtered_messages")}
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

  defp fetch_shared_conversation_matches(tenant_schema, actors, counterparts, constraints, opts) do
    limit = Keyword.get(opts, :limit, @default_limit)
    actor_ids = Enum.map(actors, & &1.id)
    counterpart_ids = Enum.map(counterparts, & &1.id)

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
      where: cm_actor.member_id in ^actor_ids and cm_counterpart.member_id in ^counterpart_ids,
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

  defp query_metadata(constraints, retrieval) do
    %{
      retrieval: retrieval,
      actor_handles: Enum.map(constraints.actors, & &1.handle),
      counterpart_actor_handles: Enum.map(constraints.counterpart_actors, & &1.handle),
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

  defp normalize_time_scope("today"), do: :today
  defp normalize_time_scope("yesterday"), do: :yesterday
  defp normalize_time_scope(_value), do: :none

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
    Enum.reduce(patterns, dynamic(false), fn pattern, acc ->
      dynamic([m, _a, _c], ^acc or ilike(m.body, ^pattern))
    end)
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
