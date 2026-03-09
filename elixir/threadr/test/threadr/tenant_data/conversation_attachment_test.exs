defmodule Threadr.TenantData.ConversationAttachmentTest do
  use Threadr.DataCase, async: false

  import Ash.Expr
  require Ash.Query

  alias Threadr.ControlPlane.Service

  alias Threadr.TenantData.{
    Actor,
    Channel,
    Conversation,
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

  test "continues a discussion without repeated direct mentions" do
    tenant = create_tenant!("Conversation Continuation")
    channel = create_channel!(tenant.schema_name, "ops")
    alice = create_actor!(tenant.schema_name, "alice")
    bob = create_actor!(tenant.schema_name, "bob")

    opening =
      create_message!(
        tenant.schema_name,
        alice,
        channel,
        "bob: did the backup finish on server xyz?",
        "msg-opening",
        ~U[2026-03-08 12:00:00Z],
        %{
          "dialogue_act" => %{"label" => "question", "confidence" => 0.94},
          "conversation_external_id" => "ops"
        }
      )

    assert {:ok, conversation} =
             ConversationAttachment.attach_message(opening.id, tenant.schema_name)

    response =
      create_message!(
        tenant.schema_name,
        bob,
        channel,
        "I checked it. Looks good.",
        "msg-response",
        ~U[2026-03-08 12:04:00Z],
        %{
          "dialogue_act" => %{"label" => "answer", "confidence" => 0.9},
          "conversation_external_id" => "ops"
        }
      )

    assert {:ok, response_inference} =
             MessageLinkInference.infer_and_persist(response.id, tenant.schema_name)

    assert response_inference.winner.target_message_id == opening.id
    assert Enum.any?(response_inference.winner.evidence, &(&1.kind == "dialogue_act_match"))
    assert Enum.any?(response_inference.winner.evidence, &(&1.kind == "conversation_external_id"))

    assert {:ok, continued} =
             ConversationAttachment.attach_message(
               response.id,
               tenant.schema_name,
               inference: response_inference
             )

    follow_up =
      create_message!(
        tenant.schema_name,
        alice,
        channel,
        "great, ship it",
        "msg-follow-up",
        ~U[2026-03-08 12:06:00Z],
        %{
          "dialogue_act" => %{"label" => "acknowledgement", "confidence" => 0.87},
          "conversation_external_id" => "ops"
        }
      )

    assert {:ok, follow_up_inference} =
             MessageLinkInference.infer_and_persist(follow_up.id, tenant.schema_name)

    assert follow_up_inference.winner == nil

    assert {:ok, final_conversation} =
             ConversationAttachment.attach_message(
               follow_up.id,
               tenant.schema_name,
               inference: follow_up_inference
             )

    assert continued.id == conversation.id
    assert final_conversation.id == conversation.id

    memberships = fetch_memberships(tenant.schema_name, conversation.id)

    assert Enum.count(memberships, &(&1.member_kind == "message")) == 3
    assert Enum.count(memberships, &(&1.member_kind == "actor")) == 2
  end

  test "revives a dormant conversation from a delayed answer without explicit reply metadata" do
    tenant = create_tenant!("Conversation Delayed Revival")
    channel = create_channel!(tenant.schema_name, "ops")
    alice = create_actor!(tenant.schema_name, "alice")
    bob = create_actor!(tenant.schema_name, "bob")

    question =
      create_message!(
        tenant.schema_name,
        bob,
        channel,
        "Can you validate web-9?",
        "msg-delayed-question",
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
        "msg-delayed-answer",
        ~U[2026-03-08 18:00:00Z],
        %{
          "dialogue_act" => %{"label" => "status_update", "confidence" => 0.87},
          "conversation_external_id" => "ops"
        }
      )

    create_entity!(tenant.schema_name, answer.id, "artifact", "web-9")

    assert {:ok, inference} =
             MessageLinkInference.infer_and_persist(answer.id, tenant.schema_name)

    assert inference.winner.target_message_id == question.id
    refute Enum.any?(inference.winner.evidence, &(&1.kind == "explicit_reply"))
    assert Enum.any?(inference.winner.evidence, &(&1.kind == "dialogue_act_match"))
    assert Enum.any?(inference.winner.evidence, &(&1.kind == "entity_overlap"))

    assert {:ok, revived} =
             ConversationAttachment.attach_message(
               answer.id,
               tenant.schema_name,
               inference: inference
             )

    assert revived.id == original_conversation.id
    assert revived.lifecycle_state == "revived"
    assert revived.most_recent_message_id == answer.id
  end

  test "keeps parallel same-channel conversations separate when evidence supports separation" do
    tenant = create_tenant!("Parallel Conversations")
    channel = create_channel!(tenant.schema_name, "ops")
    alice = create_actor!(tenant.schema_name, "alice")
    bob = create_actor!(tenant.schema_name, "bob")
    carol = create_actor!(tenant.schema_name, "carol")
    dave = create_actor!(tenant.schema_name, "dave")

    deploy_question =
      create_message!(
        tenant.schema_name,
        alice,
        channel,
        "Can you validate web-4 before deploy?",
        "msg-deploy-question",
        ~U[2026-03-08 13:00:00Z],
        %{
          "dialogue_act" => %{"label" => "request", "confidence" => 0.92},
          "conversation_external_id" => "ops:deploy"
        }
      )

    incident_question =
      create_message!(
        tenant.schema_name,
        carol,
        channel,
        "Can you check db-3 replication lag?",
        "msg-incident-question",
        ~U[2026-03-08 13:01:00Z],
        %{
          "dialogue_act" => %{"label" => "request", "confidence" => 0.91},
          "conversation_external_id" => "ops:incident"
        }
      )

    create_entity!(tenant.schema_name, deploy_question.id, "artifact", "web-4")
    create_entity!(tenant.schema_name, incident_question.id, "artifact", "db-3")

    assert {:ok, deploy_conversation} =
             ConversationAttachment.attach_message(deploy_question.id, tenant.schema_name)

    assert {:ok, incident_conversation} =
             ConversationAttachment.attach_message(incident_question.id, tenant.schema_name)

    refute deploy_conversation.id == incident_conversation.id

    deploy_answer =
      create_message!(
        tenant.schema_name,
        bob,
        channel,
        "Yes, I validated web-4 before deploy.",
        "msg-deploy-answer",
        ~U[2026-03-08 13:03:00Z],
        %{
          "dialogue_act" => %{"label" => "status_update", "confidence" => 0.86},
          "reply_to_external_id" => "msg-deploy-question",
          "conversation_external_id" => "ops:deploy"
        }
      )

    incident_answer =
      create_message!(
        tenant.schema_name,
        dave,
        channel,
        "db-3 replication lag is back to normal.",
        "msg-incident-answer",
        ~U[2026-03-08 13:04:00Z],
        %{
          "dialogue_act" => %{"label" => "status_update", "confidence" => 0.86},
          "reply_to_external_id" => "msg-incident-question",
          "conversation_external_id" => "ops:incident"
        }
      )

    create_entity!(tenant.schema_name, deploy_answer.id, "artifact", "web-4")
    create_entity!(tenant.schema_name, incident_answer.id, "artifact", "db-3")

    assert {:ok, deploy_inference} =
             MessageLinkInference.infer_and_persist(deploy_answer.id, tenant.schema_name)

    assert {:ok, incident_inference} =
             MessageLinkInference.infer_and_persist(incident_answer.id, tenant.schema_name)

    assert deploy_inference.winner.target_message_id == deploy_question.id
    assert incident_inference.winner.target_message_id == incident_question.id

    assert {:ok, updated_deploy_conversation} =
             ConversationAttachment.attach_message(
               deploy_answer.id,
               tenant.schema_name,
               inference: deploy_inference
             )

    assert {:ok, updated_incident_conversation} =
             ConversationAttachment.attach_message(
               incident_answer.id,
               tenant.schema_name,
               inference: incident_inference
             )

    assert updated_deploy_conversation.id == deploy_conversation.id
    assert updated_incident_conversation.id == incident_conversation.id

    deploy_memberships = fetch_memberships(tenant.schema_name, deploy_conversation.id)
    incident_memberships = fetch_memberships(tenant.schema_name, incident_conversation.id)

    assert Enum.sort(
             for membership <- deploy_memberships,
                 membership.member_kind == "message",
                 do: membership.member_id
           ) ==
             Enum.sort([deploy_question.id, deploy_answer.id])

    assert Enum.sort(
             for membership <- incident_memberships,
                 membership.member_kind == "message",
                 do: membership.member_id
           ) ==
             Enum.sort([incident_question.id, incident_answer.id])
  end

  test "leaves ambiguous low-signal messages unattached to any conversation" do
    tenant = create_tenant!("Conversation Ambiguity")
    channel = create_channel!(tenant.schema_name, "ops")
    alice = create_actor!(tenant.schema_name, "alice")
    bob = create_actor!(tenant.schema_name, "bob")
    carol = create_actor!(tenant.schema_name, "carol")

    _candidate_one =
      create_message!(
        tenant.schema_name,
        bob,
        channel,
        "looking",
        "msg-ambiguous-1",
        ~U[2026-03-08 14:00:00Z],
        %{"conversation_external_id" => "ops"}
      )

    _candidate_two =
      create_message!(
        tenant.schema_name,
        carol,
        channel,
        "same",
        "msg-ambiguous-2",
        ~U[2026-03-08 14:01:00Z],
        %{"conversation_external_id" => "ops"}
      )

    focal =
      create_message!(
        tenant.schema_name,
        alice,
        channel,
        "yeah",
        "msg-ambiguous-3",
        ~U[2026-03-08 14:02:00Z],
        %{"conversation_external_id" => "ops"}
      )

    assert {:ok, inference} = MessageLinkInference.infer_and_persist(focal.id, tenant.schema_name)
    assert inference.winner == nil
    assert length(inference.candidates) >= 2

    assert {:ok, nil} =
             ConversationAttachment.attach_message(
               focal.id,
               tenant.schema_name,
               inference: inference
             )

    assert fetch_conversation_for_message(tenant.schema_name, focal.id) == nil
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

  defp fetch_conversation_for_message(tenant_schema, message_id) do
    ConversationMembership
    |> Ash.Query.filter(expr(member_kind == "message" and member_id == ^message_id))
    |> Ash.read_one!(tenant: tenant_schema)
    |> case do
      nil ->
        nil

      membership ->
        Conversation
        |> Ash.Query.filter(expr(id == ^membership.conversation_id))
        |> Ash.read_one!(tenant: tenant_schema)
    end
  end
end
