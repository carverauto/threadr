defmodule Threadr.ControlPlane.ServiceTest do
  use ExUnit.Case, async: true

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
end
