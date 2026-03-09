defmodule Threadr.ControlPlane.ServiceTest do
  use Threadr.DataCase, async: false

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Service

  test "slugify derives a stable slug from a tenant name" do
    assert Service.slugify("Acme Threat Intel") == "acme-threat-intel"
  end

  test "schema_name_from_slug produces a schema-safe tenant prefix" do
    assert Service.schema_name_from_slug("acme-threat-intel") == "tenant_acme_threat_intel"
  end

  test "subject_name_from_slug produces a NATS-safe token" do
    assert Service.subject_name_from_slug("acme-threat-intel") == "acme-threat-intel"
    assert Service.subject_name_from_slug("Acme Threat Intel!") == "acme-threat-intel"
  end

  test "normalize_tenant_attrs fills missing slug and schema_name" do
    attrs = Service.normalize_tenant_attrs(%{name: "Acme Threat Intel"})

    assert attrs.slug == "acme-threat-intel"
    assert attrs.schema_name == "tenant_acme_threat_intel"
    assert attrs.subject_name == "acme-threat-intel"
  end

  test "normalize_tenant_attrs preserves explicit schema_name" do
    attrs =
      Service.normalize_tenant_attrs(%{
        "name" => "Acme Threat Intel",
        "slug" => "acme-threat-intel",
        "schema_name" => "custom_schema"
      })

    assert attrs["schema_name"] == "custom_schema"
  end

  test "create_tenant runs tenant-schema migrations before reporting success" do
    owner = create_user!("owner")
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(
        %{
          name: "Migrated Tenant #{suffix}",
          subject_name: "migrated-tenant-#{suffix}"
        },
        owner_user: owner
      )

    assert tenant.tenant_migration_status == "succeeded"
    assert tenant.tenant_migration_version == Service.latest_tenant_migration_version()
    assert not is_nil(tenant.tenant_migrated_at)

    assert tenant_table_exists?(tenant.schema_name, "aliases")
    assert tenant_table_exists?(tenant.schema_name, "alias_observations")
    assert tenant_table_exists?(tenant.schema_name, "conversations")
    assert tenant_table_exists?(tenant.schema_name, "conversation_memberships")
  end

  defp tenant_table_exists?(schema_name, table_name) do
    result =
      Threadr.Repo.query!(
        "SELECT to_regclass($1) IS NOT NULL AS exists",
        ["#{schema_name}.#{table_name}"]
      )

    [[exists?]] = result.rows
    exists?
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
end
