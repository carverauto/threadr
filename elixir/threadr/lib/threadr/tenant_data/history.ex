defmodule Threadr.TenantData.History do
  @moduledoc """
  Tenant-scoped chat history queries for analyst-facing timelines.
  """

  import Ecto.Query

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

    {:ok, Enum.map(Repo.all(query), &normalize_map_ids/1)}
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

  defp normalize_id(value) when is_binary(value) do
    if String.valid?(value), do: value, else: Ecto.UUID.load!(value)
  rescue
    ArgumentError -> value
  end

  defp normalize_id(value), do: value
end
