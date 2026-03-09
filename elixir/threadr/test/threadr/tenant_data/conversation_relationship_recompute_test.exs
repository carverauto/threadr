defmodule Threadr.TenantData.ConversationRelationshipRecomputeTest do
  use Threadr.DataCase, async: false

  import Ash.Expr
  require Ash.Query

  alias Threadr.ControlPlane.Service

  alias Threadr.TenantData.{
    Actor,
    Channel,
    Conversation,
    ConversationAttachment,
    ConversationRelationshipDispatcher,
    ConversationRelationshipRecompute,
    ExtractedEntity,
    Message,
    MessageLinkInference,
    PendingItem,
    Relationship
  }

  test "recomputes interacted and answered relationships from reconstructed conversations with decay" do
    tenant = create_tenant!("Conversation Relationship")
    channel = create_channel!(tenant.schema_name, "ops-relationships")
    alice = create_actor!(tenant.schema_name, "alice-relationships")
    bob = create_actor!(tenant.schema_name, "bob-relationships")

    older_conversation =
      create_reconstructed_conversation!(
        tenant.schema_name,
        bob,
        alice,
        channel,
        "ops-old",
        "Can you validate web-1?",
        "I validated web-1 successfully.",
        ~U[2026-01-08 10:00:00Z],
        "web-1"
      )

    recent_conversation =
      create_reconstructed_conversation!(
        tenant.schema_name,
        bob,
        alice,
        channel,
        "ops-recent",
        "Can you validate web-2?",
        "I validated web-2 successfully.",
        ~U[2026-03-08 10:00:00Z],
        "web-2"
      )

    assert {:ok, %{conversation: updated, relationships: relationships}} =
             ConversationRelationshipRecompute.recompute_conversation_relationships(
               recent_conversation.id,
               tenant.schema_name
             )

    assert updated.metadata["relationship_recompute_needs_refresh"] == false

    assert Enum.any?(relationships, &(&1.relationship_type == "INTERACTED_WITH"))
    assert Enum.any?(relationships, &(&1.relationship_type == "ANSWERED"))

    assert {:ok, interacted} =
             Relationship
             |> Ash.Query.filter(
               expr(
                 relationship_type == "INTERACTED_WITH" and from_actor_id == ^alice.id and
                   to_actor_id == ^bob.id
               )
             )
             |> Ash.read_one(tenant: tenant.schema_name)

    assert interacted.weight >= 2
    assert interacted.metadata["shared_conversation_count"] == 2
    assert interacted.metadata["raw_score"] > interacted.metadata["decayed_score"]

    assert Enum.sort(interacted.metadata["conversation_ids"]) ==
             Enum.sort([older_conversation.id, recent_conversation.id])

    assert {:ok, answered} =
             Relationship
             |> Ash.Query.filter(
               expr(
                 relationship_type == "ANSWERED" and from_actor_id == ^alice.id and
                   to_actor_id == ^bob.id
               )
             )
             |> Ash.read_one(tenant: tenant.schema_name)

    assert answered.weight >= 1
    assert answered.metadata["answered_pending_item_count"] == 2
  end

  test "dispatcher drains pending relationship recomputes" do
    tenant = create_tenant!("Conversation Relationship Dispatcher")
    channel = create_channel!(tenant.schema_name, "ops-dispatch")
    alice = create_actor!(tenant.schema_name, "alice-rel-dispatch")
    bob = create_actor!(tenant.schema_name, "bob-rel-dispatch")

    conversation =
      create_reconstructed_conversation!(
        tenant.schema_name,
        bob,
        alice,
        channel,
        "ops-dispatch",
        "Can you validate web-7?",
        "I validated web-7 successfully.",
        ~U[2026-03-08 11:00:00Z],
        "web-7"
      )

    assert :ok = ConversationRelationshipDispatcher.process_pending_once()

    assert {:ok, refreshed} =
             Conversation
             |> Ash.Query.filter(expr(id == ^conversation.id))
             |> Ash.read_one(tenant: tenant.schema_name)

    assert refreshed.metadata["relationship_recompute_needs_refresh"] == false

    assert {:ok, relationship} =
             Relationship
             |> Ash.Query.filter(
               expr(
                 relationship_type == "INTERACTED_WITH" and from_actor_id == ^alice.id and
                   to_actor_id == ^bob.id
               )
             )
             |> Ash.read_one(tenant: tenant.schema_name)

    assert relationship.metadata["source"] == "conversation_interaction"
  end

  defp create_reconstructed_conversation!(
         tenant_schema,
         starter_actor,
         reply_actor,
         channel,
         conversation_external_id,
         question_body,
         answer_body,
         observed_at,
         entity_name
       ) do
    question =
      create_message!(
        tenant_schema,
        starter_actor,
        channel,
        question_body,
        "msg-question-#{conversation_external_id}",
        observed_at,
        %{
          "dialogue_act" => %{"label" => "request", "confidence" => 0.92},
          "conversation_external_id" => conversation_external_id
        }
      )

    answer =
      create_message!(
        tenant_schema,
        reply_actor,
        channel,
        answer_body,
        "msg-answer-#{conversation_external_id}",
        DateTime.add(observed_at, 300, :second),
        %{
          "dialogue_act" => %{"label" => "status_update", "confidence" => 0.86},
          "reply_to_external_id" => question.external_id,
          "conversation_external_id" => conversation_external_id
        }
      )

    create_entity!(tenant_schema, question.id, "artifact", entity_name)
    create_entity!(tenant_schema, answer.id, "artifact", entity_name)

    {:ok, _initial_conversation} =
      ConversationAttachment.attach_message(
        question.id,
        tenant_schema
      )

    {:ok, inference} = MessageLinkInference.infer_and_persist(answer.id, tenant_schema)

    {:ok, conversation} =
      ConversationAttachment.attach_message(
        answer.id,
        tenant_schema,
        inference: inference
      )

    assert {:ok, pending_item} =
             PendingItem
             |> Ash.Query.filter(expr(opener_message_id == ^question.id))
             |> Ash.read_one(tenant: tenant_schema)

    assert pending_item.status in ["completed", "answered"]

    conversation
  end

  defp create_tenant!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(%{
        name: "#{prefix} #{suffix}",
        subject_name: "conversation-relationship-#{suffix}"
      })

    tenant
  end

  defp create_actor!(tenant_schema, handle) do
    Actor
    |> Ash.Changeset.for_create(
      :create,
      %{platform: "discord", handle: handle, display_name: String.capitalize(handle)},
      tenant: tenant_schema
    )
    |> Ash.create!()
  end

  defp create_channel!(tenant_schema, name) do
    Channel
    |> Ash.Changeset.for_create(:create, %{platform: "discord", name: name},
      tenant: tenant_schema
    )
    |> Ash.create!()
  end

  defp create_message!(tenant_schema, actor, channel, body, external_id, observed_at, metadata) do
    Message
    |> Ash.Changeset.for_create(
      :create,
      %{
        external_id: external_id,
        body: body,
        observed_at: observed_at,
        metadata: metadata,
        raw: %{},
        actor_id: actor.id,
        channel_id: channel.id
      },
      tenant: tenant_schema
    )
    |> Ash.create!()
  end

  defp create_entity!(tenant_schema, message_id, entity_type, name) do
    ExtractedEntity
    |> Ash.Changeset.for_create(
      :create,
      %{
        entity_type: entity_type,
        name: name,
        canonical_name: name,
        confidence: 0.9,
        metadata: %{},
        source_message_id: message_id
      },
      tenant: tenant_schema
    )
    |> Ash.create!()
  end
end
