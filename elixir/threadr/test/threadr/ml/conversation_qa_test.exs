defmodule Threadr.ML.ConversationQATest do
  use Threadr.DataCase, async: false

  alias Threadr.ControlPlane.Service
  alias Threadr.ML.ConversationQA

  alias Threadr.TenantData.{
    Actor,
    Channel,
    ConversationAttachment,
    ExtractedEntity,
    Message,
    MessageLinkInference
  }

  test "answers what two actors talked about from reconstructed conversations" do
    tenant = create_tenant!("Conversation QA")
    alice = create_actor!(tenant.schema_name, "alice")
    bob = create_actor!(tenant.schema_name, "bob")
    channel = create_channel!(tenant.schema_name, "ops")

    question_message =
      create_message!(
        tenant.schema_name,
        alice.id,
        channel.id,
        "Can you validate web-4 before deploy?",
        "msg-question",
        ~U[2026-03-08 10:00:00Z],
        %{
          "dialogue_act" => %{"label" => "request", "confidence" => 0.92},
          "conversation_external_id" => "ops"
        }
      )

    answer_message =
      create_message!(
        tenant.schema_name,
        bob.id,
        channel.id,
        "Yes, I validated web-4 before deploy.",
        "msg-answer",
        ~U[2026-03-08 10:05:00Z],
        %{
          "dialogue_act" => %{"label" => "status_update", "confidence" => 0.86},
          "reply_to_external_id" => question_message.external_id,
          "conversation_external_id" => "ops"
        }
      )

    create_entity!(tenant.schema_name, question_message.id, "artifact", "web-4")
    create_entity!(tenant.schema_name, answer_message.id, "artifact", "web-4")

    {:ok, _initial_conversation} =
      ConversationAttachment.attach_message(
        question_message.id,
        tenant.schema_name
      )

    {:ok, inference} =
      MessageLinkInference.infer_and_persist(answer_message.id, tenant.schema_name)

    {:ok, _conversation} =
      ConversationAttachment.attach_message(
        answer_message.id,
        tenant.schema_name,
        inference: inference
      )

    assert {:ok, result} =
             ConversationQA.answer_question(
               tenant.subject_name,
               "What did Alice and Bob talk about last week?",
               generation_provider: Threadr.TestGenerationProvider,
               generation_model: "test-chat"
             )

    assert result.query.kind == :talked_with
    assert result.query.retrieval == "reconstructed_conversations"
    assert result.query.actor_handle == "alice"
    assert result.query.target_actor_handle == "bob"
    assert length(result.conversations) == 1
    assert length(result.citations) == 2
    assert result.context =~ "Conversation-focused QA for what alice talked about with bob."
    assert result.context =~ "web-4"
    assert result.answer.content =~ "What did Alice and Bob talk about last week?"
  end

  defp create_tenant!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(%{
        name: "#{prefix} #{suffix}",
        subject_name: "conversation-qa-#{suffix}"
      })

    tenant
  end

  defp create_actor!(tenant_schema, handle) do
    Actor
    |> Ash.Changeset.for_create(
      :create,
      %{platform: "irc", handle: handle, display_name: String.capitalize(handle)},
      tenant: tenant_schema
    )
    |> Ash.create!()
  end

  defp create_channel!(tenant_schema, name) do
    Channel
    |> Ash.Changeset.for_create(
      :create,
      %{platform: "irc", name: name},
      tenant: tenant_schema
    )
    |> Ash.create!()
  end

  defp create_message!(
         tenant_schema,
         actor_id,
         channel_id,
         body,
         external_id,
         observed_at,
         metadata
       ) do
    Message
    |> Ash.Changeset.for_create(
      :create,
      %{
        external_id: external_id,
        body: body,
        observed_at: observed_at,
        raw: %{"body" => body},
        metadata: metadata,
        actor_id: actor_id,
        channel_id: channel_id
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
