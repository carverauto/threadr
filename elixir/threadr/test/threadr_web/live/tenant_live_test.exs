defmodule ThreadrWeb.TenantLiveTest do
  use ThreadrWeb.ConnCase, async: false

  import AshAuthentication.Phoenix.Plug, only: [store_in_session: 2]
  import Phoenix.LiveViewTest

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Service

  test "lists tenants and migration state", %{conn: conn} do
    user = create_user!("tenant-live")
    tenant = create_tenant!("Live Tenant", user)

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, _view, html} = live(conn, ~p"/control-plane/tenants")

    assert html =~ "Control Plane"
    assert html =~ tenant.name
    assert html =~ tenant.subject_name
    assert html =~ tenant.schema_name
    assert html =~ "succeeded"
    assert html =~ Integer.to_string(Service.latest_tenant_migration_version())
  end

  test "migrate action refreshes tenant state", %{conn: conn} do
    user = create_user!("tenant-retry")
    tenant = create_tenant!("Retry Tenant", user)

    {:ok, tenant} =
      ControlPlane.update_tenant(
        tenant,
        %{
          tenant_migration_status: "pending",
          tenant_migration_version: nil,
          tenant_migrated_at: nil,
          tenant_migration_error: "stale schema"
        },
        context: %{system: true}
      )

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, view, _html} = live(conn, ~p"/control-plane/tenants")

    view
    |> element("[data-role='migrate-tenant'][data-subject-name='#{tenant.subject_name}']")
    |> render_click()

    assert render(view) =~ "Migration completed for #{tenant.subject_name}"

    {:ok, migrated} =
      ControlPlane.get_tenant_by_subject_name(tenant.subject_name, context: %{system: true})

    assert migrated.tenant_migration_status == "succeeded"
    assert migrated.tenant_migration_version == Service.latest_tenant_migration_version()
    assert migrated.tenant_migration_error == nil
  end

  test "owner can create a tenant from the control plane UI", %{conn: conn} do
    user = create_user!("tenant-create")

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, view, _html} = live(conn, ~p"/control-plane/tenants")

    suffix = System.unique_integer([:positive])

    view
    |> form("form[phx-submit='create_tenant']",
      tenant: %{
        name: "Created Tenant #{suffix}",
        subject_name: "created-tenant-#{suffix}"
      }
    )
    |> render_submit()

    assert render(view) =~ "Tenant created: created-tenant-#{suffix}"
    assert render(view) =~ "Created Tenant #{suffix}"

    {:ok, tenant} =
      ControlPlane.get_tenant_by_subject_name("created-tenant-#{suffix}",
        context: %{system: true}
      )

    assert tenant.schema_name == "tenant_created_tenant_#{suffix}"
  end

  test "non-manager memberships do not see the migrate action", %{conn: conn} do
    owner = create_user!("tenant-owner")
    member = create_user!("tenant-member")
    tenant = create_tenant!("Member Tenant", owner)

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
      |> init_test_session(%{})
      |> store_in_session(member)

    {:ok, _view, html} = live(conn, ~p"/control-plane/tenants")

    assert html =~ "member"
    refute html =~ "data-role=\"migrate-tenant\""
  end

  defp create_user!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      ControlPlane.register_user(%{
        email: "#{prefix}-#{suffix}@example.com",
        name: "Tenant User #{suffix}",
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
          subject_name: "live-tenant-#{suffix}"
        },
        owner_user: owner_user
      )

    tenant
  end
end
