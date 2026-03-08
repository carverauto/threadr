defmodule ThreadrWeb.Api.V1.QaControllerTest do
  use ThreadrWeb.ConnCase, async: false

  import Ash.Expr
  require Ash.Query

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Service
  alias Threadr.Events.{ChatMessage, Envelope}
  alias Threadr.Messaging.Topology

  alias Threadr.TenantData.{Actor, Channel, Extraction, Ingest, Message, MessageEmbedding}

  setup do
    previous_ml_config = Application.get_env(:threadr, Threadr.ML, [])

    Application.put_env(
      :threadr,
      Threadr.ML,
      Keyword.merge(previous_ml_config,
        embeddings: [provider: Threadr.TestEmbeddingProvider, model: "test-embedding-model"],
        generation: [provider: Threadr.TestGenerationProvider, model: "test-chat"]
      )
    )

    on_exit(fn ->
      Application.put_env(:threadr, Threadr.ML, previous_ml_config)
    end)

    :ok
  end

  test "POST /api/v1/tenants/:subject_name/qa/search requires authentication", %{conn: conn} do
    conn =
      post(conn, ~p"/api/v1/tenants/acme/qa/search", %{"question" => "Who did Alice mention?"})

    assert json_response(conn, 401) == %{"errors" => %{"detail" => "Unauthorized"}}
  end

  test "POST /api/v1/tenants/:subject_name/qa/search returns ranked tenant matches", %{conn: conn} do
    owner = create_user!("owner")
    tenant = create_tenant!("QA Owned", owner)
    seed_semantic_data!(tenant.schema_name)

    conn =
      conn
      |> api_key_conn(owner)
      |> post(~p"/api/v1/tenants/#{tenant.subject_name}/qa/search", %{
        "question" => "Who did Alice mention?",
        "limit" => 2
      })

    assert %{"data" => data} = json_response(conn, 200)
    assert data["tenant_subject_name"] == tenant.subject_name
    assert data["query"]["provider"] == "test"
    assert length(data["matches"]) == 2
    assert length(data["citations"]) == 2
    assert hd(data["citations"])["label"] == "C1"
    assert hd(data["matches"])["body"] == "Alice mentioned Bob in incident response planning."
    assert hd(data["matches"])["similarity"] > List.last(data["matches"])["similarity"]
    assert data["context"] =~ "[C1]"
    assert data["context"] =~ "#ops alice: Alice mentioned Bob in incident response planning."
  end

  test "POST /api/v1/tenants/:subject_name/qa/answer returns an answer grounded in tenant context",
       %{conn: conn} do
    owner = create_user!("owner")
    tenant = create_tenant!("QA Owned", owner)
    seed_semantic_data!(tenant.schema_name)

    conn =
      conn
      |> api_key_conn(owner)
      |> post(~p"/api/v1/tenants/#{tenant.subject_name}/qa/answer", %{
        "question" => "Who did Alice mention?"
      })

    assert %{"data" => data} = json_response(conn, 200)
    assert data["tenant_subject_name"] == tenant.subject_name
    assert data["answer"]["provider"] == "test"
    assert data["answer"]["model"] == "test-llm"
    assert data["answer"]["metadata"]["context"]["question"] == "Who did Alice mention?"
    assert hd(data["citations"])["label"] == "C1"
    assert data["answer"]["content"] =~ "Question:"
  end

  test "POST /api/v1/tenants/:subject_name/qa/answer returns extraction-aware citations", %{
    conn: conn
  } do
    owner = create_user!("owner")
    tenant = create_tenant!("QA Extraction", owner)
    seed_semantic_extraction_data!(tenant)

    conn =
      conn
      |> api_key_conn(owner)
      |> post(~p"/api/v1/tenants/#{tenant.subject_name}/qa/answer", %{
        "question" => "What did Bob report?"
      })

    assert %{"data" => data} = json_response(conn, 200)
    assert hd(data["citations"])["extracted_entities"] != []
    assert hd(data["citations"])["extracted_facts"] != []
    assert data["context"] =~ "Facts: Bob reported payroll access was limited"
    assert data["facts_over_time"] != []
  end

  test "POST /api/v1/tenants/:subject_name/qa/search respects since/until bounds", %{conn: conn} do
    owner = create_user!("owner")
    tenant = create_tenant!("QA Temporal", owner)
    seed_temporal_semantic_data!(tenant.schema_name)

    conn =
      conn
      |> api_key_conn(owner)
      |> post(~p"/api/v1/tenants/#{tenant.subject_name}/qa/search", %{
        "question" => "What changed?",
        "limit" => 5,
        "since" => "2026-03-05T12:30:00",
        "until" => "2026-03-05T13:30:00"
      })

    assert %{"data" => data} = json_response(conn, 200)
    assert length(data["matches"]) == 1
    assert hd(data["matches"])["body"] == "Bob confirmed payroll access was narrowed."
  end

  test "POST /api/v1/tenants/:subject_name/qa/compare compares two windows", %{conn: conn} do
    owner = create_user!("owner")
    tenant = create_tenant!("QA Compare", owner)
    seed_temporal_semantic_data!(tenant.schema_name)

    conn =
      conn
      |> api_key_conn(owner)
      |> post(~p"/api/v1/tenants/#{tenant.subject_name}/qa/compare", %{
        "question" => "What changed?",
        "limit" => 5,
        "since" => "2026-03-05T11:30:00",
        "until" => "2026-03-05T12:30:00",
        "compare_since" => "2026-03-05T12:30:00",
        "compare_until" => "2026-03-05T13:30:00"
      })

    assert %{"data" => data} = json_response(conn, 200)

    assert data["baseline"]["matches"] |> hd() |> Map.fetch!("body") ==
             "Alice opened the incident timeline."

    assert data["comparison"]["matches"] |> hd() |> Map.fetch!("body") ==
             "Bob confirmed payroll access was narrowed."

    assert Map.has_key?(data, "entity_delta")
    assert Map.has_key?(data, "fact_delta")
    assert data["answer"]["content"] =~ "Baseline Window:"
    assert data["answer"]["content"] =~ "Comparison Window:"
  end

  test "POST /api/v1/tenants/:subject_name/qa/answer returns 422 when no embeddings exist", %{
    conn: conn
  } do
    owner = create_user!("owner")
    tenant = create_tenant!("QA Empty", owner)

    conn =
      conn
      |> api_key_conn(owner)
      |> post(~p"/api/v1/tenants/#{tenant.subject_name}/qa/answer", %{
        "question" => "Who did Alice mention?"
      })

    assert json_response(conn, 422) == %{
             "errors" => %{"detail" => "No tenant message embeddings available"}
           }
  end

  test "POST /api/v1/tenants/:subject_name/qa/graph-answer returns graph-aware context", %{
    conn: conn
  } do
    owner = create_user!("owner")
    tenant = create_tenant!("QA Graph", owner)
    seed_graph_rag_data!(tenant)

    conn =
      conn
      |> api_key_conn(owner)
      |> post(~p"/api/v1/tenants/#{tenant.subject_name}/qa/graph-answer", %{
        "question" => "Who is collaborating with Alice?",
        "limit" => "1"
      })

    assert %{"data" => data} = json_response(conn, 200)
    assert data["answer"]["provider"] == "test"
    assert data["graph"]["context"] =~ "Relationships:"
    assert Enum.any?(data["graph"]["relationships"], &(&1["relationship_type"] == "CO_MENTIONED"))
    assert Enum.any?(data["graph"]["citations"], &String.contains?(&1["body"], "followed up"))
  end

  test "POST /api/v1/tenants/:subject_name/qa/summarize returns a grounded summary", %{conn: conn} do
    owner = create_user!("owner")
    tenant = create_tenant!("QA Summary", owner)
    seed_graph_rag_data!(tenant)

    conn =
      conn
      |> api_key_conn(owner)
      |> post(~p"/api/v1/tenants/#{tenant.subject_name}/qa/summarize", %{
        "topic" => "Alice, Bob, and Carol incident response activity"
      })

    assert %{"data" => data} = json_response(conn, 200)
    assert data["summary"]["provider"] == "test"
    assert data["summary"]["metadata"]["mode"] == "summarization"
    assert data["graph"]["context"] =~ "Actors:"
    assert data["summary"]["content"] =~ "Topic:"
  end

  defp api_key_conn(conn, user) do
    {:ok, _api_key, plaintext_api_key} = Service.create_api_key(user, %{name: "CLI"})

    conn
    |> put_req_header("authorization", "Bearer #{plaintext_api_key}")
    |> put_req_header("accept", "application/json")
  end

  defp create_user!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      ControlPlane.register_user(%{
        email: "#{prefix}-#{suffix}@example.com",
        name: "User #{suffix}",
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

  defp seed_semantic_data!(tenant_schema) do
    actor = create_actor!(tenant_schema, "alice")
    channel = create_channel!(tenant_schema, "ops")

    first_message =
      create_message!(
        tenant_schema,
        actor.id,
        channel.id,
        "Alice mentioned Bob in incident response planning."
      )

    second_message =
      create_message!(
        tenant_schema,
        actor.id,
        channel.id,
        "Alice discussed malware clusters without naming anyone."
      )

    create_embedding!(tenant_schema, first_message.id, [0.4, 0.5, 0.6])
    create_embedding!(tenant_schema, second_message.id, [0.1, 0.2, 0.3])
  end

  defp seed_semantic_extraction_data!(tenant) do
    actor = create_actor!(tenant.schema_name, "alice")
    channel = create_channel!(tenant.schema_name, "ops")

    message =
      create_message!(
        tenant.schema_name,
        actor.id,
        channel.id,
        "Alice told Bob that payroll access was limited on 2026-03-05."
      )

    create_embedding!(tenant.schema_name, message.id, [0.4, 0.5, 0.6])

    {:ok, _persisted} =
      Extraction.extract_and_persist_message(
        message,
        tenant.subject_name,
        tenant.schema_name,
        provider: Threadr.TestExtractionProvider,
        generation_provider: Threadr.TestGenerationProvider,
        model: "test-chat"
      )
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

    create_embedding!(tenant.schema_name, incident_message.id, [0.4, 0.5, 0.6])
    create_embedding!(tenant.schema_name, follow_up_message.id, [0.39, 0.49, 0.59])
  end

  defp seed_temporal_semantic_data!(tenant_schema) do
    actor = create_actor!(tenant_schema, "alice")
    channel = create_channel!(tenant_schema, "ops")

    first_message =
      create_message!(
        tenant_schema,
        actor.id,
        channel.id,
        "Alice opened the incident timeline.",
        ~U[2026-03-05 12:00:00Z]
      )

    second_message =
      create_message!(
        tenant_schema,
        actor.id,
        channel.id,
        "Bob confirmed payroll access was narrowed.",
        ~U[2026-03-05 13:00:00Z]
      )

    create_embedding!(tenant_schema, first_message.id, [0.2, 0.2, 0.2])
    create_embedding!(tenant_schema, second_message.id, [0.4, 0.5, 0.6])
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

  defp create_message!(
         tenant_schema,
         actor_id,
         channel_id,
         body,
         observed_at \\ DateTime.utc_now()
       ) do
    Message
    |> Ash.Changeset.for_create(
      :create,
      %{
        external_id: Ecto.UUID.generate(),
        body: body,
        observed_at: observed_at,
        raw: %{"body" => body},
        metadata: %{},
        actor_id: actor_id,
        channel_id: channel_id
      },
      tenant: tenant_schema
    )
    |> Ash.create!()
  end

  defp create_embedding!(tenant_schema, message_id, embedding) do
    attrs = %{
      model: "test-embedding-model",
      dimensions: length(embedding),
      embedding: embedding,
      metadata: %{},
      message_id: message_id
    }

    query =
      MessageEmbedding
      |> Ash.Query.filter(expr(message_id == ^message_id and model == "test-embedding-model"))

    case Ash.read_one(query, tenant: tenant_schema) do
      {:ok, nil} ->
        MessageEmbedding
        |> Ash.Changeset.for_create(:create, attrs, tenant: tenant_schema)
        |> Ash.create!()

      {:ok, existing} ->
        existing
        |> Ash.Changeset.for_update(
          :update,
          Map.take(attrs, [:dimensions, :embedding, :metadata]),
          tenant: tenant_schema
        )
        |> Ash.update!()
    end
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
end
