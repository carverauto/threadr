defmodule ThreadrWeb.Api.V1.MembershipController do
  use ThreadrWeb, :controller

  alias Threadr.ControlPlane.Service

  def index(conn, %{"subject_name" => subject_name}) do
    with {:ok, user} <- current_user(conn),
         {:ok, memberships} <- Service.list_tenant_memberships_for_user(user, subject_name) do
      json(conn, %{data: Enum.map(memberships, &membership_json/1)})
    else
      {:error, :unauthorized} -> unauthorized(conn)
      {:error, {:tenant_not_found, _}} -> not_found(conn, "Tenant not found")
      {:error, :forbidden} -> forbidden(conn)
      {:error, reason} -> unprocessable(conn, reason)
    end
  end

  def create(conn, %{"subject_name" => subject_name, "membership" => membership_params}) do
    with {:ok, user} <- current_user(conn),
         {:ok, membership} <-
           Service.create_tenant_membership_for_user(user, subject_name, membership_params) do
      conn
      |> put_status(:created)
      |> json(%{data: membership_json(membership)})
    else
      {:error, :unauthorized} -> unauthorized(conn)
      {:error, {:tenant_not_found, _}} -> not_found(conn, "Tenant not found")
      {:error, {:user_not_found, _}} -> not_found(conn, "User not found")
      {:error, :forbidden} -> forbidden(conn)
      {:error, reason} -> unprocessable(conn, reason)
    end
  end

  def update(conn, %{
        "subject_name" => subject_name,
        "id" => id,
        "membership" => membership_params
      }) do
    with {:ok, user} <- current_user(conn),
         {:ok, membership} <-
           Service.update_tenant_membership_for_user(user, subject_name, id, membership_params) do
      json(conn, %{data: membership_json(membership)})
    else
      {:error, :unauthorized} -> unauthorized(conn)
      {:error, {:tenant_not_found, _}} -> not_found(conn, "Tenant not found")
      {:error, {:tenant_membership, :not_found, _}} -> not_found(conn, "Membership not found")
      {:error, :forbidden} -> forbidden(conn)
      {:error, reason} -> unprocessable(conn, reason)
    end
  end

  def delete(conn, %{"subject_name" => subject_name, "id" => id}) do
    with {:ok, user} <- current_user(conn),
         :ok <- Service.delete_tenant_membership_for_user(user, subject_name, id) do
      send_resp(conn, :no_content, "")
    else
      {:error, :unauthorized} -> unauthorized(conn)
      {:error, {:tenant_not_found, _}} -> not_found(conn, "Tenant not found")
      {:error, {:tenant_membership, :not_found, _}} -> not_found(conn, "Membership not found")
      {:error, :forbidden} -> forbidden(conn)
      {:error, reason} -> unprocessable(conn, reason)
    end
  end

  defp current_user(%{assigns: %{current_user: %{id: _} = user}}), do: {:ok, user}
  defp current_user(_conn), do: {:error, :unauthorized}

  defp membership_json(membership) do
    %{
      id: membership.id,
      tenant_id: membership.tenant_id,
      user_id: membership.user_id,
      role: membership.role,
      user: user_json(membership.user),
      inserted_at: membership.inserted_at,
      updated_at: membership.updated_at
    }
  end

  defp user_json(%{id: id, email: email, name: name}) do
    %{id: id, email: email, name: name}
  end

  defp user_json(_), do: nil

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

  defp unprocessable(conn, reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{detail: inspect(reason)}})
  end
end
