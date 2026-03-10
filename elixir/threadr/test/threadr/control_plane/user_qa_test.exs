defmodule Threadr.ControlPlane.UserQATest do
  use Threadr.DataCase, async: false

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.{Analysis, Service}
  alias Threadr.ML.QARequest

  alias Threadr.TenantData.{
    Actor,
    Channel,
    ConversationAttachment,
    ExtractedEntity,
    Message,
    MessageEmbedding,
    MessageLinkInference
  }

  test "answers generic tenant questions for users with semantic qa fallback" do
    owner = create_user!("owner")
    tenant = create_tenant!("User QA", owner)
    actor = create_actor!(tenant.schema_name, "alice")
    channel = create_channel!(tenant.schema_name, "ops")

    message =
      create_message!(
        tenant.schema_name,
        actor.id,
        channel.id,
        "Alice and Bob discussed endpoint isolation last week."
      )

    create_embedding!(tenant.schema_name, message.id, [0.4, 0.5, 0.6], "test-embedding-model")

    request =
      QARequest.new("What did Alice and Bob talk about last week?", :user,
        embedding_provider: Threadr.TestEmbeddingProvider,
        embedding_model: "test-embedding-model",
        generation_provider: Threadr.TestGenerationProvider,
        generation_model: "test-chat",
        limit: 1
      )

    assert {:ok, result} =
             Analysis.answer_tenant_question_for_user(
               owner,
               tenant.subject_name,
               request
             )

    assert result.mode == :semantic_qa
    assert result.answer.content =~ "What did Alice and Bob talk about last week?"
  end

  test "answers actor-pair conversation questions for users from reconstructed conversations" do
    owner = create_user!("conversation")
    tenant = create_tenant!("User QA Conversation", owner)
    alice = create_actor!(tenant.schema_name, "alice")
    bob = create_actor!(tenant.schema_name, "bob")
    channel = create_channel!(tenant.schema_name, "ops")

    request_message =
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

    response_message =
      create_message!(
        tenant.schema_name,
        bob.id,
        channel.id,
        "Yes, I validated web-4 before deploy.",
        "msg-answer",
        ~U[2026-03-08 10:05:00Z],
        %{
          "dialogue_act" => %{"label" => "status_update", "confidence" => 0.86},
          "reply_to_external_id" => request_message.external_id,
          "conversation_external_id" => "ops"
        }
      )

    create_entity!(tenant.schema_name, request_message.id, "artifact", "web-4")
    create_entity!(tenant.schema_name, response_message.id, "artifact", "web-4")

    {:ok, _initial_conversation} =
      ConversationAttachment.attach_message(
        request_message.id,
        tenant.schema_name
      )

    {:ok, inference} =
      MessageLinkInference.infer_and_persist(
        response_message.id,
        tenant.schema_name
      )

    {:ok, _conversation} =
      ConversationAttachment.attach_message(
        response_message.id,
        tenant.schema_name,
        inference: inference
      )

    request =
      QARequest.new("What did Alice and Bob talk about last week?", :user,
        generation_provider: Threadr.TestGenerationProvider,
        generation_model: "test-chat"
      )

    assert {:ok, result} =
             Analysis.answer_tenant_question_for_user(
               owner,
               tenant.subject_name,
               request
             )

    assert result.mode == :conversation_qa
    assert result.query.retrieval == "reconstructed_conversations"
    assert result.query.actor_handle == "alice"
    assert result.query.target_actor_handle == "bob"
    assert result.answer.content =~ "What did Alice and Bob talk about last week?"
  end

  test "answers single-actor topical questions for users from filtered actor messages" do
    owner = create_user!("single-actor-topic")
    tenant = create_tenant!("User QA Single Actor Topic", owner)
    thanew = create_actor!(tenant.schema_name, "THANEW")
    leku = create_actor!(tenant.schema_name, "leku")
    channel = create_channel!(tenant.schema_name, "#!chases")

    create_message!(
      tenant.schema_name,
      thanew.id,
      channel.id,
      "not a big fan of dnb tbh"
    )

    create_message!(
      tenant.schema_name,
      thanew.id,
      channel.id,
      "but its good background shit for playing games"
    )

    create_message!(
      tenant.schema_name,
      leku.id,
      channel.id,
      "i like jungle more than dnb"
    )

    request =
      QARequest.new("does THANEW like dnb?", :user,
        requester_channel_name: "#!chases",
        generation_provider: Threadr.TestConstraintGenerationProvider,
        generation_model: "test-chat"
      )

    assert {:ok, result} =
             Analysis.answer_tenant_question_for_user(
               owner,
               tenant.subject_name,
               request
             )

    assert result.mode == :constrained_qa
    assert result.query.retrieval == "literal_term_messages"
    assert result.query.actor_handles == ["THANEW"]
    assert result.context =~ "not a big fan of dnb tbh"
    refute result.context =~ "i like jungle more than dnb"
  end

  test "answers time-bounded conversation summary questions for users from reconstructed conversations" do
    owner = create_user!("conversation-summary")
    tenant = create_tenant!("User QA Conversation Summary", owner)
    alice = create_actor!(tenant.schema_name, "alice")
    bob = create_actor!(tenant.schema_name, "bob")
    channel = create_channel!(tenant.schema_name, "ops")

    request_message =
      create_message!(
        tenant.schema_name,
        alice.id,
        channel.id,
        "Can you validate web-7 before deploy?",
        "msg-question-summary",
        ~U[2026-03-08 11:00:00Z],
        %{
          "dialogue_act" => %{"label" => "request", "confidence" => 0.92},
          "conversation_external_id" => "ops"
        }
      )

    response_message =
      create_message!(
        tenant.schema_name,
        bob.id,
        channel.id,
        "Yes, I validated web-7 before deploy.",
        "msg-answer-summary",
        ~U[2026-03-08 11:05:00Z],
        %{
          "dialogue_act" => %{"label" => "status_update", "confidence" => 0.86},
          "reply_to_external_id" => request_message.external_id,
          "conversation_external_id" => "ops"
        }
      )

    create_entity!(tenant.schema_name, request_message.id, "artifact", "web-7")
    create_entity!(tenant.schema_name, response_message.id, "artifact", "web-7")

    {:ok, _initial_conversation} =
      ConversationAttachment.attach_message(
        request_message.id,
        tenant.schema_name
      )

    {:ok, inference} =
      MessageLinkInference.infer_and_persist(
        response_message.id,
        tenant.schema_name
      )

    {:ok, _conversation} =
      ConversationAttachment.attach_message(
        response_message.id,
        tenant.schema_name,
        inference: inference
      )

    request =
      QARequest.new("What happened last week?", :user,
        since: ~U[2026-03-01 00:00:00Z],
        until: ~U[2026-03-09 00:00:00Z],
        generation_provider: Threadr.TestGenerationProvider,
        generation_model: "test-chat"
      )

    assert {:ok, result} =
             Analysis.answer_tenant_question_for_user(
               owner,
               tenant.subject_name,
               request
             )

    assert result.mode == :conversation_summary_qa
    assert result.query.retrieval == "reconstructed_conversations_plus_messages"
    assert result.query.conversation_count == 1
    assert result.query.message_count == 2
    assert result.answer.content =~ "What happened last week?"
  end

  test "reports qa embedding coverage for retained tenant messages" do
    owner = create_user!("coverage")
    tenant = create_tenant!("User QA Coverage", owner)
    actor = create_actor!(tenant.schema_name, "alice")
    channel = create_channel!(tenant.schema_name, "ops")

    embedded_message =
      create_message!(
        tenant.schema_name,
        actor.id,
        channel.id,
        "Alice documented the deploy checklist."
      )

    _missing_message =
      create_message!(
        tenant.schema_name,
        actor.id,
        channel.id,
        "Alice still needs to verify the rollout state."
      )

    create_embedding!(
      tenant.schema_name,
      embedded_message.id,
      [0.4, 0.5, 0.6],
      "test-embedding-model"
    )

    assert {:ok, status} =
             Analysis.qa_embedding_status_for_user(
               owner,
               tenant.subject_name,
               embedding_model: "test-embedding-model"
             )

    assert status.status == :catching_up
    assert status.embedding_model == "test-embedding-model"
    assert status.total_messages == 2
    assert status.embedded_messages == 1
    assert status.missing_messages == 1
    assert status.coverage_percent == 50.0
    assert status.latest_unembedded_observed_at
  end

  defp create_user!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      ControlPlane.register_user(%{
        email: "#{prefix}-#{suffix}@example.com",
        name: "User QA #{suffix}",
        password: "threadr-password-#{suffix}"
      })

    user
  end

  defp create_tenant!(prefix, owner) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(
        %{
          name: "#{prefix} #{suffix}",
          subject_name: "#{String.downcase(String.replace(prefix, " ", "-"))}-#{suffix}"
        },
        owner_user: owner
      )

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
         external_id \\ Ecto.UUID.generate(),
         observed_at \\ DateTime.utc_now(),
         metadata \\ %{}
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

  defp create_embedding!(tenant_schema, message_id, embedding, model) do
    MessageEmbedding
    |> Ash.Changeset.for_create(
      :create,
      %{
        model: model,
        dimensions: length(embedding),
        embedding: embedding,
        metadata: %{},
        message_id: message_id
      },
      tenant: tenant_schema
    )
    |> Ash.create!()
  end
end
