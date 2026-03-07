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
    assert html =~ "Investigation Window"
    assert html =~ "Selection"
    assert html =~ "graph-selection-panel"
    assert html =~ "/control-plane/tenants/#{tenant.subject_name}/history"
    assert html =~ "/control-plane/tenants/#{tenant.subject_name}/qa"
  end

  test "hydrates graph time window from query params", %{conn: conn} do
    user = create_user!("tenant-graph-window")
    tenant = create_tenant!("Graph Window Tenant", user)

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, _view, html} =
      live(
        conn,
        ~p"/control-plane/tenants/#{tenant.subject_name}/graph?#{%{since: "2026-03-05T11:30:00", until: "2026-03-05T12:30:00"}}"
      )

    assert html =~ ~s(value="2026-03-05T11:30:00")
    assert html =~ ~s(value="2026-03-05T12:30:00")
    assert html =~ ~s(data-since="2026-03-05T11:30:00")
    assert html =~ ~s(data-until="2026-03-05T12:30:00")
  end

  test "hydrates graph compare context from query params without surfacing compare controls", %{conn: conn} do
    user = create_user!("tenant-graph-compare-window")
    tenant = create_tenant!("Graph Compare Window Tenant", user)

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, _view, html} =
      live(
        conn,
        ~p"/control-plane/tenants/#{tenant.subject_name}/graph?#{%{since: "2026-03-05T11:30:00", until: "2026-03-05T12:30:00", compare_since: "2026-03-05T12:30:00", compare_until: "2026-03-05T13:30:00", node_kind: "actor", node_id: "123"}}"
      )

    assert html =~ ~s(data-compare-since="2026-03-05T12:30:00")
    assert html =~ ~s(data-compare-until="2026-03-05T13:30:00")
    refute html =~ ~s(id="graph-compare-since")
    refute html =~ ~s(id="graph-compare-until")
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
