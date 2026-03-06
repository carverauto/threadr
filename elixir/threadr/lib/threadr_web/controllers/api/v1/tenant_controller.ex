defmodule ThreadrWeb.Api.V1.TenantController do
  use ThreadrWeb, :controller

  alias Threadr.ControlPlane.Service

  def index(conn, _params) do
    with {:ok, user} <- current_user(conn),
         {:ok, tenants} <- Service.list_user_tenants(user) do
      json(conn, %{data: Enum.map(tenants, &tenant_json/1)})
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

  def create(conn, %{"tenant" => tenant_params}) do
    with {:ok, user} <- current_user(conn),
         {:ok, tenant} <- Service.create_tenant_for_user(user, tenant_params) do
      conn
      |> put_status(:created)
      |> json(%{data: tenant_json(tenant)})
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

  def migrate(conn, %{"subject_name" => subject_name}) do
    with {:ok, user} <- current_user(conn),
         {:ok, result} <- Service.migrate_tenant_for_user(user, subject_name) do
      json(conn, %{data: tenant_migration_json(result)})
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{errors: %{detail: "Unauthorized"}})

      {:error, {:tenant_not_found, _}} ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Tenant not found"}})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{errors: %{detail: "Forbidden"}})

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
      status: tenant.status,
      tenant_migration_status: tenant.tenant_migration_status,
      tenant_migration_version: tenant.tenant_migration_version,
      tenant_migrated_at: tenant.tenant_migrated_at
    }
  end

  defp tenant_migration_json(result) do
    %{
      tenant_id: result.tenant_id,
      tenant_name: result.tenant_name,
      subject_name: result.subject_name,
      schema_name: result.schema_name,
      tenant_migration_status: result.tenant_migration_status,
      tenant_migration_version: result.tenant_migration_version,
      tenant_migrated_at: result.tenant_migrated_at
    }
  end
end
