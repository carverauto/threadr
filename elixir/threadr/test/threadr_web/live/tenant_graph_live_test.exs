defmodule ThreadrWeb.TenantGraphLiveTest do
  use ThreadrWeb.ConnCase, async: false

  import AshAuthentication.Phoenix.Plug, only: [store_in_session: 2]
  import Phoenix.LiveViewTest

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Service

  test "renders the tenant graph workspace", %{conn: conn} do
    user = create_user!("tenant-graph")
    tenant = create_tenant!("Graph Tenant", user)

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, _view, html} = live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/graph")

    assert html =~ "#{tenant.name} Graph"
    assert html =~ "graph:#{tenant.subject_name}"
    assert html =~ "TenantGraphExplorer"
    assert html =~ "Arrow"
    assert html =~ "Zoom"
    assert html =~ "Relationships"
    assert html =~ "Auto"
  end

  defp create_user!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      ControlPlane.register_user(%{
        email: "#{prefix}-#{suffix}@example.com",
        name: "Tenant Graph User #{suffix}",
        password: "threadr-password-#{suffix}"
      })

    user
  end

  defp create_tenant!(name_prefix, owner_user) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(
        %{
          name: "#{name_prefix} #{suffix}",
          subject_name: "graph-live-#{suffix}"
        },
        owner_user: owner_user
      )

    tenant
  end
end
