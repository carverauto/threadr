defmodule Threadr.TenantData.Graph do
  @moduledoc """
  Apache AGE-backed tenant graph projection and inference helpers.
  """

  alias Threadr.Repo
  alias Threadr.TenantData.{Actor, Channel, Message, Relationship}

  @vertex_labels ~w(Actor Channel Message)
  @edge_labels ~w(SENT IN_CHANNEL MENTIONS RELATES_TO)

  def graph_name(tenant_schema) when is_binary(tenant_schema) do
    hash =
      :crypto.hash(:sha256, tenant_schema)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 12)

    base =
      tenant_schema
      |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
      |> String.slice(0, 40)

    "tg_#{base}_#{hash}"
    |> String.slice(0, 63)
  end

  def sync_message(
        %Message{} = message,
        %Actor{} = actor,
        %Channel{} = channel,
        mentioned_actors,
        tenant_schema
      )
      when is_list(mentioned_actors) do
    with_age_session(fn ->
      graph_name = graph_name(tenant_schema)

      with :ok <- ensure_graph(graph_name),
           :ok <- upsert_actor_vertex(graph_name, actor),
           :ok <- upsert_channel_vertex(graph_name, channel),
           :ok <- upsert_message_vertex(graph_name, message),
           :ok <-
             upsert_structural_edge(
               graph_name,
               "SENT",
               "Actor",
               actor.id,
               "Message",
               message.id,
               %{
                 "message_id" => message.id,
                 "observed_at" => iso8601(message.observed_at)
               }
             ),
           :ok <-
             upsert_structural_edge(
               graph_name,
               "IN_CHANNEL",
               "Message",
               message.id,
               "Channel",
               channel.id,
               %{
                 "message_id" => message.id,
                 "observed_at" => iso8601(message.observed_at)
               }
             ) do
        Enum.reduce_while(mentioned_actors, :ok, fn mentioned_actor, :ok ->
          with :ok <- upsert_actor_vertex(graph_name, mentioned_actor),
               :ok <-
                 upsert_structural_edge(
                   graph_name,
                   "MENTIONS",
                   "Message",
                   message.id,
                   "Actor",
                   mentioned_actor.id,
                   %{
                     "message_id" => message.id,
                     "observed_at" => iso8601(message.observed_at)
                   }
                 ) do
            {:cont, :ok}
          else
            error -> {:halt, error}
          end
        end)
      end
    end)
  end

  def sync_relationships(relationships, tenant_schema) when is_list(relationships) do
    with_age_session(fn ->
      graph_name = graph_name(tenant_schema)

      with :ok <- ensure_graph(graph_name) do
        relationships
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(& &1.id)
        |> Enum.reduce_while(:ok, fn relationship, :ok ->
          case sync_relationship(relationship, graph_name) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
        end)
      end
    end)
  end

  def infer_co_mentions(message_id, tenant_schema)
      when is_binary(message_id) and is_binary(tenant_schema) do
    with_age_session(fn ->
      graph_name = graph_name(tenant_schema)

      with :ok <- ensure_graph(graph_name),
           {:ok, %{rows: rows}} <- Repo.query(co_mentions_sql(graph_name), [message_id]) do
        {:ok, Enum.map(rows, fn [from_actor_id, to_actor_id] -> {from_actor_id, to_actor_id} end)}
      end
    end)
  end

  def neighborhood(message_ids, tenant_schema, opts \\ [])
      when is_list(message_ids) and is_binary(tenant_schema) do
    with_age_session(fn ->
      graph_name = graph_name(tenant_schema)
      related_limit = Keyword.get(opts, :graph_message_limit, 5)

      with :ok <- ensure_graph(graph_name),
           {:ok, actors} <- fetch_neighbor_actors(graph_name, message_ids),
           {:ok, relationships} <- fetch_actor_relationships(graph_name, actors),
           {:ok, messages} <-
             fetch_related_messages(graph_name, actors, message_ids, related_limit) do
        {:ok,
         %{
           actors: actors,
           relationships: relationships,
           messages: messages
         }}
      end
    end)
  end

  defp sync_relationship(%Relationship{} = relationship, graph_name) do
    upsert_relationship_edge(graph_name, relationship)
  end

  defp ensure_graph(graph_name) do
    with :ok <- ensure_graph_record(graph_name) do
      Enum.reduce_while(@vertex_labels ++ @edge_labels, :ok, fn label, :ok ->
        case ensure_label(graph_name, label) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end
  end

  defp ensure_graph_record(graph_name) do
    case Repo.query("SELECT 1 FROM ag_catalog.ag_graph WHERE name = $1 LIMIT 1", [graph_name]) do
      {:ok, %{rows: [[1]]}} ->
        :ok

      {:ok, %{rows: []}} ->
        Repo.query(create_graph_sql(graph_name))
        |> normalize_repo_result()

      error ->
        error
    end
  end

  defp ensure_label(graph_name, label_name) do
    case Repo.query(
           """
           SELECT 1
           FROM ag_catalog.ag_label
           WHERE graph = (SELECT graphid FROM ag_catalog.ag_graph WHERE name = $1)
             AND name = $2
           LIMIT 1
           """,
           [graph_name, label_name]
         ) do
      {:ok, %{rows: [[1]]}} ->
        :ok

      {:ok, %{rows: []}} ->
        Repo.query(create_label_sql(graph_name, label_name))
        |> normalize_repo_result()

      error ->
        error
    end
  end

  defp upsert_actor_vertex(graph_name, %Actor{} = actor) do
    upsert_vertex(
      graph_name,
      "Actor",
      actor.id,
      %{
        "id" => actor.id,
        "platform" => actor.platform,
        "handle" => actor.handle,
        "display_name" => actor.display_name,
        "external_id" => actor.external_id
      }
    )
  end

  defp upsert_channel_vertex(graph_name, %Channel{} = channel) do
    upsert_vertex(
      graph_name,
      "Channel",
      channel.id,
      %{
        "id" => channel.id,
        "platform" => channel.platform,
        "name" => channel.name,
        "external_id" => channel.external_id
      }
    )
  end

  defp upsert_message_vertex(graph_name, %Message{} = message) do
    upsert_vertex(
      graph_name,
      "Message",
      message.id,
      %{
        "id" => message.id,
        "external_id" => message.external_id,
        "body" => message.body,
        "observed_at" => iso8601(message.observed_at)
      }
    )
  end

  defp upsert_vertex(graph_name, label, vertex_key, properties) do
    case Repo.query(find_vertex_sql(graph_name, label), [to_string(vertex_key)]) do
      {:ok, %{rows: [[vertex_id]]}} ->
        {map_sql, params, next_index} = agtype_build_map_sql(properties, 1)

        Repo.query(
          """
          UPDATE #{qualified_table(graph_name, label)}
          SET properties = #{map_sql}
          WHERE id::text = $#{next_index}
          """,
          params ++ [vertex_id]
        )
        |> normalize_repo_result()

      {:ok, %{rows: []}} ->
        {map_sql, params, _next_index} = agtype_build_map_sql(properties, 1)

        Repo.query(
          """
          INSERT INTO #{qualified_table(graph_name, label)} (properties)
          VALUES (#{map_sql})
          """,
          params
        )
        |> normalize_repo_result()

      error ->
        error
    end
  end

  defp upsert_structural_edge(
         graph_name,
         edge_label,
         start_label,
         start_key,
         end_label,
         end_key,
         properties
       ) do
    case Repo.query(
           find_structural_edge_sql(graph_name, edge_label, start_label, end_label),
           [to_string(start_key), to_string(end_key), Map.fetch!(properties, "message_id")]
         ) do
      {:ok, %{rows: [[edge_id]]}} ->
        {map_sql, params, next_index} = agtype_build_map_sql(properties, 1)

        Repo.query(
          """
          UPDATE #{qualified_table(graph_name, edge_label)}
          SET properties = #{map_sql}
          WHERE id::text = $#{next_index}
          """,
          params ++ [edge_id]
        )
        |> normalize_repo_result()

      {:ok, %{rows: []}} ->
        {map_sql, params, _next_index} = agtype_build_map_sql(properties, 3)

        Repo.query(
          insert_edge_sql(graph_name, edge_label, start_label, end_label, map_sql),
          [to_string(start_key), to_string(end_key)] ++ params
        )
        |> normalize_repo_result()

      error ->
        error
    end
  end

  defp upsert_relationship_edge(graph_name, %Relationship{} = relationship) do
    properties = %{
      "relationship_id" => relationship.id,
      "relationship_type" => relationship.relationship_type,
      "weight" => relationship.weight,
      "first_seen_at" => iso8601(relationship.first_seen_at),
      "last_seen_at" => iso8601(relationship.last_seen_at),
      "source_message_id" => relationship.source_message_id
    }

    case Repo.query(find_relationship_edge_sql(graph_name), [
           to_string(relationship.from_actor_id),
           to_string(relationship.to_actor_id),
           relationship.relationship_type
         ]) do
      {:ok, %{rows: [[edge_id]]}} ->
        {map_sql, params, next_index} = agtype_build_map_sql(properties, 1)

        Repo.query(
          """
          UPDATE #{qualified_table(graph_name, "RELATES_TO")}
          SET properties = #{map_sql}
          WHERE id::text = $#{next_index}
          """,
          params ++ [edge_id]
        )
        |> normalize_repo_result()

      {:ok, %{rows: []}} ->
        {map_sql, params, _next_index} = agtype_build_map_sql(properties, 3)

        Repo.query(
          insert_edge_sql(graph_name, "RELATES_TO", "Actor", "Actor", map_sql),
          [to_string(relationship.from_actor_id), to_string(relationship.to_actor_id)] ++ params
        )
        |> normalize_repo_result()

      error ->
        error
    end
  end

  defp find_vertex_sql(graph_name, label) do
    """
    SELECT id::text
    FROM #{qualified_table(graph_name, label)}
    WHERE ag_catalog.agtype_object_field_text(properties, 'id') = $1
    LIMIT 1
    """
  end

  defp find_structural_edge_sql(graph_name, edge_label, start_label, end_label) do
    """
    SELECT e.id::text
    FROM #{qualified_table(graph_name, edge_label)} e
    JOIN #{qualified_table(graph_name, start_label)} s ON s.id::text = e.start_id::text
    JOIN #{qualified_table(graph_name, end_label)} t ON t.id::text = e.end_id::text
    WHERE ag_catalog.agtype_object_field_text(s.properties, 'id') = $1
      AND ag_catalog.agtype_object_field_text(t.properties, 'id') = $2
      AND ag_catalog.agtype_object_field_text(e.properties, 'message_id') = $3
    LIMIT 1
    """
  end

  defp find_relationship_edge_sql(graph_name) do
    """
    SELECT e.id::text
    FROM #{qualified_table(graph_name, "RELATES_TO")} e
    JOIN #{qualified_table(graph_name, "Actor")} s ON s.id::text = e.start_id::text
    JOIN #{qualified_table(graph_name, "Actor")} t ON t.id::text = e.end_id::text
    WHERE ag_catalog.agtype_object_field_text(s.properties, 'id') = $1
      AND ag_catalog.agtype_object_field_text(t.properties, 'id') = $2
      AND ag_catalog.agtype_object_field_text(e.properties, 'relationship_type') = $3
    LIMIT 1
    """
  end

  defp insert_edge_sql(graph_name, edge_label, start_label, end_label, properties_sql) do
    """
    INSERT INTO #{qualified_table(graph_name, edge_label)} (start_id, end_id, properties)
    SELECT s.id, t.id, #{properties_sql}
    FROM #{qualified_table(graph_name, start_label)} s
    CROSS JOIN #{qualified_table(graph_name, end_label)} t
    WHERE ag_catalog.agtype_object_field_text(s.properties, 'id') = $1
      AND ag_catalog.agtype_object_field_text(t.properties, 'id') = $2
    """
  end

  defp co_mentions_sql(graph_name) do
    """
    SELECT
      LEAST(
        ag_catalog.agtype_object_field_text(a1.properties, 'id'),
        ag_catalog.agtype_object_field_text(a2.properties, 'id')
      ) AS from_actor_id,
      GREATEST(
        ag_catalog.agtype_object_field_text(a1.properties, 'id'),
        ag_catalog.agtype_object_field_text(a2.properties, 'id')
      ) AS to_actor_id
    FROM #{qualified_table(graph_name, "MENTIONS")} e1
    JOIN #{qualified_table(graph_name, "MENTIONS")} e2
      ON e1.start_id::text = e2.start_id::text
     AND e1.id::text <> e2.id::text
    JOIN #{qualified_table(graph_name, "Actor")} a1 ON a1.id::text = e1.end_id::text
    JOIN #{qualified_table(graph_name, "Actor")} a2 ON a2.id::text = e2.end_id::text
    WHERE ag_catalog.agtype_object_field_text(e1.properties, 'message_id') = $1
      AND ag_catalog.agtype_object_field_text(e2.properties, 'message_id') = $1
      AND ag_catalog.agtype_object_field_text(a1.properties, 'id') <
          ag_catalog.agtype_object_field_text(a2.properties, 'id')
    GROUP BY 1, 2
    ORDER BY 1, 2
    """
  end

  defp fetch_neighbor_actors(graph_name, message_ids) do
    Repo.query(neighbor_actors_sql(graph_name), [message_ids])
    |> case do
      {:ok, %{rows: rows}} ->
        {:ok,
         Enum.map(rows, fn [actor_id, handle, display_name, role] ->
           %{
             actor_id: actor_id,
             handle: handle,
             display_name: display_name,
             role: role
           }
         end)}

      error ->
        error
    end
  end

  defp fetch_actor_relationships(_graph_name, []), do: {:ok, []}

  defp fetch_actor_relationships(graph_name, actors) do
    actor_ids = Enum.map(actors, & &1.actor_id)

    Repo.query(actor_relationships_sql(graph_name), [actor_ids])
    |> case do
      {:ok, %{rows: rows}} ->
        {:ok,
         Enum.map(rows, fn [
                             from_actor_id,
                             from_actor_handle,
                             to_actor_id,
                             to_actor_handle,
                             relationship_type,
                             weight,
                             source_message_id
                           ] ->
           %{
             from_actor_id: from_actor_id,
             from_actor_handle: from_actor_handle,
             to_actor_id: to_actor_id,
             to_actor_handle: to_actor_handle,
             relationship_type: relationship_type,
             weight: parse_integer(weight),
             source_message_id: source_message_id
           }
         end)}

      error ->
        error
    end
  end

  defp fetch_related_messages(_graph_name, [], _message_ids, _limit), do: {:ok, []}

  defp fetch_related_messages(graph_name, actors, message_ids, limit) do
    actor_ids = Enum.map(actors, & &1.actor_id)

    Repo.query(related_messages_sql(graph_name), [actor_ids, message_ids, limit])
    |> case do
      {:ok, %{rows: rows}} ->
        {:ok,
         Enum.map(rows, fn [
                             message_id,
                             external_id,
                             body,
                             observed_at,
                             actor_handle,
                             channel_name
                           ] ->
           %{
             message_id: message_id,
             external_id: external_id,
             body: body,
             observed_at: observed_at,
             actor_handle: actor_handle,
             channel_name: channel_name
           }
         end)}

      error ->
        error
    end
  end

  defp neighbor_actors_sql(graph_name) do
    """
    SELECT DISTINCT actor_id, handle, display_name, role
    FROM (
      SELECT
        ag_catalog.agtype_object_field_text(a.properties, 'id') AS actor_id,
        ag_catalog.agtype_object_field_text(a.properties, 'handle') AS handle,
        ag_catalog.agtype_object_field_text(a.properties, 'display_name') AS display_name,
        'sender' AS role
      FROM #{qualified_table(graph_name, "Message")} m
      JOIN #{qualified_table(graph_name, "SENT")} sent
        ON sent.end_id::text = m.id::text
      JOIN #{qualified_table(graph_name, "Actor")} a
        ON a.id::text = sent.start_id::text
      WHERE ag_catalog.agtype_object_field_text(m.properties, 'id') = ANY($1::text[])

      UNION ALL

      SELECT
        ag_catalog.agtype_object_field_text(a.properties, 'id') AS actor_id,
        ag_catalog.agtype_object_field_text(a.properties, 'handle') AS handle,
        ag_catalog.agtype_object_field_text(a.properties, 'display_name') AS display_name,
        'mentioned' AS role
      FROM #{qualified_table(graph_name, "Message")} m
      JOIN #{qualified_table(graph_name, "MENTIONS")} mention
        ON mention.start_id::text = m.id::text
      JOIN #{qualified_table(graph_name, "Actor")} a
        ON a.id::text = mention.end_id::text
      WHERE ag_catalog.agtype_object_field_text(m.properties, 'id') = ANY($1::text[])
    ) actor_neighbors
    ORDER BY role, handle
    """
  end

  defp actor_relationships_sql(graph_name) do
    """
    SELECT DISTINCT
      ag_catalog.agtype_object_field_text(a1.properties, 'id') AS from_actor_id,
      ag_catalog.agtype_object_field_text(a1.properties, 'handle') AS from_actor_handle,
      ag_catalog.agtype_object_field_text(a2.properties, 'id') AS to_actor_id,
      ag_catalog.agtype_object_field_text(a2.properties, 'handle') AS to_actor_handle,
      ag_catalog.agtype_object_field_text(rel.properties, 'relationship_type') AS relationship_type,
      ag_catalog.agtype_object_field_text(rel.properties, 'weight') AS weight,
      ag_catalog.agtype_object_field_text(rel.properties, 'source_message_id') AS source_message_id
    FROM #{qualified_table(graph_name, "RELATES_TO")} rel
    JOIN #{qualified_table(graph_name, "Actor")} a1
      ON a1.id::text = rel.start_id::text
    JOIN #{qualified_table(graph_name, "Actor")} a2
      ON a2.id::text = rel.end_id::text
    WHERE ag_catalog.agtype_object_field_text(a1.properties, 'id') = ANY($1::text[])
      AND ag_catalog.agtype_object_field_text(a2.properties, 'id') = ANY($1::text[])
    ORDER BY relationship_type, from_actor_handle, to_actor_handle
    """
  end

  defp related_messages_sql(graph_name) do
    """
    SELECT DISTINCT
      ag_catalog.agtype_object_field_text(m.properties, 'id') AS message_id,
      ag_catalog.agtype_object_field_text(m.properties, 'external_id') AS external_id,
      ag_catalog.agtype_object_field_text(m.properties, 'body') AS body,
      ag_catalog.agtype_object_field_text(m.properties, 'observed_at') AS observed_at,
      ag_catalog.agtype_object_field_text(a.properties, 'handle') AS actor_handle,
      ag_catalog.agtype_object_field_text(c.properties, 'name') AS channel_name
    FROM #{qualified_table(graph_name, "Actor")} a
    JOIN #{qualified_table(graph_name, "SENT")} sent
      ON sent.start_id::text = a.id::text
    JOIN #{qualified_table(graph_name, "Message")} m
      ON m.id::text = sent.end_id::text
    LEFT JOIN #{qualified_table(graph_name, "IN_CHANNEL")} ic
      ON ic.start_id::text = m.id::text
    LEFT JOIN #{qualified_table(graph_name, "Channel")} c
      ON c.id::text = ic.end_id::text
    WHERE ag_catalog.agtype_object_field_text(a.properties, 'id') = ANY($1::text[])
      AND NOT (ag_catalog.agtype_object_field_text(m.properties, 'id') = ANY($2::text[]))
    ORDER BY ag_catalog.agtype_object_field_text(m.properties, 'observed_at') DESC NULLS LAST
    LIMIT $3
    """
  end

  defp agtype_build_map_sql(properties, start_index) do
    entries =
      properties
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Enum.sort_by(fn {key, _value} -> key end)

    Enum.reduce(entries, {"ag_catalog.agtype_build_map(", [], start_index, true}, fn {key, value},
                                                                                     {sql, params,
                                                                                      index,
                                                                                      first?} ->
      prefix = if first?, do: "", else: ", "

      {
        sql <> "#{prefix}'#{escape_sql_literal(key)}', #{agtype_param(index, value)}",
        params ++ [value],
        index + 1,
        false
      }
    end)
    |> then(fn {sql, params, next_index, _first?} -> {sql <> ")", params, next_index} end)
  end

  defp create_graph_sql(graph_name) do
    "SELECT ag_catalog.create_graph(#{sql_literal(graph_name)})"
  end

  defp create_label_sql(graph_name, label_name) when label_name in @vertex_labels do
    "SELECT ag_catalog.create_vlabel(#{sql_literal(graph_name)}, #{sql_literal(label_name)})"
  end

  defp create_label_sql(graph_name, label_name) when label_name in @edge_labels do
    "SELECT ag_catalog.create_elabel(#{sql_literal(graph_name)}, #{sql_literal(label_name)})"
  end

  defp qualified_table(graph_name, table_name) do
    "#{quote_ident(graph_name)}.#{quote_ident(table_name)}"
  end

  defp quote_ident(name) do
    escaped = String.replace(to_string(name), "\"", "\"\"")
    ~s("#{escaped}")
  end

  defp sql_literal(value) do
    escaped = escape_sql_literal(value)
    "'#{escaped}'"
  end

  defp escape_sql_literal(value) do
    value
    |> to_string()
    |> String.replace("'", "''")
  end

  defp agtype_param(index, value) when is_integer(value), do: "$#{index}::bigint"
  defp agtype_param(index, value) when is_float(value), do: "$#{index}::double precision"
  defp agtype_param(index, value) when is_boolean(value), do: "$#{index}::boolean"
  defp agtype_param(index, _value), do: "$#{index}::text"

  defp parse_integer(nil), do: nil

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp iso8601(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime)
  defp iso8601(value), do: to_string(value)

  defp normalize_repo_result({:ok, _result}), do: :ok
  defp normalize_repo_result(error), do: error

  defp with_age_session(fun) when is_function(fun, 0) do
    case Repo.transaction(fn ->
           with {:ok, _result} <- Repo.query("SET LOCAL search_path = ag_catalog, public") do
             case fun.() do
               :ok = ok -> ok
               {:ok, _result} = ok -> ok
               error -> Repo.rollback(error)
             end
           else
             error -> Repo.rollback(error)
           end
         end) do
      {:ok, result} -> result
      {:error, error} -> error
    end
  end
end
