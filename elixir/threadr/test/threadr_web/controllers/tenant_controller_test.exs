defmodule ThreadrWeb.TenantControllerTest do
  use ThreadrWeb.ConnCase, async: false

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Service

  test "GET /api/control-plane/tenants returns only the current user's tenants", %{conn: conn} do
    owner = create_user!("owner")
    _owned_tenant = create_tenant!("Owned", owner)

    other_user = create_user!("other")
    other_tenant = create_tenant!("Other", other_user)

    conn = conn |> api_key_conn(owner) |> get(~p"/api/control-plane/tenants")

    assert %{"data" => tenants} = json_response(conn, 200)
    refute Enum.any?(tenants, &(&1["id"] == other_tenant.id))
    assert Enum.all?(tenants, &(&1["tenant_migration_status"] == "succeeded"))
  end

  test "POST /api/control-plane/tenants/:subject_name/migrate returns migration status for tenant owners",
       %{conn: conn} do
    owner = create_user!("owner")
    tenant = create_tenant!("Migrate Tenant", owner)

    conn =
      conn
      |> api_key_conn(owner)
      |> post(~p"/api/control-plane/tenants/#{tenant.subject_name}/migrate")

    assert %{
             "data" => %{
               "tenant_id" => tenant_id,
               "subject_name" => subject_name,
               "schema_name" => schema_name,
               "tenant_migration_status" => "succeeded",
               "tenant_migration_version" => version,
               "tenant_migrated_at" => migrated_at
             }
           } = json_response(conn, 200)

    assert tenant_id == tenant.id
    assert subject_name == tenant.subject_name
    assert schema_name == tenant.schema_name
    assert version == Service.latest_tenant_migration_version()
    assert is_binary(migrated_at)
  end

  test "POST /api/control-plane/tenants/:subject_name/migrate returns 403 for non-manager memberships",
       %{conn: conn} do
    owner = create_user!("owner")
    member = create_user!("member")
    tenant = create_tenant!("Forbidden Tenant", owner)

    {:ok, _membership} =
      ControlPlane.create_tenant_membership(
        %{
          user_id: member.id,
          tenant_id: tenant.id,
          role: "member"
        },
        context: %{system: true}
      )

    conn =
      conn
      |> api_key_conn(member)
      |> post(~p"/api/control-plane/tenants/#{tenant.subject_name}/migrate")

    assert json_response(conn, 403) == %{"errors" => %{"detail" => "Forbidden"}}
  end

  test "POST /api/control-plane/tenants/:subject_name/migrate returns 404 for missing tenant", %{
    conn: conn
  } do
    owner = create_user!("owner")

    conn =
      conn
      |> api_key_conn(owner)
      |> post(~p"/api/control-plane/tenants/missing-tenant/migrate")

    assert json_response(conn, 404) == %{"errors" => %{"detail" => "Tenant not found"}}
  end

  defp api_key_conn(conn, user) do
    {:ok, _api_key, plaintext_api_key} = Service.create_api_key(user, %{name: "test-api"})

    conn
    |> put_req_header("authorization", "Bearer #{plaintext_api_key}")
    |> put_req_header("accept", "application/json")
  end

  defp create_user!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      ControlPlane.register_user(%{
        email: "#{prefix}-#{suffix}@example.com",
        name: "User #{suffix}",
        password: "threadr-password-#{suffix}"
      })

    user
  end

  defp create_tenant!(name_prefix, owner) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(
        %{
          name: "#{name_prefix} #{suffix}",
          subject_name: "api-tenant-#{suffix}"
        },
        owner_user: owner
      )

    tenant
  end
end
