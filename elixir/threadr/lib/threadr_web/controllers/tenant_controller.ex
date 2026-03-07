defmodule ThreadrWeb.TenantController do
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

  def migrate(conn, %{"subject_name" => subject_name}) do
    with {:ok, user} <- current_user(conn),
         {:ok, tenant} <- Service.migrate_tenant_for_user(user, subject_name) do
      json(conn, %{data: tenant_result_json(tenant)})
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
      kubernetes_namespace: tenant.kubernetes_namespace,
      tenant_migration_status: tenant.tenant_migration_status,
      tenant_migration_version: tenant.tenant_migration_version,
      tenant_migrated_at: tenant.tenant_migrated_at,
      tenant_migration_error: tenant.tenant_migration_error,
      inserted_at: tenant.inserted_at,
      updated_at: tenant.updated_at
    }
  end

  defp tenant_result_json(result) do
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
