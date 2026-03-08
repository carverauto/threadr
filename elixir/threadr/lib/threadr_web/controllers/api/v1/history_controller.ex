defmodule ThreadrWeb.Api.V1.HistoryController do
  use ThreadrWeb, :controller

  alias Threadr.ControlPlane.Analysis
  alias Threadr.HistoryRequest

  def index(conn, %{"subject_name" => subject_name} = params) do
    request = history_request(params)

    with {:ok, user} <- current_user(conn),
         {:ok, result} <- Analysis.list_tenant_messages_for_user(user, subject_name, request) do
      json(conn, %{data: history_json(result)})
    else
      {:error, :unauthorized} ->
        unauthorized(conn)

      {:error, {:tenant_not_found, _}} ->
        not_found(conn, "Tenant not found")

      {:error, :forbidden} ->
        forbidden(conn)

      {:error, reason} ->
        unprocessable(conn, inspect(reason))
    end
  end

  def compare(conn, %{"subject_name" => subject_name} = params) do
    request = history_request(params)

    with {:ok, user} <- current_user(conn),
         {:ok, result} <-
           Analysis.compare_tenant_history_windows_for_user(user, subject_name, request) do
      json(conn, %{data: compare_json(result)})
    else
      {:error, :unauthorized} ->
        unauthorized(conn)

      {:error, {:tenant_not_found, _}} ->
        not_found(conn, "Tenant not found")

      {:error, :forbidden} ->
        forbidden(conn)

      {:error, :generation_provider_not_configured} ->
        unprocessable(conn, "No LLM is configured for this tenant or the system default")

      {:error, reason} ->
        unprocessable(conn, inspect(reason))
    end
  end

  defp history_json(result) do
    %{
      tenant_subject_name: result.tenant.subject_name,
      tenant_schema: result.tenant.schema_name,
      membership_role: result.membership.role,
      messages: json_safe(result.messages),
      facts_over_time: json_safe(result.facts_over_time)
    }
  end

  defp compare_json(result) do
    %{
      tenant_subject_name: result.tenant.subject_name,
      tenant_schema: result.tenant.schema_name,
      membership_role: result.membership.role,
      comparison: json_safe(result.comparison),
      entity_delta: json_safe(Map.get(result.comparison, :entity_delta, %{})),
      fact_delta: json_safe(Map.get(result.comparison, :fact_delta, %{})),
      answer: generation_json(result.answer)
    }
  end

  defp generation_json(answer) do
    %{
      content: answer.content,
      model: answer.model,
      provider: answer.provider,
      metadata: json_safe(answer.metadata)
    }
  end

  defp history_request(params) do
    HistoryRequest.new(
      query: params["query"],
      actor_handle: params["actor_handle"],
      channel_name: params["channel_name"],
      entity_name: params["entity_name"],
      entity_type: params["entity_type"],
      fact_type: params["fact_type"],
      since: parse_datetime(params["since"]),
      until: parse_datetime(params["until"]),
      compare_since: parse_datetime(params["compare_since"]),
      compare_until: parse_datetime(params["compare_until"]),
      limit: parse_limit(params["limit"])
    )
  end

  defp parse_limit(nil), do: 50
  defp parse_limit(limit) when is_integer(limit), do: limit

  defp parse_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {value, ""} when value > 0 -> value
      _ -> 50
    end
  end

  defp parse_limit(_limit), do: 50

  defp current_user(%{assigns: %{current_user: %{id: _} = user}}), do: {:ok, user}
  defp current_user(_conn), do: {:error, :unauthorized}

  defp parse_datetime(nil), do: nil
  defp parse_datetime(""), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, datetime} -> datetime
      _ -> nil
    end
  end

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
    if String.valid?(value), do: value, else: Base.encode16(value, case: :lower)
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
