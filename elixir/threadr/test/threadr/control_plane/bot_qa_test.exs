defmodule Threadr.ControlPlane.BotQATest do
  use Threadr.DataCase, async: false

  alias Threadr.ControlPlane.{Analysis, Service}
  alias Threadr.ML.QARequest
  alias Threadr.TenantData.{Actor, Channel, Message, MessageEmbedding}

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

    assert result.mode in [:graph_rag, :semantic_qa]
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

  defp create_message!(tenant_schema, actor_id, channel_id, body) do
    Message
    |> Ash.Changeset.for_create(
      :create,
      %{
        external_id: Ecto.UUID.generate(),
        body: body,
        observed_at: DateTime.utc_now(),
        raw: %{"body" => body},
        metadata: %{},
        actor_id: actor_id,
        channel_id: channel_id
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
