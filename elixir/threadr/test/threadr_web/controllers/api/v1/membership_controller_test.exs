defmodule ThreadrWeb.Api.V1.MembershipControllerTest do
  use ThreadrWeb.ConnCase, async: false

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Service

  test "GET /api/v1/tenants/:subject_name/memberships lists memberships for tenant managers", %{
    conn: conn
  } do
    owner = create_user!("owner")
    member = create_user!("member")
    tenant = create_tenant!("Owned", owner)

    {:ok, _membership} =
      ControlPlane.create_tenant_membership(
        %{user_id: member.id, tenant_id: tenant.id, role: "member"},
        context: %{system: true}
      )

    conn =
      conn
      |> api_key_conn(owner)
      |> get(~p"/api/v1/tenants/#{tenant.subject_name}/memberships")

    assert %{"data" => memberships} = json_response(conn, 200)
    assert Enum.count(memberships) == 2

    assert Enum.any?(
             memberships,
             &(&1["role"] == "owner" and &1["user"]["email"] == to_string(owner.email))
           )

    assert Enum.any?(
             memberships,
             &(&1["role"] == "member" and &1["user"]["email"] == to_string(member.email))
           )
  end

  test "POST /api/v1/tenants/:subject_name/memberships creates a membership for an existing user",
       %{
         conn: conn
       } do
    owner = create_user!("owner")
    invitee = create_user!("invitee")
    tenant = create_tenant!("Owned", owner)

    conn =
      conn
      |> api_key_conn(owner)
      |> post(~p"/api/v1/tenants/#{tenant.subject_name}/memberships", %{
        "membership" => %{"email" => invitee.email, "role" => "admin"}
      })

    assert %{"data" => membership} = json_response(conn, 201)
    assert membership["role"] == "admin"
    assert membership["user"]["email"] == to_string(invitee.email)
  end

  test "PATCH /api/v1/tenants/:subject_name/memberships/:id updates a membership role", %{
    conn: conn
  } do
    owner = create_user!("owner")
    member = create_user!("member")
    tenant = create_tenant!("Owned", owner)

    {:ok, membership} =
      ControlPlane.create_tenant_membership(
        %{user_id: member.id, tenant_id: tenant.id, role: "member"},
        context: %{system: true}
      )

    conn =
      conn
      |> api_key_conn(owner)
      |> patch(~p"/api/v1/tenants/#{tenant.subject_name}/memberships/#{membership.id}", %{
        "membership" => %{"role" => "admin"}
      })

    assert %{"data" => updated_membership} = json_response(conn, 200)
    assert updated_membership["id"] == membership.id
    assert updated_membership["role"] == "admin"
  end

  test "DELETE /api/v1/tenants/:subject_name/memberships/:id deletes a membership", %{conn: conn} do
    owner = create_user!("owner")
    member = create_user!("member")
    tenant = create_tenant!("Owned", owner)

    {:ok, membership} =
      ControlPlane.create_tenant_membership(
        %{user_id: member.id, tenant_id: tenant.id, role: "member"},
        context: %{system: true}
      )

    conn =
      conn
      |> api_key_conn(owner)
      |> delete(~p"/api/v1/tenants/#{tenant.subject_name}/memberships/#{membership.id}")

    assert response(conn, 204) == ""

    {:ok, memberships} = Service.list_tenant_memberships_for_user(owner, tenant.subject_name)
    refute Enum.any?(memberships, &(&1.id == membership.id))
  end

  test "membership endpoints return 403 for non-manager memberships", %{conn: conn} do
    owner = create_user!("owner")
    member = create_user!("member")
    invitee = create_user!("invitee")
    tenant = create_tenant!("Owned", owner)

    {:ok, membership} =
      ControlPlane.create_tenant_membership(
        %{user_id: member.id, tenant_id: tenant.id, role: "member"},
        context: %{system: true}
      )

    conn =
      conn
      |> api_key_conn(member)
      |> get(~p"/api/v1/tenants/#{tenant.subject_name}/memberships")

    assert json_response(conn, 403) == %{"errors" => %{"detail" => "Forbidden"}}

    conn =
      conn
      |> recycle()
      |> api_key_conn(member)
      |> post(~p"/api/v1/tenants/#{tenant.subject_name}/memberships", %{
        "membership" => %{"email" => invitee.email, "role" => "member"}
      })

    assert json_response(conn, 403) == %{"errors" => %{"detail" => "Forbidden"}}

    conn =
      conn
      |> recycle()
      |> api_key_conn(member)
      |> patch(~p"/api/v1/tenants/#{tenant.subject_name}/memberships/#{membership.id}", %{
        "membership" => %{"role" => "admin"}
      })

    assert json_response(conn, 403) == %{"errors" => %{"detail" => "Forbidden"}}
  end

  test "creating a membership for an unknown user returns 404", %{conn: conn} do
    owner = create_user!("owner")
    tenant = create_tenant!("Owned", owner)

    conn =
      conn
      |> api_key_conn(owner)
      |> post(~p"/api/v1/tenants/#{tenant.subject_name}/memberships", %{
        "membership" => %{"email" => "missing@example.com", "role" => "member"}
      })

    assert json_response(conn, 404) == %{"errors" => %{"detail" => "User not found"}}
  end

  defp api_key_conn(conn, user) do
    {:ok, _api_key, plaintext_api_key} = Service.create_api_key(user, %{name: "membership-api"})

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
