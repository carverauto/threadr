defmodule ThreadrWeb.Api.V1.DossierController do
  use ThreadrWeb, :controller

  alias Threadr.ControlPlane.Service

  def show(conn, %{
        "subject_name" => subject_name,
        "node_kind" => node_kind,
        "node_id" => node_id
      }) do
    with {:ok, user} <- current_user(conn),
         {:ok, result} <-
           Service.get_tenant_dossier_for_user(user, subject_name, node_kind, node_id) do
      json(conn, %{data: dossier_response_json(result)})
    else
      {:error, :unauthorized} ->
        unauthorized(conn)

      {:error, {:tenant_not_found, _}} ->
        not_found(conn, "Tenant not found")

      {:error, {:resource_not_found, _kind, _id}} ->
        not_found(conn, "Dossier target not found")

      {:error, :forbidden} ->
        forbidden(conn)

      {:error, reason} ->
        unprocessable(conn, inspect(reason))
    end
  end

  def compare(
        conn,
        %{
          "subject_name" => subject_name,
          "node_kind" => node_kind,
          "node_id" => node_id
        } = params
      ) do
    with {:ok, user} <- current_user(conn),
         {:ok, result} <-
           Service.compare_tenant_dossier_windows_for_user(
             user,
             subject_name,
             node_kind,
             node_id,
             since: parse_datetime(params["since"]),
             until: parse_datetime(params["until"]),
             compare_since: parse_datetime(params["compare_since"]),
             compare_until: parse_datetime(params["compare_until"])
           ) do
      json(conn, %{data: dossier_compare_json(result)})
    else
      {:error, :unauthorized} ->
        unauthorized(conn)

      {:error, {:tenant_not_found, _}} ->
        not_found(conn, "Tenant not found")

      {:error, {:resource_not_found, _kind, _id}} ->
        not_found(conn, "Dossier target not found")

      {:error, :forbidden} ->
        forbidden(conn)

      {:error, :generation_provider_not_configured} ->
        unprocessable(conn, "No LLM is configured for this tenant or the system default")

      {:error, reason} ->
        unprocessable(conn, inspect(reason))
    end
  end

  defp dossier_response_json(result) do
    %{
      tenant_subject_name: result.tenant.subject_name,
      tenant_schema: result.tenant.schema_name,
      membership_role: result.membership.role,
      dossier: json_safe(result.dossier)
    }
  end

  defp dossier_compare_json(result) do
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
