defmodule Threadr.TenantData.GraphInspectorTest do
  use Threadr.DataCase, async: false

  import Ecto.Query

  alias Threadr.ControlPlane.Service
  alias Threadr.Events.{ChatMessage, Envelope}
  alias Threadr.Messaging.Topology
  alias Threadr.TenantData.{GraphInspector, Ingest}

  test "describes actor nodes with recent messages and graph neighborhood context" do
    tenant = create_tenant!("Graph Inspector")
    observed_at = DateTime.utc_now() |> DateTime.truncate(:second)

    assert {:ok, _message_one} =
             persist_message(tenant, %{
               platform: "discord",
               channel: "ops",
               actor: "alice",
               body: "Alice mentioned Bob in the ops channel.",
               mentions: ["bob"],
               observed_at: observed_at
             })

    assert {:ok, _message_two} =
             persist_message(tenant, %{
               platform: "discord",
               channel: "alerts",
               actor: "alice",
               body: "Alice mentioned Carol while triaging alerts.",
               mentions: ["carol"],
               observed_at: DateTime.add(observed_at, 5, :second)
             })

    [alice_id] =
      Repo.all(
        from(a in "actors",
          prefix: ^tenant.schema_name,
          where: a.handle == "alice",
          select: a.id
        )
      )
      |> Enum.map(&Ecto.UUID.load!/1)

    assert {:ok, detail} = GraphInspector.describe_node(alice_id, "actor", tenant.schema_name)

    assert detail.type == "actor"
    assert detail.focal.handle == "alice"
    assert detail.summary.message_count == 2
    assert Enum.any?(detail.top_channels, &(&1.channel_name == "ops"))
    assert Enum.any?(detail.top_channels, &(&1.channel_name == "alerts"))
    assert Enum.any?(detail.recent_messages, &(String.contains?(&1.body, "Carol")))
    assert Enum.any?(detail.neighborhood.actors, &(&1.handle == "bob"))
    assert Enum.any?(detail.neighborhood.actors, &(&1.handle == "carol"))
    assert length(detail.top_relationships) >= 2
  end

  defp create_tenant!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(%{
        name: "#{prefix} #{suffix}",
        subject_name: "graph-inspector-#{suffix}"
      })

    tenant
  end

  defp persist_message(tenant, attrs) do
    envelope =
      Envelope.new(
        ChatMessage.from_map(
          Map.merge(attrs, %{
            raw: %{"body" => attrs.body}
          })
        ),
        "chat.message",
        Topology.subject_for(:chat_messages, tenant.subject_name),
        %{id: Ecto.UUID.generate()}
      )

    Ingest.persist_envelope(envelope)
  end
end
