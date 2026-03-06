defmodule ThreadrWeb.Api.V1.MeController do
  use ThreadrWeb, :controller

  alias Threadr.ControlPlane.Service

  def show(conn, _params) do
    with {:ok, user} <- current_user(conn),
         {:ok, tenants} <- Service.list_user_tenants(user) do
      json(conn, %{
        data: %{
          id: user.id,
          email: user.email,
          name: user.name,
          tenants: Enum.map(tenants, &tenant_json/1)
        }
      })
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{errors: %{detail: "Unauthorized"}})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{detail: inspect(reason)}})
    end
  end

  defp current_user(%{assigns: %{current_user: %{id: _} = user}}), do: {:ok, user}
  defp current_user(_conn), do: {:error, :unauthorized}

  defp tenant_json(tenant) do
    %{
      id: tenant.id,
      name: tenant.name,
      slug: tenant.slug,
      subject_name: tenant.subject_name,
      schema_name: tenant.schema_name,
      status: tenant.status
    }
  end
end
