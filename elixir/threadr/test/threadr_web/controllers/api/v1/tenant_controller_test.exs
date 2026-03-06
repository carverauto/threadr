defmodule ThreadrWeb.Api.V1.TenantControllerTest do
  use ThreadrWeb.ConnCase, async: false

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Service

  test "GET /api/v1/tenants requires authentication", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/tenants")

    assert json_response(conn, 401) == %{"errors" => %{"detail" => "Unauthorized"}}
  end

  test "GET /api/v1/tenants returns only the current user's tenants for an API key", %{conn: conn} do
    owner = create_user!("owner")
    other_user = create_user!("other")

    owned_tenant = create_tenant!("Owned", owner)
    _other_tenant = create_tenant!("Other", other_user)

    {:ok, _api_key, plaintext_api_key} = Service.create_api_key(owner, %{name: "CLI"})

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{plaintext_api_key}")
      |> put_req_header("accept", "application/json")
      |> get(~p"/api/v1/tenants")

    assert %{"data" => [tenant]} = json_response(conn, 200)
    assert tenant["id"] == owned_tenant.id
    assert tenant["subject_name"] == owned_tenant.subject_name

    {:ok, [api_key]} = Service.list_user_api_keys(owner)
    assert not is_nil(api_key.last_used_at)
  end

  test "POST /api/v1/tenants creates a tenant owned by the current user", %{conn: conn} do
    owner = create_user!("owner")

    conn =
      conn
      |> api_key_conn(owner)
      |> post(~p"/api/v1/tenants", %{
        "tenant" => %{"name" => "Acme Threat Intel", "subject_name" => "acme-threat-intel"}
      })

    assert %{"data" => tenant} = json_response(conn, 201)
    assert tenant["subject_name"] == "acme-threat-intel"
    assert tenant["tenant_migration_status"] == "succeeded"

    {:ok, tenants} = Service.list_user_tenants(owner)
    assert Enum.any?(tenants, &(&1.subject_name == "acme-threat-intel"))
  end

  test "POST /api/v1/tenants/:subject_name/migrate returns 403 for non-manager memberships", %{
    conn: conn
  } do
    owner = create_user!("owner")
    member = create_user!("member")
    tenant = create_tenant!("Owned", owner)

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
      |> post(~p"/api/v1/tenants/#{tenant.subject_name}/migrate")

    assert json_response(conn, 403) == %{"errors" => %{"detail" => "Forbidden"}}
  end

  defp api_key_conn(conn, user) do
    {:ok, _api_key, plaintext_api_key} = Service.create_api_key(user, %{name: "CLI"})

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

  defp create_tenant!(prefix, owner) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(
        %{
          name: "#{prefix} #{suffix}",
          subject_name: "#{String.downcase(prefix)}-#{suffix}"
        },
        owner_user: owner
      )

    tenant
  end
end
