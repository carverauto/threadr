defmodule Threadr.ML.HybridRetriever do
  @moduledoc """
  Shared tenant message retrieval that can merge vector and lexical evidence.
  """

  import Ecto.Query
  import Pgvector.Ecto.Query

  alias Threadr.ML.{EmbeddingProviderOpts, Embeddings}
  alias Threadr.Repo

  @default_limit 5
  @default_vector_limit 24
  @default_lexical_limit 24
  @default_expansion_limit 8
  @default_expansion_window_seconds 180
  @lexical_similarity_threshold 0.08
  @stopwords MapSet.new([
               "a",
               "about",
               "all",
               "an",
               "and",
               "are",
               "did",
               "do",
               "does",
               "for",
               "from",
               "how",
               "i",
               "in",
               "is",
               "it",
               "me",
               "of",
               "on",
               "or",
               "said",
               "that",
               "the",
               "this",
               "to",
               "today",
               "was",
               "what",
               "when",
               "where",
               "who",
               "why",
               "with"
             ])

  def search_messages(tenant_schema, question, opts \\ [])
      when is_binary(tenant_schema) and is_binary(question) and is_list(opts) do
    limit = Keyword.get(opts, :limit, @default_limit)

    vector_result = fetch_vector_matches(tenant_schema, question, opts)
    lexical_matches = fetch_lexical_matches(tenant_schema, question, opts)

    seed_matches =
      vector_result
      |> vector_matches()
      |> merge_matches(lexical_matches, lexical_terms(question), limit)

    matches =
      seed_matches
      |> expand_matches(tenant_schema, opts)

    cond do
      matches != [] ->
        {:ok, matches,
         query_metadata(vector_result, lexical_matches, seed_matches, matches, limit)}

      match?({:error, :no_message_embeddings}, vector_result) ->
        {:error, :no_message_embeddings}

      true ->
        {:error, :no_retrieval_matches}
    end
  end

  defp fetch_vector_matches(tenant_schema, question, opts) do
    with {:ok, query_embedding} <- Embeddings.embed_query(question, embedding_opts(opts)),
         {:ok, query_vector} <- Ash.Vector.new(query_embedding.embedding) do
      model = Keyword.get(opts, :embedding_model, default_embedding_model())
      limit = max(Keyword.get(opts, :limit, @default_limit) * 4, @default_vector_limit)

      matches =
        from(me in "message_embeddings",
          join: m in "messages",
          on: m.id == me.message_id,
          join: a in "actors",
          on: a.id == m.actor_id,
          join: c in "channels",
          on: c.id == m.channel_id,
          where: me.model == ^model,
          where: ^vector_actor_filter(Keyword.get(opts, :actor_ids, [])),
          where: ^vector_channel_filter(request_channel_name(opts)),
          where: ^vector_message_since_filter(Keyword.get(opts, :since)),
          where: ^vector_message_until_filter(Keyword.get(opts, :until)),
          order_by: cosine_distance(me.embedding, ^query_vector),
          limit: ^limit,
          select: %{
            message_id: m.id,
            external_id: m.external_id,
            body: m.body,
            observed_at: m.observed_at,
            metadata: m.metadata,
            actor_handle: a.handle,
            actor_display_name: a.display_name,
            channel_name: c.name,
            model: me.model,
            distance: cosine_distance(me.embedding, ^query_vector)
          }
        )
        |> Repo.all(prefix: tenant_schema)
        |> Enum.map(&normalize_vector_match/1)

      case matches do
        [] ->
          {:error, :no_message_embeddings}

        _ ->
          {:ok,
           %{
             matches: matches,
             model: model,
             provider: query_embedding.provider,
             metadata: Map.get(query_embedding, :metadata, %{})
           }}
      end
    else
      {:error, _reason} = error -> error
    end
  end

  defp fetch_lexical_matches(tenant_schema, question, opts) do
    normalized_question = normalize_question(question)
    terms = lexical_terms(question)
    limit = max(Keyword.get(opts, :limit, @default_limit) * 4, @default_lexical_limit)

    lexical_gate =
      dynamic(
        [m, _a, _c],
        fragment(
          "similarity(lower(?), ?) >= ?",
          m.body,
          ^normalized_question,
          ^@lexical_similarity_threshold
        ) or
          ^term_filter(terms)
      )

    from(m in "messages",
      join: a in "actors",
      on: a.id == m.actor_id,
      join: c in "channels",
      on: c.id == m.channel_id,
      where: ^actor_filter(Keyword.get(opts, :actor_ids, [])),
      where: ^channel_filter(request_channel_name(opts)),
      where: ^message_since_filter(Keyword.get(opts, :since)),
      where: ^message_until_filter(Keyword.get(opts, :until)),
      where: ^lexical_gate,
      order_by: [
        desc: fragment("similarity(lower(?), ?)", m.body, ^normalized_question),
        desc: m.observed_at
      ],
      limit: ^limit,
      select: %{
        message_id: m.id,
        external_id: m.external_id,
        body: m.body,
        observed_at: m.observed_at,
        metadata: m.metadata,
        actor_handle: a.handle,
        actor_display_name: a.display_name,
        channel_name: c.name,
        lexical_similarity: fragment("similarity(lower(?), ?)", m.body, ^normalized_question)
      }
    )
    |> Repo.all(prefix: tenant_schema)
    |> Enum.map(&normalize_lexical_match/1)
  end

  defp merge_matches(vector_matches, lexical_matches, terms, limit) do
    vector_by_id = Map.new(vector_matches, &{&1.message_id, &1})
    lexical_by_id = Map.new(lexical_matches, &{&1.message_id, &1})

    vector_by_id
    |> Map.merge(lexical_by_id)
    |> Enum.map(fn {message_id, match} ->
      vector_match = Map.get(vector_by_id, message_id)
      lexical_match = Map.get(lexical_by_id, message_id)

      overlap =
        lexical_overlap_count(
          match.body,
          terms
        )

      score =
        vector_similarity(vector_match) * 0.7 +
          lexical_similarity(lexical_match) * 0.8 +
          overlap * 0.15 +
          exact_phrase_bonus(match.body, terms)

      match
      |> Map.put(
        :similarity,
        max(vector_similarity(vector_match), lexical_similarity(lexical_match))
      )
      |> Map.put(:distance, vector_distance(vector_match))
      |> Map.put(:model, vector_model(vector_match))
      |> Map.put(:retrieval_score, score)
    end)
    |> Enum.sort_by(
      fn match -> {match.retrieval_score, match.observed_at, match.message_id} end,
      :desc
    )
    |> Enum.take(limit)
  end

  defp query_metadata(vector_result, lexical_matches, seed_matches, matches, limit) do
    vector_metadata =
      case vector_result do
        {:ok, result} ->
          %{
            provider: result.provider,
            model: result.model,
            metadata: result.metadata
          }

        _ ->
          %{
            provider: nil,
            model: nil,
            metadata: %{}
          }
      end

    Map.merge(vector_metadata, %{
      retrieval: "hybrid",
      retrieval_sources:
        []
        |> maybe_add_source(match?({:ok, _}, vector_result), "vector")
        |> maybe_add_source(lexical_matches != [], "lexical"),
      lexical_match_count: length(lexical_matches),
      seed_match_count: length(seed_matches),
      expanded_match_count: max(length(matches) - length(seed_matches), 0),
      limit: limit
    })
  end

  defp expand_matches([], _tenant_schema, _opts), do: []

  defp expand_matches(seed_matches, tenant_schema, opts) do
    expansion_limit =
      opts
      |> Keyword.get(:expansion_limit, @default_expansion_limit)
      |> max(0)

    if expansion_limit == 0 do
      seed_matches
    else
      expansion_matches =
        tenant_schema
        |> fetch_expansion_candidates(seed_matches, opts, expansion_limit)
        |> Enum.reject(&seed_message?(seed_matches, &1))
        |> Enum.uniq_by(& &1.message_id)
        |> Enum.take(expansion_limit)
        |> Enum.map(&mark_expanded_match/1)

      seed_matches ++ expansion_matches
    end
  end

  defp fetch_expansion_candidates(tenant_schema, seed_matches, opts, expansion_limit) do
    channel_names = seed_matches |> Enum.map(& &1.channel_name) |> Enum.uniq()
    actor_ids = Keyword.get(opts, :actor_ids, [])
    seed_external_ids = MapSet.new(Enum.map(seed_matches, & &1.external_id))

    seed_reply_targets =
      seed_matches
      |> Enum.map(&get_in(&1, [:metadata, "reply_to_external_id"]))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    {since, until} = expansion_bounds(seed_matches, opts)

    from(m in "messages",
      join: a in "actors",
      on: a.id == m.actor_id,
      join: c in "channels",
      on: c.id == m.channel_id,
      where: ^expansion_actor_filter(actor_ids),
      where: ^expansion_channel_filter(channel_names),
      where: m.observed_at >= ^since and m.observed_at <= ^until,
      order_by: [asc: m.observed_at, asc: m.id],
      limit: ^max(expansion_limit * 8, expansion_limit),
      select: %{
        message_id: m.id,
        external_id: m.external_id,
        body: m.body,
        observed_at: m.observed_at,
        metadata: m.metadata,
        actor_handle: a.handle,
        actor_display_name: a.display_name,
        channel_name: c.name
      }
    )
    |> Repo.all(prefix: tenant_schema)
    |> Enum.map(&normalize_expansion_match/1)
    |> Enum.filter(
      &expansion_match?(&1, seed_matches, seed_external_ids, seed_reply_targets, opts)
    )
    |> Enum.sort_by(
      &expansion_sort_key(&1, seed_matches, seed_external_ids, seed_reply_targets),
      :desc
    )
  end

  defp expansion_bounds(seed_matches, opts) do
    window_seconds =
      Keyword.get(opts, :expansion_window_seconds, @default_expansion_window_seconds)

    observed_times = Enum.map(seed_matches, & &1.observed_at)
    min_time = Enum.min_by(observed_times, &time_sort_key/1)
    max_time = Enum.max_by(observed_times, &time_sort_key/1)
    since = add_seconds(min_time, -window_seconds)
    until = add_seconds(max_time, window_seconds)

    {
      clamp_since(since, Keyword.get(opts, :since)),
      clamp_until(until, Keyword.get(opts, :until))
    }
  end

  defp clamp_since(value, nil), do: value

  defp clamp_since(%NaiveDateTime{} = value, %NaiveDateTime{} = since),
    do: if(NaiveDateTime.compare(value, since) == :lt, do: since, else: value)

  defp clamp_since(%DateTime{} = value, %DateTime{} = since),
    do: if(DateTime.compare(value, since) == :lt, do: since, else: value)

  defp clamp_since(%DateTime{} = value, %NaiveDateTime{} = since),
    do: clamp_since(value, DateTime.from_naive!(since, "Etc/UTC"))

  defp clamp_since(%NaiveDateTime{} = value, %DateTime{} = since),
    do: clamp_since(DateTime.from_naive!(value, "Etc/UTC"), since)

  defp clamp_until(value, nil), do: value

  defp clamp_until(%NaiveDateTime{} = value, %NaiveDateTime{} = until),
    do: if(NaiveDateTime.compare(value, until) == :gt, do: until, else: value)

  defp clamp_until(%DateTime{} = value, %DateTime{} = until),
    do: if(DateTime.compare(value, until) == :gt, do: until, else: value)

  defp clamp_until(%DateTime{} = value, %NaiveDateTime{} = until),
    do: clamp_until(value, DateTime.from_naive!(until, "Etc/UTC"))

  defp clamp_until(%NaiveDateTime{} = value, %DateTime{} = until),
    do: clamp_until(DateTime.from_naive!(value, "Etc/UTC"), until)

  defp expansion_actor_filter([]), do: dynamic(true)
  defp expansion_actor_filter(actor_ids), do: dynamic([m, _a, _c], m.actor_id in ^actor_ids)

  defp expansion_channel_filter(channel_names) do
    normalized = Enum.map(channel_names, &String.downcase/1)
    dynamic([_m, _a, c], fragment("lower(?)", c.name) in ^normalized)
  end

  defp expansion_match?(candidate, seed_matches, seed_external_ids, seed_reply_targets, opts) do
    nearby_seed?(candidate, seed_matches, opts) or
      MapSet.member?(seed_external_ids, get_in(candidate, [:metadata, "reply_to_external_id"])) or
      MapSet.member?(seed_reply_targets, candidate.external_id)
  end

  defp nearby_seed?(candidate, seed_matches, opts) do
    window_seconds =
      Keyword.get(opts, :expansion_window_seconds, @default_expansion_window_seconds)

    Enum.any?(seed_matches, fn seed ->
      candidate.channel_name == seed.channel_name and
        abs(time_diff_seconds(candidate.observed_at, seed.observed_at)) <= window_seconds
    end)
  end

  defp expansion_sort_key(candidate, seed_matches, seed_external_ids, seed_reply_targets) do
    reply_boost =
      if MapSet.member?(seed_external_ids, get_in(candidate, [:metadata, "reply_to_external_id"])) or
           MapSet.member?(seed_reply_targets, candidate.external_id) do
        1
      else
        0
      end

    nearest_seconds =
      seed_matches
      |> Enum.filter(&(&1.channel_name == candidate.channel_name))
      |> Enum.map(&abs(time_diff_seconds(candidate.observed_at, &1.observed_at)))
      |> Enum.min(fn -> @default_expansion_window_seconds end)

    {-nearest_seconds, reply_boost, candidate.observed_at, candidate.message_id}
  end

  defp seed_message?(seed_matches, candidate) do
    Enum.any?(seed_matches, &(&1.message_id == candidate.message_id))
  end

  defp mark_expanded_match(match) do
    match
    |> Map.put(:similarity, 0.0)
    |> Map.put(:distance, nil)
    |> Map.put(:model, nil)
    |> Map.put(:expanded, true)
  end

  defp normalize_expansion_match(match) do
    match
    |> Map.update!(:message_id, &normalize_identifier/1)
    |> Map.update!(:external_id, &normalize_identifier/1)
  end

  defp add_seconds(%NaiveDateTime{} = value, seconds),
    do: NaiveDateTime.add(value, seconds, :second)

  defp add_seconds(%DateTime{} = value, seconds), do: DateTime.add(value, seconds, :second)

  defp time_sort_key(%NaiveDateTime{} = value), do: NaiveDateTime.to_erl(value)

  defp time_sort_key(%DateTime{} = value),
    do: value |> DateTime.to_naive() |> NaiveDateTime.to_erl()

  defp time_diff_seconds(%NaiveDateTime{} = left, %NaiveDateTime{} = right),
    do: NaiveDateTime.diff(left, right, :second)

  defp time_diff_seconds(%DateTime{} = left, %DateTime{} = right),
    do: DateTime.diff(left, right, :second)

  defp time_diff_seconds(%DateTime{} = left, %NaiveDateTime{} = right),
    do: DateTime.diff(left, DateTime.from_naive!(right, "Etc/UTC"), :second)

  defp time_diff_seconds(%NaiveDateTime{} = left, %DateTime{} = right),
    do: DateTime.diff(DateTime.from_naive!(left, "Etc/UTC"), right, :second)

  defp maybe_add_source(sources, true, source), do: sources ++ [source]
  defp maybe_add_source(sources, false, _source), do: sources

  defp vector_matches({:ok, %{matches: matches}}), do: matches
  defp vector_matches(_result), do: []

  defp lexical_terms(question) do
    question
    |> normalize_question()
    |> String.replace(~r/[^a-z0-9]+/u, " ")
    |> String.split(~r/\s+/u, trim: true)
    |> Enum.reject(&(String.length(&1) < 2))
    |> Enum.reject(&MapSet.member?(@stopwords, &1))
    |> Enum.uniq()
    |> Enum.take(6)
  end

  defp lexical_overlap_count(body, terms) do
    tokens =
      body
      |> normalize_question()
      |> String.replace(~r/[^a-z0-9]+/u, " ")
      |> String.split(~r/\s+/u, trim: true)
      |> MapSet.new()

    Enum.count(terms, &MapSet.member?(tokens, &1))
  end

  defp exact_phrase_bonus(_body, []), do: 0.0

  defp exact_phrase_bonus(body, terms) do
    if String.contains?(normalize_question(body), Enum.join(terms, " ")) do
      0.25
    else
      0.0
    end
  end

  defp normalize_vector_match(match) do
    distance = normalize_distance(match.distance)

    match
    |> Map.update!(:message_id, &normalize_identifier/1)
    |> Map.update!(:external_id, &normalize_identifier/1)
    |> Map.put(:distance, distance)
    |> Map.put(:similarity, 1.0 - distance)
  end

  defp normalize_lexical_match(match) do
    lexical_similarity =
      case match.lexical_similarity do
        %Decimal{} = value -> Decimal.to_float(value)
        value when is_float(value) -> value
        value when is_integer(value) -> value / 1
        _ -> 0.0
      end

    match
    |> Map.update!(:message_id, &normalize_identifier/1)
    |> Map.update!(:external_id, &normalize_identifier/1)
    |> Map.put(:lexical_similarity, lexical_similarity)
  end

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

  defp vector_similarity(nil), do: 0.0
  defp vector_similarity(match), do: Map.get(match, :similarity, 0.0) || 0.0

  defp lexical_similarity(nil), do: 0.0
  defp lexical_similarity(match), do: Map.get(match, :lexical_similarity, 0.0) || 0.0

  defp vector_distance(nil), do: nil
  defp vector_distance(match), do: Map.get(match, :distance)

  defp vector_model(nil), do: nil
  defp vector_model(match), do: Map.get(match, :model)

  defp request_channel_name(opts) do
    Keyword.get(opts, :channel_name) || Keyword.get(opts, :requester_channel_name)
  end

  defp actor_filter([]), do: dynamic(true)
  defp actor_filter(actor_ids), do: dynamic([m, _a, _c], m.actor_id in ^actor_ids)

  defp vector_actor_filter([]), do: dynamic(true)
  defp vector_actor_filter(actor_ids), do: dynamic([_me, m, _a, _c], m.actor_id in ^actor_ids)

  defp channel_filter(nil), do: dynamic(true)

  defp channel_filter(channel_name) do
    normalized = String.downcase(String.trim(channel_name))
    dynamic([_m, _a, c], fragment("lower(?) = ?", c.name, ^normalized))
  end

  defp vector_channel_filter(nil), do: dynamic(true)

  defp vector_channel_filter(channel_name) do
    normalized = String.downcase(String.trim(channel_name))
    dynamic([_me, _m, _a, c], fragment("lower(?) = ?", c.name, ^normalized))
  end

  defp term_filter([]), do: dynamic(false)

  defp term_filter(terms) do
    terms
    |> Enum.map(&"%#{&1}%")
    |> Enum.reduce(dynamic(false), fn pattern, acc ->
      dynamic([m, _a, _c], ^acc or ilike(m.body, ^pattern))
    end)
  end

  defp message_since_filter(nil), do: dynamic(true)

  defp message_since_filter(%NaiveDateTime{} = since) do
    message_since_filter(DateTime.from_naive!(since, "Etc/UTC"))
  end

  defp message_since_filter(%DateTime{} = since) do
    dynamic([m, _a, _c], m.observed_at >= ^since)
  end

  defp vector_message_since_filter(nil), do: dynamic(true)

  defp vector_message_since_filter(%NaiveDateTime{} = since) do
    vector_message_since_filter(DateTime.from_naive!(since, "Etc/UTC"))
  end

  defp vector_message_since_filter(%DateTime{} = since) do
    dynamic([_me, m, _a, _c], m.observed_at >= ^since)
  end

  defp message_until_filter(nil), do: dynamic(true)

  defp message_until_filter(%NaiveDateTime{} = until) do
    message_until_filter(DateTime.from_naive!(until, "Etc/UTC"))
  end

  defp message_until_filter(%DateTime{} = until) do
    dynamic([m, _a, _c], m.observed_at <= ^until)
  end

  defp vector_message_until_filter(nil), do: dynamic(true)

  defp vector_message_until_filter(%NaiveDateTime{} = until) do
    vector_message_until_filter(DateTime.from_naive!(until, "Etc/UTC"))
  end

  defp vector_message_until_filter(%DateTime{} = until) do
    dynamic([_me, m, _a, _c], m.observed_at <= ^until)
  end

  defp normalize_question(question) do
    question
    |> String.trim()
    |> String.downcase()
  end

  defp default_embedding_model do
    Application.get_env(:threadr, Threadr.ML, [])
    |> Keyword.fetch!(:embeddings)
    |> Keyword.fetch!(:model)
  end

  defp embedding_opts(opts), do: EmbeddingProviderOpts.from_prefixed(opts)
end
