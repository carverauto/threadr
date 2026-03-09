defmodule Threadr.TenantData.ConversationAttachmentTest do
  use Threadr.DataCase, async: false

  import Ash.Expr
  require Ash.Query

  alias Threadr.ControlPlane.Service

  alias Threadr.TenantData.{
    Actor,
    Channel,
    ConversationAttachment,
    ConversationMembership,
    ExtractedEntity,
    Message,
    MessageLinkInference
  }

  alias Threadr.TenantData.PendingItem

  test "creates a conversation from a linked reply and attaches both messages and actors" do
    tenant = create_tenant!("Conversation Attachment")
    channel = create_channel!(tenant.schema_name, "ops")
    alice = create_actor!(tenant.schema_name, "alice")
    bob = create_actor!(tenant.schema_name, "bob")

    question =
      create_message!(
        tenant.schema_name,
        bob,
        channel,
        "Did web-2 finish?",
        "msg-question",
        ~U[2026-03-08 15:00:00Z],
        %{
          "dialogue_act" => %{"label" => "question", "confidence" => 0.95},
          "conversation_external_id" => "ops"
        }
      )

    answer =
      create_message!(
        tenant.schema_name,
        alice,
        channel,
        "Yes, web-2 is done.",
        "msg-answer",
        ~U[2026-03-08 15:03:00Z],
        %{
          "dialogue_act" => %{"label" => "answer", "confidence" => 0.96},
          "reply_to_external_id" => "msg-question",
          "conversation_external_id" => "ops"
        }
      )

    create_entity!(tenant.schema_name, question.id, "artifact", "web-2")
    create_entity!(tenant.schema_name, answer.id, "artifact", "web-2")

    assert {:ok, inference} =
             MessageLinkInference.infer_and_persist(answer.id, tenant.schema_name)

    assert {:ok, conversation} =
             ConversationAttachment.attach_message(
               answer.id,
               tenant.schema_name,
               inference: inference
             )

    assert conversation.lifecycle_state in ["active", "revived"]
    assert conversation.starter_message_id == question.id
    assert conversation.most_recent_message_id == answer.id
    assert conversation.participant_summary["actor_ids"] == Enum.sort([alice.id, bob.id])

    memberships = fetch_memberships(tenant.schema_name, conversation.id)

    assert Enum.sort(Enum.map(memberships, &{&1.member_kind, &1.member_id})) ==
             Enum.sort([
               {"actor", alice.id},
               {"actor", bob.id},
               {"message", answer.id},
               {"message", question.id}
             ])
  end

  test "revives a dormant conversation when a linked answer arrives later" do
    tenant = create_tenant!("Conversation Revival")
    channel = create_channel!(tenant.schema_name, "ops")
    alice = create_actor!(tenant.schema_name, "alice")
    bob = create_actor!(tenant.schema_name, "bob")

    question =
      create_message!(
        tenant.schema_name,
        bob,
        channel,
        "Can you validate web-9?",
        "msg-question",
        ~U[2026-03-06 09:00:00Z],
        %{
          "dialogue_act" => %{"label" => "request", "confidence" => 0.9},
          "conversation_external_id" => "ops"
        }
      )

    create_entity!(tenant.schema_name, question.id, "artifact", "web-9")

    assert {:ok, original_conversation} =
             ConversationAttachment.attach_message(question.id, tenant.schema_name)

    answer =
      create_message!(
        tenant.schema_name,
        alice,
        channel,
        "I validated web-9 successfully.",
        "msg-answer",
        ~U[2026-03-08 18:00:00Z],
        %{
          "dialogue_act" => %{"label" => "status_update", "confidence" => 0.87},
          "reply_to_external_id" => "msg-question",
          "conversation_external_id" => "ops"
        }
      )

    create_entity!(tenant.schema_name, answer.id, "artifact", "web-9")

    assert {:ok, inference} =
             MessageLinkInference.infer_and_persist(answer.id, tenant.schema_name)

    assert {:ok, revived} =
             ConversationAttachment.attach_message(
               answer.id,
               tenant.schema_name,
               inference: inference
             )

    assert revived.id == original_conversation.id
    assert revived.lifecycle_state == "revived"
    assert revived.most_recent_message_id == answer.id
    assert revived.participant_summary["actor_ids"] == Enum.sort([alice.id, bob.id])
  end

  test "opens and resolves pending items through conversation attachment" do
    tenant = create_tenant!("Pending Item Attachment")
    channel = create_channel!(tenant.schema_name, "ops")
    alice = create_actor!(tenant.schema_name, "alice")
    bob = create_actor!(tenant.schema_name, "bob")

    request =
      create_message!(
        tenant.schema_name,
        bob,
        channel,
        "Can you validate web-4?",
        "msg-request",
        ~U[2026-03-08 10:00:00Z],
        %{
          "dialogue_act" => %{"label" => "request", "confidence" => 0.92},
          "conversation_external_id" => "ops"
        }
      )

    create_entity!(tenant.schema_name, request.id, "artifact", "web-4")

    assert {:ok, conversation} =
             ConversationAttachment.attach_message(request.id, tenant.schema_name)

    assert conversation.open_pending_item_count == 1

    assert {:ok, pending_item} =
             PendingItem
             |> Ash.Query.filter(expr(opener_message_id == ^request.id))
             |> Ash.read_one(tenant: tenant.schema_name)

    assert pending_item.item_kind == "request"
    assert pending_item.status == "open"

    completion =
      create_message!(
        tenant.schema_name,
        alice,
        channel,
        "I validated web-4 successfully.",
        "msg-complete",
        ~U[2026-03-08 10:05:00Z],
        %{
          "dialogue_act" => %{"label" => "status_update", "confidence" => 0.86},
          "reply_to_external_id" => "msg-request",
          "conversation_external_id" => "ops"
        }
      )

    create_entity!(tenant.schema_name, completion.id, "artifact", "web-4")

    assert {:ok, inference} =
             MessageLinkInference.infer_and_persist(completion.id, tenant.schema_name)

    assert {:ok, updated_conversation} =
             ConversationAttachment.attach_message(
               completion.id,
               tenant.schema_name,
               inference: inference
             )

    assert updated_conversation.open_pending_item_count == 0

    assert {:ok, resolved_item} =
             PendingItem
             |> Ash.Query.filter(expr(opener_message_id == ^request.id))
             |> Ash.read_one(tenant: tenant.schema_name)

    assert resolved_item.status == "completed"
    assert resolved_item.resolver_message_id == completion.id

    memberships = fetch_memberships(tenant.schema_name, updated_conversation.id)
    assert Enum.any?(memberships, &(&1.member_kind == "pending_item"))
  end

  defp create_tenant!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(%{
        name: "#{prefix} #{suffix}",
        subject_name: "conversation-attachment-#{suffix}"
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

  defp fetch_memberships(tenant_schema, conversation_id) do
    ConversationMembership
    |> Ash.Query.filter(expr(conversation_id == ^conversation_id))
    |> Ash.read!(tenant: tenant_schema)
  end
end
