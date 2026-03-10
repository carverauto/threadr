defmodule Threadr.ML.GraphRAGTest do
  use Threadr.DataCase, async: false

  import Ash.Expr
  require Ash.Query

  alias Threadr.ControlPlane.Service
  alias Threadr.Events.{ChatMessage, Envelope}
  alias Threadr.ML.{GraphRAG, QARequest, SummaryRequest}
  alias Threadr.Messaging.Topology
  alias Threadr.TenantData.{Ingest, Message, MessageEmbedding}

  test "answers a question with semantic and graph context" do
    tenant = create_tenant!("Graph RAG")
    %{incident_message: incident_message} = seed_graph_rag_data!(tenant)

    create_embedding!(tenant.schema_name, incident_message.id, [0.4, 0.5, 0.6])

    request =
      QARequest.new("Who is collaborating with Alice?", :user,
        embedding_provider: Threadr.TestEmbeddingProvider,
        embedding_model: "test-embedding-model",
        generation_provider: Threadr.TestGenerationProvider,
        generation_model: "test-chat",
        limit: 1
      )

    assert {:ok, result} =
             GraphRAG.answer_question(
               tenant.subject_name,
               request
             )

    assert result.semantic.context =~ "[C1]"
    assert result.graph.context =~ "Actors:"
    assert result.graph.context =~ "Relationships:"
    assert result.graph.context =~ "CO_MENTIONED"
    assert result.graph.context =~ "[G1]"
    assert Enum.any?(result.graph.relationships, &(&1.relationship_type == "CO_MENTIONED"))
    assert Enum.any?(result.graph.citations, &String.contains?(&1.body, "followed up"))
    assert result.answer.metadata["context"]["graph_citations"] == ["G1"]
    assert result.answer.content =~ "Graph Context:"
  end

  test "summarizes a topic with graph-aware evidence" do
    tenant = create_tenant!("Graph Summary")
    %{incident_message: incident_message} = seed_graph_rag_data!(tenant)

    create_embedding!(tenant.schema_name, incident_message.id, [0.4, 0.5, 0.6])

    request =
      SummaryRequest.new("Alice, Bob, and Carol incident response activity",
        embedding_provider: Threadr.TestEmbeddingProvider,
        embedding_model: "test-embedding-model",
        generation_provider: Threadr.TestGenerationProvider,
        generation_model: "test-chat",
        limit: 1
      )

    assert {:ok, result} =
             GraphRAG.summarize_topic(
               tenant.subject_name,
               request
             )

    assert result.summary.metadata["mode"] == :summarization

    assert result.summary.metadata["context"]["topic"] ==
             "Alice, Bob, and Carol incident response activity"

    assert result.context =~ "Semantic Evidence:"
    assert result.context =~ "Graph Context:"
    assert result.summary.content =~ "Topic:"
  end

  test "uses actor-filtered constrained retrieval before semantic fallback for graph answers" do
    tenant = create_tenant!("Graph RAG Actor Topic")
    observed_at = DateTime.utc_now() |> DateTime.truncate(:second)

    _question_message =
      persist_message!(
        tenant.subject_name,
        tenant.schema_name,
        "larsini0",
        "#!chases",
        "THANEW: u can tell i play a certain kind of dnb",
        ["THANEW"],
        observed_at
      )

    _answer_message =
      persist_message!(
        tenant.subject_name,
        tenant.schema_name,
        "THANEW",
        "#!chases",
        "not a big fan of dnb tbh",
        [],
        DateTime.add(observed_at, 60, :second)
      )

    _follow_up_message =
      persist_message!(
        tenant.subject_name,
        tenant.schema_name,
        "THANEW",
        "#!chases",
        "but its good background shit for playing games",
        [],
        DateTime.add(observed_at, 120, :second)
      )

    request =
      QARequest.new("does THANEW like dnb?", :user,
        requester_channel_name: "#!chases",
        generation_provider: Threadr.TestConstraintGenerationProvider,
        generation_model: "test-chat"
      )

    assert {:ok, result} =
             GraphRAG.answer_question(
               tenant.subject_name,
               request
             )

    assert result.semantic.query.mode == "constrained_qa"
    assert result.semantic.query.retrieval == "literal_term_messages"

    assert Enum.any?(
             result.semantic.citations,
             &String.contains?(&1.body, "not a big fan of dnb")
           )

    refute Enum.any?(result.semantic.citations, &String.contains?(&1.body, "incident response"))
  end

  defp create_tenant!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(%{
        name: "#{prefix} #{suffix}",
        subject_name: "graph-rag-#{suffix}"
      })

    tenant
  end

  defp seed_graph_rag_data!(tenant) do
    observed_at = DateTime.utc_now() |> DateTime.truncate(:second)

    incident_message =
      persist_message!(
        tenant.subject_name,
        tenant.schema_name,
        "alice",
        "ops",
        "Alice mentioned Bob and Carol in incident response planning.",
        ["bob", "carol"],
        observed_at
      )

    follow_up_message =
      persist_message!(
        tenant.subject_name,
        tenant.schema_name,
        "bob",
        "ops",
        "Bob followed up with Carol on endpoint isolation.",
        ["carol"],
        DateTime.add(observed_at, 60, :second)
      )

    %{
      incident_message: incident_message,
      follow_up_message: follow_up_message
    }
  end

  defp persist_message!(
         tenant_subject_name,
         tenant_schema,
         actor,
         channel,
         body,
         mentions,
         observed_at
       ) do
    envelope =
      Envelope.new(
        ChatMessage.from_map(%{
          platform: "discord",
          channel: channel,
          actor: actor,
          body: body,
          mentions: mentions,
          observed_at: observed_at,
          raw: %{"body" => body}
        }),
        "chat.message",
        Topology.subject_for(:chat_messages, tenant_subject_name),
        %{id: Ecto.UUID.generate()}
      )

    {:ok, message} = Ingest.persist_envelope(envelope)

    Message
    |> Ash.Query.filter(expr(id == ^message.id))
    |> Ash.read_one!(tenant: tenant_schema)
  end

  defp create_embedding!(tenant_schema, message_id, embedding) do
    MessageEmbedding
    |> Ash.Changeset.for_create(
      :create,
      %{
        model: "test-embedding-model",
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
