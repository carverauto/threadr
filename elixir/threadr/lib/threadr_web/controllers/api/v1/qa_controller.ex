defmodule ThreadrWeb.Api.V1.QaController do
  use ThreadrWeb, :controller

  alias Threadr.ControlPlane.Service

  def search(conn, %{"subject_name" => subject_name, "question" => question} = params) do
    with {:ok, user} <- current_user(conn),
         {:ok, result} <-
           Service.semantic_search_for_user(
             user,
             subject_name,
             question,
             limit: parse_limit(params["limit"])
           ) do
      json(conn, %{data: search_json(result)})
    else
      {:error, :unauthorized} ->
        unauthorized(conn)

      {:error, {:tenant_not_found, _}} ->
        not_found(conn, "Tenant not found")

      {:error, :forbidden} ->
        forbidden(conn)

      {:error, :no_message_embeddings} ->
        unprocessable(conn, "No tenant message embeddings available")

      {:error, :generation_provider_not_configured} ->
        unprocessable(conn, "No LLM is configured for this tenant or the system default")

      {:error, reason} ->
        unprocessable(conn, inspect(reason))
    end
  end

  def answer(conn, %{"subject_name" => subject_name, "question" => question} = params) do
    with {:ok, user} <- current_user(conn),
         {:ok, result} <-
           Service.answer_tenant_question_for_user(
             user,
             subject_name,
             question,
             limit: parse_limit(params["limit"])
           ) do
      json(conn, %{data: answer_json(result)})
    else
      {:error, :unauthorized} ->
        unauthorized(conn)

      {:error, {:tenant_not_found, _}} ->
        not_found(conn, "Tenant not found")

      {:error, :forbidden} ->
        forbidden(conn)

      {:error, :no_message_embeddings} ->
        unprocessable(conn, "No tenant message embeddings available")

      {:error, :generation_provider_not_configured} ->
        unprocessable(conn, "No LLM is configured for this tenant or the system default")

      {:error, reason} ->
        unprocessable(conn, inspect(reason))
    end
  end

  def graph_answer(conn, %{"subject_name" => subject_name, "question" => question} = params) do
    with {:ok, user} <- current_user(conn),
         {:ok, result} <-
           Service.answer_tenant_graph_question_for_user(
             user,
             subject_name,
             question,
             limit: parse_limit(params["limit"])
           ) do
      json(conn, %{data: graph_answer_json(result)})
    else
      {:error, :unauthorized} ->
        unauthorized(conn)

      {:error, {:tenant_not_found, _}} ->
        not_found(conn, "Tenant not found")

      {:error, :forbidden} ->
        forbidden(conn)

      {:error, :no_message_embeddings} ->
        unprocessable(conn, "No tenant message embeddings available")

      {:error, :generation_provider_not_configured} ->
        unprocessable(conn, "No LLM is configured for this tenant or the system default")

      {:error, reason} ->
        unprocessable(conn, inspect(reason))
    end
  end

  def summarize(conn, %{"subject_name" => subject_name, "topic" => topic} = params) do
    with {:ok, user} <- current_user(conn),
         {:ok, result} <-
           Service.summarize_tenant_topic_for_user(
             user,
             subject_name,
             topic,
             limit: parse_limit(params["limit"])
           ) do
      json(conn, %{data: summary_json(result)})
    else
      {:error, :unauthorized} ->
        unauthorized(conn)

      {:error, {:tenant_not_found, _}} ->
        not_found(conn, "Tenant not found")

      {:error, :forbidden} ->
        forbidden(conn)

      {:error, :no_message_embeddings} ->
        unprocessable(conn, "No tenant message embeddings available")

      {:error, :generation_provider_not_configured} ->
        unprocessable(conn, "No LLM is configured for this tenant or the system default")

      {:error, reason} ->
        unprocessable(conn, inspect(reason))
    end
  end

  defp current_user(%{assigns: %{current_user: %{id: _} = user}}), do: {:ok, user}
  defp current_user(_conn), do: {:error, :unauthorized}

  defp search_json(result) do
    %{
      tenant_subject_name: result.tenant_subject_name,
      tenant_schema: result.tenant_schema,
      question: result.question,
      query: json_safe(result.query),
      matches: Enum.map(result.matches, &match_json/1),
      citations: Enum.map(Map.get(result, :citations, []), &citation_json/1),
      context: result.context
    }
  end

  defp answer_json(result) do
    search_json(result)
    |> Map.put(:answer, generation_json(result.answer))
  end

  defp graph_answer_json(result) do
    answer_json(%{
      tenant_subject_name: result.tenant_subject_name,
      tenant_schema: result.tenant_schema,
      question: result.question,
      query: result.semantic.query,
      matches: result.semantic.matches,
      citations: result.semantic.citations,
      context: result.context,
      answer: result.answer
    })
    |> Map.put(:semantic, search_json(result.semantic))
    |> Map.put(:graph, graph_json(result.graph))
  end

  defp summary_json(result) do
    %{
      tenant_subject_name: result.tenant_subject_name,
      tenant_schema: result.tenant_schema,
      topic: result.topic,
      semantic: search_json(result.semantic),
      graph: graph_json(result.graph),
      context: result.context,
      summary: generation_json(result.summary)
    }
  end

  defp match_json(match) do
    json_safe(%{
      message_id: match.message_id,
      external_id: match.external_id,
      body: match.body,
      observed_at: match.observed_at,
      actor_handle: match.actor_handle,
      actor_display_name: match.actor_display_name,
      channel_name: match.channel_name,
      model: match.model,
      distance: match.distance,
      similarity: match.similarity
    })
  end

  defp generation_json(answer) do
    %{
      content: answer.content,
      model: answer.model,
      provider: answer.provider,
      metadata: json_safe(answer.metadata)
    }
  end

  defp graph_json(graph) do
    %{
      actors: json_safe(graph.actors),
      relationships: json_safe(graph.relationships),
      related_messages: json_safe(graph.related_messages),
      citations: json_safe(graph.citations),
      context: graph.context
    }
  end

  defp citation_json(citation) do
    json_safe(%{
      label: citation.label,
      rank: citation.rank,
      message_id: citation.message_id,
      external_id: citation.external_id,
      body: citation.body,
      observed_at: citation.observed_at,
      actor_handle: citation.actor_handle,
      actor_display_name: citation.actor_display_name,
      channel_name: citation.channel_name,
      similarity: citation.similarity
    })
  end

  defp parse_limit(nil), do: 5
  defp parse_limit(limit) when is_integer(limit) and limit > 0, do: limit

  defp parse_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {value, ""} when value > 0 -> value
      _ -> 5
    end
  end

  defp parse_limit(_limit), do: 5

  defp unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{errors: %{detail: "Unauthorized"}})
  end

  defp forbidden(conn) do
    conn
    |> put_status(:forbidden)
    |> json(%{errors: %{detail: "Forbidden"}})
  end

  defp not_found(conn, message) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: message}})
  end

  defp unprocessable(conn, message) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{detail: message}})
  end

  defp json_safe(value) when is_binary(value) do
    if String.valid?(value) do
      value
    else
      Base.encode16(value, case: :lower)
    end
  end

  defp json_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp json_safe(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json_safe(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)

  defp json_safe(value)
       when is_integer(value) or is_float(value) or is_boolean(value) or is_nil(value), do: value

  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)

  defp json_safe(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {json_safe_key(key), json_safe(item)} end)
  end

  defp json_safe(value), do: inspect(value)

  defp json_safe_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_safe_key(key) when is_binary(key), do: json_safe(key)
  defp json_safe_key(key), do: to_string(key)
end
