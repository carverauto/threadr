defmodule Threadr.ControlPlane.BotQATest do
  use Threadr.DataCase, async: false

  alias Threadr.ControlPlane.{Analysis, Service}
  alias Threadr.ML.QARequest

  alias Threadr.TenantData.{
    Actor,
    Channel,
    ConversationAttachment,
    ConversationRelationshipRecompute,
    ExtractedEntity,
    Message,
    MessageEmbedding,
    MessageLinkInference
  }

  test "answers tenant questions for bot runtimes with tenant-scoped QA" do
    tenant = create_tenant!("Bot QA")
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
      QARequest.new("What did Alice and Bob talk about last week?", :bot,
        embedding_provider: Threadr.TestEmbeddingProvider,
        embedding_model: "test-embedding-model",
        generation_provider: Threadr.TestGenerationProvider,
        generation_model: "test-chat",
        limit: 1
      )

    assert {:ok, result} =
             Analysis.answer_tenant_question_for_bot(
               tenant.subject_name,
               request
             )

    assert result.mode in [:graph_rag, :semantic_qa]
    assert result.answer.content =~ "What did Alice and Bob talk about last week?"
  end

  test "answers actor-centric questions for bot runtimes without generic fallback" do
    tenant = create_tenant!("Bot QA Actor")
    actor = create_actor!(tenant.schema_name, "twatbot")
    channel = create_channel!(tenant.schema_name, "ops")

    create_message!(
      tenant.schema_name,
      actor.id,
      channel.id,
      "twatbot keeps talking about deploys, restart loops, and operator state."
    )

    create_message!(
      tenant.schema_name,
      actor.id,
      channel.id,
      "twatbot also talks about bots, rollouts, and crash recovery."
    )

    create_message!(
      tenant.schema_name,
      actor.id,
      channel.id,
      "twatbot asked whether the new bot image was live."
    )

    request =
      QARequest.new("what does twatbot talk about?", :bot,
        generation_provider: Threadr.TestGenerationProvider,
        generation_model: "test-chat",
        limit: 3
      )

    assert {:ok, result} =
             Analysis.answer_tenant_question_for_bot(
               tenant.subject_name,
               request
             )

    assert result.mode == :actor_qa
    assert result.query.actor_handle == "twatbot"
    assert result.answer.content =~ "what does twatbot talk about?"
  end

  test "answers actor-pair conversation questions from reconstructed conversations" do
    tenant = create_tenant!("Bot QA Conversation")
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
      QARequest.new("What did Alice and Bob talk about last week?", :bot,
        generation_provider: Threadr.TestGenerationProvider,
        generation_model: "test-chat"
      )

    assert {:ok, result} =
             Analysis.answer_tenant_question_for_bot(
               tenant.subject_name,
               request
             )

    assert result.mode == :conversation_qa
    assert result.query.retrieval == "reconstructed_conversations"
    assert result.query.actor_handle == "alice"
    assert result.query.target_actor_handle == "bob"
    assert result.answer.content =~ "What did Alice and Bob talk about last week?"
  end

  test "answers actor topical questions constrained to today" do
    tenant = create_tenant!("Bot QA Today")
    actor = create_actor!(tenant.schema_name, "farmr")
    channel = create_channel!(tenant.schema_name, "#!chases")

    create_message!(
      tenant.schema_name,
      actor.id,
      channel.id,
      "farmr talked about terrace produce, planters, and garden ideas today.",
      "farmr-today-bot",
      DateTime.utc_now() |> DateTime.truncate(:second)
    )

    request =
      QARequest.new("what did farmr talk about today?", :bot,
        generation_provider: Threadr.TestConstraintGenerationProvider,
        generation_model: "test-chat"
      )

    assert {:ok, result} =
             Analysis.answer_tenant_question_for_bot(
               tenant.subject_name,
               request
             )

    assert result.mode == :constrained_qa
    assert result.query.retrieval == "filtered_messages"
    assert result.query.actor_handles == ["farmr"]
    assert result.answer.content =~ "what did farmr talk about today?"
  end

  test "answers time-bounded conversation summary questions from reconstructed conversations" do
    tenant = create_tenant!("Bot QA Conversation Summary")
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
      QARequest.new("What happened last week?", :bot,
        since: ~U[2026-03-01 00:00:00Z],
        until: ~U[2026-03-09 00:00:00Z],
        generation_provider: Threadr.TestGenerationProvider,
        generation_model: "test-chat"
      )

    assert {:ok, result} =
             Analysis.answer_tenant_question_for_bot(
               tenant.subject_name,
               request
             )

    assert result.mode == :conversation_summary_qa
    assert result.query.retrieval == "reconstructed_conversations_plus_messages"
    assert result.query.conversation_count == 1
    assert result.query.message_count == 2
    assert result.answer.content =~ "What happened last week?"
  end

  test "routes paired-actor phrasing through generic bot QA instead of actor QA" do
    tenant = create_tenant!("Bot QA Generic Pair")
    actor = create_actor!(tenant.schema_name, "hyralak")
    target_actor = create_actor!(tenant.schema_name, "sig")
    channel = create_channel!(tenant.schema_name, "ops")

    first_message =
      create_message!(
        tenant.schema_name,
        actor.id,
        channel.id,
        "hyralak keeps talking about deploys, IRC bots, and restart loops."
      )

    second_message =
      create_message!(
        tenant.schema_name,
        target_actor.id,
        channel.id,
        "sig mostly talks about rollout failures, bots, and deploy recovery."
      )

    create_embedding!(
      tenant.schema_name,
      first_message.id,
      [0.1, 0.2, 0.3],
      "test-embedding-model"
    )

    create_embedding!(
      tenant.schema_name,
      second_message.id,
      [0.3, 0.2, 0.1],
      "test-embedding-model"
    )

    request =
      QARequest.new("what do hyralak and sig mostly talk about?", :bot,
        embedding_provider: Threadr.TestEmbeddingProvider,
        embedding_model: "test-embedding-model",
        generation_provider: Threadr.TestGenerationProvider,
        generation_model: "test-chat",
        limit: 2
      )

    assert {:ok, result} =
             Analysis.answer_tenant_question_for_bot(
               tenant.subject_name,
               request
             )

    assert result.mode in [:graph_rag, :semantic_qa, :constrained_qa]
    refute result.mode == :actor_qa
    assert result.answer.content =~ "what do hyralak and sig mostly talk about?"
  end

  test "catches up missing embeddings before generic bot QA" do
    tenant = create_tenant!("Bot QA Catchup")
    actor = create_actor!(tenant.schema_name, "alice")
    channel = create_channel!(tenant.schema_name, "ops")

    create_message!(
      tenant.schema_name,
      actor.id,
      channel.id,
      "Alice and Bob discussed endpoint isolation last week."
    )

    request =
      QARequest.new("What did Alice and Bob talk about last week?", :bot,
        embedding_provider: Threadr.TestEmbeddingProvider,
        embedding_model: "test-embedding-model",
        generation_provider: Threadr.TestGenerationProvider,
        generation_model: "test-chat",
        limit: 1
      )

    assert {:ok, result} =
             Analysis.answer_tenant_question_for_bot(
               tenant.subject_name,
               request
             )

    assert result.mode in [:graph_rag, :semantic_qa]
    assert result.answer.content =~ "What did Alice and Bob talk about last week?"
  end

  test "answers interaction partner questions from reconstructed relationship evidence" do
    tenant = create_tenant!("Bot QA Interaction")
    sig = create_actor!(tenant.schema_name, "sig")
    bysin = create_actor!(tenant.schema_name, "bysin")
    channel = create_channel!(tenant.schema_name, "#!chases")

    request_message =
      create_message!(
        tenant.schema_name,
        sig.id,
        channel.id,
        "bysin can you check the bridge bot?",
        "msg-sig-int-1",
        ~U[2026-03-08 09:00:00Z],
        %{
          "dialogue_act" => %{"label" => "request", "confidence" => 0.92},
          "conversation_external_id" => "#!chases"
        }
      )

    response_message =
      create_message!(
        tenant.schema_name,
        bysin.id,
        channel.id,
        "yeah, bridge bot looks fine now",
        "msg-sig-int-2",
        ~U[2026-03-08 09:02:00Z],
        %{
          "dialogue_act" => %{"label" => "status_update", "confidence" => 0.84},
          "reply_to_external_id" => request_message.external_id,
          "conversation_external_id" => "#!chases"
        }
      )

    {:ok, conversation} =
      ConversationAttachment.attach_message(request_message.id, tenant.schema_name)

    {:ok, inference} =
      MessageLinkInference.infer_and_persist(response_message.id, tenant.schema_name)

    {:ok, _conversation} =
      ConversationAttachment.attach_message(
        response_message.id,
        tenant.schema_name,
        inference: inference
      )

    assert {:ok, _} =
             ConversationRelationshipRecompute.recompute_conversation_relationships(
               conversation.id,
               tenant.schema_name
             )

    request =
      QARequest.new("who does sig talk with the most?", :bot,
        generation_provider: Threadr.TestGenerationProvider,
        generation_model: "test-chat"
      )

    assert {:ok, result} =
             Analysis.answer_tenant_question_for_bot(
               tenant.subject_name,
               request
             )

    assert result.mode == :interaction_qa
    assert result.query.actor_handle == "sig"
    assert hd(result.partners).partner_handle == "bysin"
    refute result.context =~ "##!chases"
  end

  test "resolves requester self reference for interaction partner questions" do
    tenant = create_tenant!("Bot QA Interaction Self")
    leku = create_actor!(tenant.schema_name, "leku")
    sig = create_actor!(tenant.schema_name, "sig")
    channel = create_channel!(tenant.schema_name, "#!chases")

    request_message =
      create_message!(
        tenant.schema_name,
        leku.id,
        channel.id,
        "sig can you review the replay?",
        "msg-self-1",
        ~U[2026-03-08 09:10:00Z],
        %{
          "dialogue_act" => %{"label" => "request", "confidence" => 0.92},
          "conversation_external_id" => "#!chases"
        }
      )

    response_message =
      create_message!(
        tenant.schema_name,
        sig.id,
        channel.id,
        "yeah, replay looks good",
        "msg-self-2",
        ~U[2026-03-08 09:11:00Z],
        %{
          "dialogue_act" => %{"label" => "status_update", "confidence" => 0.84},
          "reply_to_external_id" => request_message.external_id,
          "conversation_external_id" => "#!chases"
        }
      )

    {:ok, conversation} =
      ConversationAttachment.attach_message(request_message.id, tenant.schema_name)

    {:ok, inference} =
      MessageLinkInference.infer_and_persist(response_message.id, tenant.schema_name)

    {:ok, _conversation} =
      ConversationAttachment.attach_message(
        response_message.id,
        tenant.schema_name,
        inference: inference
      )

    assert {:ok, _} =
             ConversationRelationshipRecompute.recompute_conversation_relationships(
               conversation.id,
               tenant.schema_name
             )

    request =
      QARequest.new("who do I mostly talk with?", :bot,
        requester_actor_handle: "leku",
        generation_provider: Threadr.TestGenerationProvider,
        generation_model: "test-chat"
      )

    assert {:ok, result} =
             Analysis.answer_tenant_question_for_bot(
               tenant.subject_name,
               request
             )

    assert result.mode == :interaction_qa
    assert result.query.actor_handle == "leku"
    assert hd(result.partners).partner_handle == "sig"
  end

  test "returns insufficient context when no embeddings exist" do
    tenant = create_tenant!("Bot QA Empty")

    request =
      QARequest.new("What happened?", :bot,
        embedding_provider: Threadr.TestEmbeddingProvider,
        embedding_model: "test-embedding-model"
      )

    assert {:error, :no_message_embeddings} =
             Analysis.answer_tenant_question_for_bot(
               tenant.subject_name,
               request
             )
  end

  test "passes embedding endpoint and provider config through catch-up embeddings" do
    tenant = create_tenant!("Bot QA Embedding Opts")
    actor = create_actor!(tenant.schema_name, "alice")
    channel = create_channel!(tenant.schema_name, "ops")

    message =
      create_message!(
        tenant.schema_name,
        actor.id,
        channel.id,
        "Alice and Bob discussed endpoint isolation last week."
      )

    request =
      QARequest.new("What did Alice and Bob talk about last week?", :bot,
        embedding_provider: Threadr.TestEmbeddingOptsProvider,
        embedding_model: "test-embedding-model",
        embedding_endpoint: "https://embeddings.example.test",
        embedding_api_key: "embedding-secret",
        embedding_provider_name: "custom-embedder",
        document_prefix: "doc:",
        query_prefix: "query:",
        generation_provider: Threadr.TestGenerationProvider,
        generation_model: "test-chat",
        limit: 1
      )

    assert {:ok, result} =
             Analysis.answer_tenant_question_for_bot(
               tenant.subject_name,
               request
             )

    assert result.mode in [:graph_rag, :semantic_qa]

    embeddings = Ash.read!(MessageEmbedding, tenant: tenant.schema_name)
    persisted = Enum.find(embeddings, &(&1.message_id == message.id))
    assert persisted
    assert persisted.metadata["input_type"] == "document"
    assert persisted.metadata["endpoint"] == "https://embeddings.example.test"
    assert persisted.metadata["api_key"] == "embedding-secret"
    assert persisted.metadata["provider_name"] == "custom-embedder"
    assert persisted.metadata["document_prefix"] == "doc:"
    assert persisted.metadata["query_prefix"] == "query:"
  end

  defp create_tenant!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(%{
        name: "#{prefix} #{suffix}",
        subject_name: "#{String.downcase(String.replace(prefix, " ", "-"))}-#{suffix}"
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
