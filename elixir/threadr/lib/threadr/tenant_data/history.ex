defmodule Threadr.TenantData.History do
  @moduledoc """
  Tenant-scoped chat history queries for analyst-facing timelines.
  """

  import Ecto.Query

  alias Threadr.CompareDelta
  alias Threadr.Repo

  @default_limit 50
  @max_limit 200

  def list_messages(tenant_schema, opts \\ []) when is_binary(tenant_schema) do
    limit =
      opts
      |> Keyword.get(:limit, @default_limit)
      |> normalize_limit()

    query =
      from(m in "messages",
        prefix: ^tenant_schema,
        join: a in "actors",
        on: a.id == m.actor_id,
        prefix: ^tenant_schema,
        join: c in "channels",
        on: c.id == m.channel_id,
        prefix: ^tenant_schema,
        order_by: [desc: m.observed_at, desc: m.inserted_at],
        limit: ^limit,
        select: %{
          id: m.id,
          external_id: m.external_id,
          body: m.body,
          observed_at: m.observed_at,
          metadata: m.metadata,
          actor_id: a.id,
          actor_handle: a.handle,
          actor_display_name: a.display_name,
          channel_id: c.id,
          channel_name: c.name,
          platform: a.platform
        }
      )
      |> maybe_filter_query(Keyword.get(opts, :query))
      |> maybe_filter_actor(Keyword.get(opts, :actor_handle))
      |> maybe_filter_channel(Keyword.get(opts, :channel_name))
      |> maybe_filter_since(Keyword.get(opts, :since))
      |> maybe_filter_until(Keyword.get(opts, :until))
      |> maybe_filter_extraction_message_ids(
        tenant_schema,
        entity_name: Keyword.get(opts, :entity_name),
        entity_type: Keyword.get(opts, :entity_type),
        fact_type: Keyword.get(opts, :fact_type)
      )

    messages =
      query
      |> Repo.all()
      |> Enum.map(&normalize_map_ids/1)
      |> enrich_with_extractions(tenant_schema)

    {:ok, %{messages: messages, facts_over_time: facts_over_time(messages)}}
  end

  def compare_windows(tenant_schema, baseline_opts, comparison_opts)
      when is_binary(tenant_schema) and is_list(baseline_opts) and is_list(comparison_opts) do
    with {:ok, baseline} <- list_messages(tenant_schema, baseline_opts),
         {:ok, comparison} <- list_messages(tenant_schema, comparison_opts),
         delta <-
           CompareDelta.build(
             message_entities(baseline.messages),
             message_entities(comparison.messages),
             message_facts(baseline.messages),
             message_facts(comparison.messages)
           ) do
      {:ok,
       %{
         baseline: baseline,
         comparison: comparison,
         entity_delta: delta.entity_delta,
         fact_delta: delta.fact_delta,
         context: build_comparison_context(baseline, comparison, baseline_opts, comparison_opts)
       }}
    end
  end

  defp maybe_filter_query(query, nil), do: query
  defp maybe_filter_query(query, ""), do: query

  defp maybe_filter_query(query, value) when is_binary(value) do
    pattern = "%" <> String.replace(value, "%", "\\%") <> "%"
    where(query, [m, _a, _c], ilike(m.body, ^pattern))
  end

  defp maybe_filter_actor(query, nil), do: query
  defp maybe_filter_actor(query, ""), do: query

  defp maybe_filter_actor(query, handle) when is_binary(handle) do
    where(query, [_m, a, _c], a.handle == ^handle)
  end

  defp maybe_filter_channel(query, nil), do: query
  defp maybe_filter_channel(query, ""), do: query

  defp maybe_filter_channel(query, name) when is_binary(name) do
    where(query, [_m, _a, c], c.name == ^name)
  end

  defp maybe_filter_extraction_message_ids(query, tenant_schema, opts) do
    query
    |> maybe_filter_by_entity_name(tenant_schema, Keyword.get(opts, :entity_name))
    |> maybe_filter_by_entity_type(tenant_schema, Keyword.get(opts, :entity_type))
    |> maybe_filter_by_fact_type(tenant_schema, Keyword.get(opts, :fact_type))
  end

  defp maybe_filter_by_entity_name(query, _tenant_schema, nil), do: query
  defp maybe_filter_by_entity_name(query, _tenant_schema, ""), do: query

  defp maybe_filter_by_entity_name(query, tenant_schema, value) when is_binary(value) do
    pattern = "%" <> String.replace(String.trim(value), "%", "\\%") <> "%"

    source_message_ids =
      Repo.all(
        from(e in "extracted_entities",
          prefix: ^tenant_schema,
          where: ilike(e.name, ^pattern) or ilike(coalesce(e.canonical_name, ""), ^pattern),
          select: e.source_message_id
        )
      )

    where(query, [m, _a, _c], m.id in ^source_message_ids)
  end

  defp maybe_filter_by_entity_type(query, _tenant_schema, nil), do: query
  defp maybe_filter_by_entity_type(query, _tenant_schema, ""), do: query

  defp maybe_filter_by_entity_type(query, tenant_schema, value) when is_binary(value) do
    source_message_ids =
      Repo.all(
        from(e in "extracted_entities",
          prefix: ^tenant_schema,
          where: fragment("lower(?)", e.entity_type) == fragment("lower(?)", ^String.trim(value)),
          select: e.source_message_id
        )
      )

    where(query, [m, _a, _c], m.id in ^source_message_ids)
  end

  defp maybe_filter_by_fact_type(query, _tenant_schema, nil), do: query
  defp maybe_filter_by_fact_type(query, _tenant_schema, ""), do: query

  defp maybe_filter_by_fact_type(query, tenant_schema, value) when is_binary(value) do
    source_message_ids =
      Repo.all(
        from(f in "extracted_facts",
          prefix: ^tenant_schema,
          where: fragment("lower(?)", f.fact_type) == fragment("lower(?)", ^String.trim(value)),
          select: f.source_message_id
        )
      )

    where(query, [m, _a, _c], m.id in ^source_message_ids)
  end

  defp maybe_filter_since(query, nil), do: query

  defp maybe_filter_since(query, %NaiveDateTime{} = since) do
    where(query, [m, _a, _c], m.observed_at >= ^since)
  end

  defp maybe_filter_since(query, %DateTime{} = since) do
    where(query, [m, _a, _c], m.observed_at >= ^since)
  end

  defp maybe_filter_until(query, nil), do: query

  defp maybe_filter_until(query, %NaiveDateTime{} = until) do
    where(query, [m, _a, _c], m.observed_at <= ^until)
  end

  defp maybe_filter_until(query, %DateTime{} = until) do
    where(query, [m, _a, _c], m.observed_at <= ^until)
  end

  defp normalize_limit(limit) when is_integer(limit), do: limit |> min(@max_limit) |> max(1)

  defp normalize_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {parsed, _} -> normalize_limit(parsed)
      :error -> @default_limit
    end
  end

  defp normalize_limit(_limit), do: @default_limit

  defp normalize_map_ids(map) do
    map
    |> Enum.map(fn {key, value} -> {key, normalize_id(value)} end)
    |> Map.new()
  end

  defp enrich_with_extractions(messages, tenant_schema) do
    message_ids = Enum.map(messages, & &1.id)

    entities_by_message = fetch_entities_by_message(tenant_schema, message_ids)
    facts_by_message = fetch_facts_by_message(tenant_schema, message_ids)

    Enum.map(messages, fn message ->
      message
      |> Map.put(:extracted_entities, Map.get(entities_by_message, message.id, []))
      |> Map.put(:extracted_facts, Map.get(facts_by_message, message.id, []))
    end)
  end

  defp fetch_entities_by_message(_tenant_schema, []), do: %{}

  defp fetch_entities_by_message(tenant_schema, message_ids) do
    source_message_ids = Enum.map(message_ids, &dump_uuid!/1)

    Repo.all(
      from(e in "extracted_entities",
        prefix: ^tenant_schema,
        where: e.source_message_id in ^source_message_ids,
        order_by: [desc: e.confidence, asc: e.name],
        select: %{
          id: e.id,
          entity_type: e.entity_type,
          name: e.name,
          canonical_name: e.canonical_name,
          confidence: e.confidence,
          metadata: e.metadata,
          source_message_id: e.source_message_id
        }
      )
    )
    |> Enum.map(&normalize_map_ids/1)
    |> Enum.group_by(& &1.source_message_id)
  end

  defp fetch_facts_by_message(_tenant_schema, []), do: %{}

  defp fetch_facts_by_message(tenant_schema, message_ids) do
    source_message_ids = Enum.map(message_ids, &dump_uuid!/1)

    Repo.all(
      from(f in "extracted_facts",
        prefix: ^tenant_schema,
        where: f.source_message_id in ^source_message_ids,
        order_by: [desc: f.confidence, asc: f.fact_type],
        select: %{
          id: f.id,
          fact_type: f.fact_type,
          subject: f.subject,
          predicate: f.predicate,
          object: f.object,
          confidence: f.confidence,
          valid_at: f.valid_at,
          metadata: f.metadata,
          source_message_id: f.source_message_id
        }
      )
    )
    |> Enum.map(&normalize_map_ids/1)
    |> Enum.map(&stringify_timestamps/1)
    |> Enum.group_by(& &1.source_message_id)
  end

  defp normalize_id(value) when is_binary(value) do
    if String.valid?(value), do: value, else: Ecto.UUID.load!(value)
  rescue
    ArgumentError -> value
  end

  defp normalize_id(value), do: value

  defp dump_uuid!(value) when is_binary(value), do: Ecto.UUID.dump!(value)
  defp dump_uuid!(value), do: value

  defp stringify_timestamps(map) when is_map(map) do
    Map.new(map, fn
      {key, %DateTime{} = value} -> {key, DateTime.to_iso8601(value)}
      {key, %NaiveDateTime{} = value} -> {key, NaiveDateTime.to_iso8601(value)}
      {key, value} -> {key, value}
    end)
  end

  defp facts_over_time(messages) do
    messages
    |> Enum.flat_map(fn message ->
      observed_at = Map.get(message, :observed_at)

      Enum.map(Map.get(message, :extracted_facts, []), fn fact ->
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
        |> Enum.max_by(fn {_key, values} -> length(values) end, fn -> {{"", "", ""}, []} end)

      %{
        day: day,
        fact_count: length(facts),
        fact_type_count: facts |> Enum.map(& &1.fact_type) |> Enum.uniq() |> length(),
        top_fact: compact_fact(subject, predicate, object),
        top_fact_count: length(grouped)
      }
    end)
    |> Enum.sort_by(& &1.day, {:desc, Date})
  end

  defp build_comparison_context(baseline, comparison, baseline_opts, comparison_opts) do
    [
      "Baseline Window: #{window_label(baseline_opts)}",
      listing_context(baseline),
      "",
      "Comparison Window: #{window_label(comparison_opts)}",
      listing_context(comparison)
    ]
    |> Enum.join("\n")
  end

  defp listing_context(%{messages: messages, facts_over_time: facts_over_time}) do
    [
      "Messages:",
      message_context(messages),
      "",
      "Facts Over Time:",
      facts_context(facts_over_time)
    ]
    |> Enum.join("\n")
  end

  defp message_entities(messages) do
    Enum.flat_map(messages, &Map.get(&1, :extracted_entities, []))
  end

  defp message_facts(messages) do
    Enum.flat_map(messages, &Map.get(&1, :extracted_facts, []))
  end

  defp message_context([]), do: "- none"

  defp message_context(messages) do
    messages
    |> Enum.take(8)
    |> Enum.map(fn message ->
      observed_at = message[:observed_at] || message["observed_at"]
      actor_handle = message[:actor_handle] || message["actor_handle"]
      channel_name = message[:channel_name] || message["channel_name"]
      body = message[:body] || message["body"]
      "- #{format_window_value(observed_at)} ##{channel_name} #{actor_handle}: #{body}"
    end)
    |> Enum.join("\n")
  end

  defp facts_context([]), do: "- none"

  defp facts_context(entries) do
    entries
    |> Enum.take(8)
    |> Enum.map(fn entry ->
      "- #{Date.to_iso8601(entry.day)}: #{entry.fact_count} facts, top=#{entry.top_fact}"
    end)
    |> Enum.join("\n")
  end

  defp window_label(opts) do
    "#{format_window_value(Keyword.get(opts, :since))} -> #{format_window_value(Keyword.get(opts, :until))}"
  end

  defp format_window_value(nil), do: "beginning/end"
  defp format_window_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp format_window_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp format_window_value(value) when is_binary(value), do: value
  defp format_window_value(value), do: inspect(value)

  defp fact_day(%{valid_at: valid_at}, observed_at) when is_binary(valid_at) do
    case Date.from_iso8601(String.slice(valid_at, 0, 10)) do
      {:ok, date} -> date
      _ -> observed_day(observed_at)
    end
  end

  defp fact_day(_fact, observed_at), do: observed_day(observed_at)

  defp observed_day(%DateTime{} = observed_at), do: DateTime.to_date(observed_at)
  defp observed_day(%NaiveDateTime{} = observed_at), do: NaiveDateTime.to_date(observed_at)

  defp observed_day(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} -> NaiveDateTime.to_date(naive)
      _ -> ~D[1970-01-01]
    end
  end

  defp observed_day(_value), do: ~D[1970-01-01]

  defp compact_fact(subject, predicate, object) do
    [subject, predicate, object]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end
end
