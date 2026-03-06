defmodule Threadr.TenantData.GraphInspector do
  @moduledoc """
  Server-side node inspection for tenant graph exploration.

  The graph client renders from snapshot data, but detailed selection dossiers are
  fetched on demand so the browser does not need to derive or carry a second
  graph model.
  """

  import Ecto.Query

  alias Threadr.Repo
  alias Threadr.TenantData.Graph

  @message_limit 8
  @relationship_limit 8

  def describe_node(node_id, node_kind, tenant_schema)
      when is_binary(node_id) and is_binary(node_kind) and is_binary(tenant_schema) do
    case node_kind do
      "message" -> describe_message(node_id, tenant_schema)
      "actor" -> describe_actor(node_id, tenant_schema)
      "channel" -> describe_channel(node_id, tenant_schema)
      other -> {:error, {:unsupported_node_kind, other}}
    end
  end

  defp describe_message(message_id, tenant_schema) do
    with {:ok, message} <- fetch_message(tenant_schema, message_id),
         {:ok, neighborhood} <- Graph.neighborhood([message_id], tenant_schema, graph_message_limit: 8) do
      {:ok,
       %{
         type: "message",
         focal: message,
         summary: %{
           message_count: 1,
           related_actor_count: length(neighborhood.actors),
           related_relationship_count: length(neighborhood.relationships)
         },
         recent_messages: [message],
         neighborhood: neighborhood_payload(neighborhood)
       }}
    end
  end

  defp describe_actor(actor_id, tenant_schema) do
    with {:ok, actor} <- fetch_actor(tenant_schema, actor_id),
         message_ids <- fetch_actor_message_ids(tenant_schema, actor_id),
         {:ok, neighborhood} <- Graph.neighborhood(message_ids, tenant_schema, graph_message_limit: 8) do
      {:ok,
       %{
         type: "actor",
         focal: actor,
         summary: %{
           message_count: length(message_ids),
           channel_count: length(top_channels_for_actor(tenant_schema, actor_id)),
           related_actor_count: length(neighborhood.actors),
           related_relationship_count: length(neighborhood.relationships)
         },
         recent_messages: recent_messages_for_actor(tenant_schema, actor_id),
         top_channels: top_channels_for_actor(tenant_schema, actor_id),
         top_relationships: top_relationships_for_actor(tenant_schema, actor_id),
         neighborhood: neighborhood_payload(neighborhood)
       }}
    end
  end

  defp describe_channel(channel_id, tenant_schema) do
    with {:ok, channel} <- fetch_channel(tenant_schema, channel_id),
         message_ids <- fetch_channel_message_ids(tenant_schema, channel_id),
         {:ok, neighborhood} <- Graph.neighborhood(message_ids, tenant_schema, graph_message_limit: 8) do
      {:ok,
       %{
         type: "channel",
         focal: channel,
         summary: %{
           message_count: length(message_ids),
           actor_count: length(top_actors_for_channel(tenant_schema, channel_id)),
           related_actor_count: length(neighborhood.actors),
           related_relationship_count: length(neighborhood.relationships)
         },
         recent_messages: recent_messages_for_channel(tenant_schema, channel_id),
         top_actors: top_actors_for_channel(tenant_schema, channel_id),
         neighborhood: neighborhood_payload(neighborhood)
       }}
    end
  end

  defp fetch_message(tenant_schema, message_id) do
    Repo.one(
      from(m in "messages",
        prefix: ^tenant_schema,
        join: a in "actors",
        on: a.id == m.actor_id,
        prefix: ^tenant_schema,
        join: c in "channels",
        on: c.id == m.channel_id,
        prefix: ^tenant_schema,
        where: m.id == type(^message_id, :binary_id),
        select: %{
          id: m.id,
          external_id: m.external_id,
          body: m.body,
          observed_at: m.observed_at,
          actor_id: m.actor_id,
          actor_handle: a.handle,
          actor_display_name: a.display_name,
          channel_id: c.id,
          channel_name: c.name
        }
      )
    )
    |> case do
      nil -> {:error, :not_found}
      message -> {:ok, normalize_map_ids(message)}
    end
  end

  defp fetch_actor(tenant_schema, actor_id) do
    Repo.one(
      from(a in "actors",
        prefix: ^tenant_schema,
        where: a.id == type(^actor_id, :binary_id),
        select: %{
          id: a.id,
          platform: a.platform,
          handle: a.handle,
          display_name: a.display_name,
          external_id: a.external_id,
          last_seen_at: a.last_seen_at
        }
      )
    )
    |> case do
      nil -> {:error, :not_found}
      actor -> {:ok, normalize_map_ids(actor)}
    end
  end

  defp fetch_channel(tenant_schema, channel_id) do
    Repo.one(
      from(c in "channels",
        prefix: ^tenant_schema,
        where: c.id == type(^channel_id, :binary_id),
        select: %{
          id: c.id,
          platform: c.platform,
          name: c.name,
          external_id: c.external_id
        }
      )
    )
    |> case do
      nil -> {:error, :not_found}
      channel -> {:ok, normalize_map_ids(channel)}
    end
  end

  defp fetch_actor_message_ids(tenant_schema, actor_id) do
    Repo.all(
      from(m in "messages",
        prefix: ^tenant_schema,
        where: m.actor_id == type(^actor_id, :binary_id),
        order_by: [desc: m.observed_at, desc: m.inserted_at],
        limit: @message_limit,
        select: m.id
      )
    )
    |> Enum.map(&normalize_id/1)
  end

  defp fetch_channel_message_ids(tenant_schema, channel_id) do
    Repo.all(
      from(m in "messages",
        prefix: ^tenant_schema,
        where: m.channel_id == type(^channel_id, :binary_id),
        order_by: [desc: m.observed_at, desc: m.inserted_at],
        limit: @message_limit,
        select: m.id
      )
    )
    |> Enum.map(&normalize_id/1)
  end

  defp recent_messages_for_actor(tenant_schema, actor_id) do
    Repo.all(
      from(m in "messages",
        prefix: ^tenant_schema,
        join: c in "channels",
        on: c.id == m.channel_id,
        prefix: ^tenant_schema,
        where: m.actor_id == type(^actor_id, :binary_id),
        order_by: [desc: m.observed_at, desc: m.inserted_at],
        limit: @message_limit,
        select: %{
          id: m.id,
          external_id: m.external_id,
          body: m.body,
          observed_at: m.observed_at,
          channel_id: c.id,
          channel_name: c.name
        }
      )
    )
    |> Enum.map(&normalize_map_ids/1)
    |> Enum.map(&stringify_timestamps/1)
  end

  defp recent_messages_for_channel(tenant_schema, channel_id) do
    Repo.all(
      from(m in "messages",
        prefix: ^tenant_schema,
        join: a in "actors",
        on: a.id == m.actor_id,
        prefix: ^tenant_schema,
        where: m.channel_id == type(^channel_id, :binary_id),
        order_by: [desc: m.observed_at, desc: m.inserted_at],
        limit: @message_limit,
        select: %{
          id: m.id,
          external_id: m.external_id,
          body: m.body,
          observed_at: m.observed_at,
          actor_id: a.id,
          actor_handle: a.handle,
          actor_display_name: a.display_name
        }
      )
    )
    |> Enum.map(&normalize_map_ids/1)
    |> Enum.map(&stringify_timestamps/1)
  end

  defp top_channels_for_actor(tenant_schema, actor_id) do
    Repo.all(
      from(m in "messages",
        prefix: ^tenant_schema,
        join: c in "channels",
        on: c.id == m.channel_id,
        prefix: ^tenant_schema,
        where: m.actor_id == type(^actor_id, :binary_id),
        group_by: [c.id, c.name],
        order_by: [desc: count(m.id), asc: c.name],
        limit: 6,
        select: %{
          channel_id: c.id,
          channel_name: c.name,
          message_count: count(m.id)
        }
      )
    )
    |> Enum.map(&normalize_map_ids/1)
  end

  defp top_actors_for_channel(tenant_schema, channel_id) do
    Repo.all(
      from(m in "messages",
        prefix: ^tenant_schema,
        join: a in "actors",
        on: a.id == m.actor_id,
        prefix: ^tenant_schema,
        where: m.channel_id == type(^channel_id, :binary_id),
        group_by: [a.id, a.handle, a.display_name],
        order_by: [desc: count(m.id), asc: a.handle],
        limit: 6,
        select: %{
          actor_id: a.id,
          actor_handle: a.handle,
          actor_display_name: a.display_name,
          message_count: count(m.id)
        }
      )
    )
    |> Enum.map(&normalize_map_ids/1)
  end

  defp top_relationships_for_actor(tenant_schema, actor_id) do
    Repo.all(
      from(r in "relationships",
        prefix: ^tenant_schema,
        join: from_actor in "actors",
        on: from_actor.id == r.from_actor_id,
        prefix: ^tenant_schema,
        join: to_actor in "actors",
        on: to_actor.id == r.to_actor_id,
        prefix: ^tenant_schema,
        where: r.from_actor_id == type(^actor_id, :binary_id) or r.to_actor_id == type(^actor_id, :binary_id),
        order_by: [desc: r.weight, asc: r.relationship_type],
        limit: @relationship_limit,
        select: %{
          relationship_type: r.relationship_type,
          weight: r.weight,
          from_actor_id: from_actor.id,
          from_actor_handle: from_actor.handle,
          to_actor_id: to_actor.id,
          to_actor_handle: to_actor.handle,
          source_message_id: r.source_message_id
        }
      )
    )
    |> Enum.map(&normalize_map_ids/1)
  end

  defp neighborhood_payload(neighborhood) do
    %{
      actors: Enum.map(neighborhood.actors, &normalize_map_ids/1),
      relationships:
        Enum.map(neighborhood.relationships, fn relationship ->
          relationship
          |> normalize_map_ids()
          |> stringify_timestamps()
        end),
      messages:
        Enum.map(neighborhood.messages, fn message ->
          message
          |> normalize_map_ids()
          |> stringify_timestamps()
        end)
    }
  end

  defp normalize_map_ids(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {key, normalize_id(value)} end)
  end

  defp normalize_id(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} ->
        uuid

      :error ->
        case Ecto.UUID.load(value) do
          {:ok, uuid} -> uuid
          :error -> value
        end
    end
  end

  defp normalize_id(value), do: value

  defp stringify_timestamps(map) when is_map(map) do
    Map.new(map, fn
      {key, %DateTime{} = value} -> {key, DateTime.to_iso8601(value)}
      {key, %NaiveDateTime{} = value} -> {key, NaiveDateTime.to_iso8601(value)}
      {key, value} -> {key, value}
    end)
  end
end
