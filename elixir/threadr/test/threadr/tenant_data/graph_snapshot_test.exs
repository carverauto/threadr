defmodule Threadr.TenantData.GraphSnapshotTest do
  use Threadr.DataCase, async: false

  alias Threadr.ControlPlane.Service
  alias Threadr.Events.{ChatMessage, Envelope}
  alias Threadr.Messaging.Topology
  alias Threadr.TenantData.{GraphSnapshot, Ingest}

  test "builds a tenant graph snapshot payload from persisted chat data" do
    tenant = create_tenant!("Graph Snapshot")

    envelope =
      Envelope.new(
        ChatMessage.from_map(%{
          platform: "discord",
          channel: "ops",
          actor: "alice",
          body: "Alice mentioned Bob and Carol in incident response planning.",
          mentions: ["bob", "carol"],
          observed_at: DateTime.utc_now() |> DateTime.truncate(:second),
          raw: %{"body" => "Alice mentioned Bob and Carol in incident response planning."}
        }),
        "chat.message",
        Topology.subject_for(:chat_messages, tenant.subject_name),
        %{id: Ecto.UUID.generate()}
      )

    assert {:ok, _message} = Ingest.persist_envelope(envelope)
    assert {:ok, %{snapshot: snapshot, payload: payload}} = GraphSnapshot.latest_snapshot(tenant)

    assert snapshot.schema_version == GraphSnapshot.schema_version()
    assert snapshot.node_count == 5
    assert snapshot.edge_count == 5
    assert snapshot.bitmap_metadata.root_cause.count == 3
    assert snapshot.bitmap_metadata.affected.count == 1
    assert snapshot.bitmap_metadata.healthy.count == 1
    assert is_binary(payload)
    assert byte_size(payload) > 0
  end

  defp create_tenant!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(%{
        name: "#{prefix} #{suffix}",
        subject_name: "graph-snapshot-#{suffix}"
      })

    tenant
  end
end
