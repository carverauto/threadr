defmodule Threadr.TenantData.IngestTest do
  use Threadr.DataCase, async: false

  import Ash.Expr
  require Ash.Query

  alias Threadr.ControlPlane.Service
  alias Threadr.Events.{ChatMessage, Envelope}
  alias Threadr.Messaging.Topology
  alias Threadr.TenantData.{Graph, Ingest, Relationship, RelationshipObservation}

  test "projects persisted messages into AGE and infers co-mentioned relationships idempotently" do
    tenant = create_tenant!("AGE Graph")
    observed_at = DateTime.utc_now() |> DateTime.truncate(:second)
    external_id = Ecto.UUID.generate()

    envelope =
      Envelope.new(
        ChatMessage.from_map(%{
          platform: "discord",
          channel: "ops",
          actor: "alice",
          body: "Alice mentioned Bob and Carol in incident response planning.",
          mentions: ["bob", "carol"],
          observed_at: observed_at,
          raw: %{"text" => "Alice mentioned Bob and Carol in incident response planning."}
        }),
        "chat.message",
        Topology.subject_for(:chat_messages, tenant.subject_name),
        %{id: external_id}
      )

    assert {:ok, message} = Ingest.persist_envelope(envelope)

    relationships = fetch_relationships(tenant.schema_name, message.id)

    assert Enum.sort(Enum.map(relationships, & &1.relationship_type)) == [
             "CO_MENTIONED",
             "MENTIONED",
             "MENTIONED"
           ]

    assert Enum.all?(relationships, &(&1.weight == 1))

    co_mentioned =
      Enum.find(relationships, &(&1.relationship_type == "CO_MENTIONED"))

    assert co_mentioned.metadata["source"] == "age.co_mentions"

    observations = fetch_relationship_observations(tenant.schema_name, message.id)

    assert length(observations) == 3

    graph_name = Graph.graph_name(tenant.schema_name)

    assert vertex_count(graph_name, "Actor") == 3
    assert vertex_count(graph_name, "Channel") == 1
    assert vertex_count(graph_name, "Message") == 1
    assert edge_count(graph_name, "SENT") == 1
    assert edge_count(graph_name, "IN_CHANNEL") == 1
    assert edge_count(graph_name, "MENTIONS") == 2
    assert edge_count(graph_name, "RELATES_TO") == 3

    assert {:ok, same_message} = Ingest.persist_envelope(envelope)
    assert same_message.id == message.id

    relationships_after_replay = fetch_relationships(tenant.schema_name, message.id)
    observations_after_replay = fetch_relationship_observations(tenant.schema_name, message.id)

    assert length(relationships_after_replay) == 3
    assert Enum.all?(relationships_after_replay, &(&1.weight == 1))
    assert length(observations_after_replay) == 3
    assert edge_count(graph_name, "MENTIONS") == 2
    assert edge_count(graph_name, "RELATES_TO") == 3
  end

  defp create_tenant!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(%{
        name: "#{prefix} #{suffix}",
        subject_name: "tenant-age-#{suffix}"
      })

    tenant
  end

  defp fetch_relationships(tenant_schema, message_id) do
    Relationship
    |> Ash.Query.filter(expr(source_message_id == ^message_id))
    |> Ash.read!(tenant: tenant_schema)
  end

  defp fetch_relationship_observations(tenant_schema, message_id) do
    RelationshipObservation
    |> Ash.Query.filter(expr(source_message_id == ^message_id))
    |> Ash.read!(tenant: tenant_schema)
  end

  defp vertex_count(graph_name, label_name) do
    {:ok, %{rows: [[count]]}} =
      Repo.query("SELECT count(*)::int FROM #{qualified_table(graph_name, label_name)}")

    count
  end

  defp edge_count(graph_name, label_name) do
    {:ok, %{rows: [[count]]}} =
      Repo.query("SELECT count(*)::int FROM #{qualified_table(graph_name, label_name)}")

    count
  end

  defp qualified_table(graph_name, label_name) do
    "#{quote_ident(graph_name)}.#{quote_ident(label_name)}"
  end

  defp quote_ident(value) do
    escaped = String.replace(to_string(value), "\"", "\"\"")
    ~s("#{escaped}")
  end
end
