defmodule Threadr.TenantData.ExtractionTest do
  use Threadr.DataCase, async: false

  import Ash.Expr
  require Ash.Query

  alias Threadr.ControlPlane.Service
  alias Threadr.Events.{ChatMessage, Envelope}
  alias Threadr.Messaging.Topology
  alias Threadr.TenantData.{ExtractedEntity, ExtractedFact, Extraction, Ingest}

  test "extracts and persists structured entities and facts for a message" do
    tenant = create_tenant!("Extraction Tenant")

    envelope =
      Envelope.new(
        ChatMessage.from_map(%{
          platform: "discord",
          actor: "alice",
          channel: "ops",
          body: "Alice told Bob that payroll access was limited on 2026-03-05.",
          mentions: ["bob"],
          observed_at: ~U[2026-03-05 12:00:00Z],
          raw: %{"body" => "Alice told Bob that payroll access was limited on 2026-03-05."}
        }),
        "chat.message",
        Topology.subject_for(:chat_messages, tenant.subject_name),
        %{source: "discord", occurred_at: ~U[2026-03-05 12:00:00Z]}
      )

    {:ok, message} = Ingest.persist_envelope(envelope)

    assert {:ok, persisted} =
             Extraction.extract_and_persist_message(
               message,
               tenant.subject_name,
               tenant.schema_name,
               provider: Threadr.TestExtractionProvider,
               generation_provider: Threadr.TestGenerationProvider,
               model: "test-llm"
             )

    assert length(persisted.persisted.entities) == 2
    assert length(persisted.persisted.facts) == 1

    assert {:ok, entity} =
             ExtractedEntity
             |> Ash.Query.filter(expr(name == "Alice"))
             |> Ash.read_one(tenant: tenant.schema_name)

    assert entity.entity_type == "person"

    assert {:ok, fact} =
             ExtractedFact
             |> Ash.Query.filter(expr(subject == "Bob"))
             |> Ash.read_one(tenant: tenant.schema_name)

    assert fact.predicate == "reported"
  end

  defp create_tenant!(name_prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(%{
        name: "#{name_prefix} #{suffix}",
        subject_name: "extraction-test-#{suffix}"
      })

    tenant
  end
end
