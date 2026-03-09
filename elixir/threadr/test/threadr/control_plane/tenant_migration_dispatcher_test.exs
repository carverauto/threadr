defmodule Threadr.ControlPlane.TenantMigrationDispatcherTest do
  use ExUnit.Case, async: true

  alias Threadr.ControlPlane.TenantMigrationDispatcher

  test "tenant_requires_migration?/2 returns true for pending tenants" do
    tenant = %{
      schema_name: "tenant_pending",
      status: "active",
      tenant_migration_status: "pending",
      tenant_migration_version: nil
    }

    assert TenantMigrationDispatcher.tenant_requires_migration?(tenant, 20_260_308_195_500)
  end

  test "tenant_requires_migration?/2 returns true for stale succeeded tenants" do
    tenant = %{
      schema_name: "tenant_stale",
      status: "active",
      tenant_migration_status: "succeeded",
      tenant_migration_version: 20_260_308_195_400
    }

    assert TenantMigrationDispatcher.tenant_requires_migration?(tenant, 20_260_308_195_500)
  end

  test "tenant_requires_migration?/2 returns false for current succeeded tenants" do
    latest = 20_260_308_195_500

    tenant = %{
      schema_name: "tenant_current",
      status: "active",
      tenant_migration_status: "succeeded",
      tenant_migration_version: latest
    }

    refute TenantMigrationDispatcher.tenant_requires_migration?(tenant, latest)
  end

  test "tenant_requires_migration?/2 returns false for inactive tenants" do
    tenant = %{
      schema_name: "tenant_inactive",
      status: "disabled",
      tenant_migration_status: "pending",
      tenant_migration_version: nil
    }

    refute TenantMigrationDispatcher.tenant_requires_migration?(tenant, 20_260_308_195_500)
  end
end
