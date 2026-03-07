defmodule Threadr.Messaging.TopologyTest do
  use ExUnit.Case, async: true

  alias Threadr.Messaging.Topology

  test "builds tenant-scoped chat subjects from tenant subject names" do
    assert Topology.subject_for(:chat_messages, "acme-threat-intel") ==
             "threadr.tenants.acme-threat-intel.chat.message"
  end

  test "parses the tenant subject name from a tenant-scoped subject" do
    assert Topology.tenant_subject_name_from_subject(
             "threadr.tenants.acme-threat-intel.processing.result"
           ) == {:ok, "acme-threat-intel"}
  end

  test "rejects invalid tenant subject names" do
    assert_raise ArgumentError, fn ->
      Topology.subject_for(:chat_messages, "acme threat intel")
    end
  end
end
