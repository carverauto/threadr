defmodule ThreadrWeb.TenantQaLiveTest do
  use ThreadrWeb.ConnCase, async: false

  import Ash.Expr
  import AshAuthentication.Phoenix.Plug, only: [store_in_session: 2]
  import Phoenix.LiveViewTest
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

  test "renders tenant workspace and grounded answer results", %{conn: conn} do
    user = create_user!("tenant-qa")
    tenant = create_tenant!("Tenant QA", user)
    seed_semantic_data!(tenant.schema_name)

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, view, html} = live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/qa")

    assert html =~ "Tenant QA Workspace"
    assert html =~ tenant.subject_name
    assert html =~ "/control-plane/tenants/#{tenant.subject_name}/graph"
    assert html =~ "/control-plane/tenants/#{tenant.subject_name}/history"

    view
    |> element("#tenant-qa-form")
    |> render_change(%{"question" => "Who did Alice mention?", "limit" => "2"})

    view
    |> element("#tenant-qa-answer")
    |> render_click()

    rendered = render(view)
    assert rendered =~ "Alice mentioned Bob in incident response planning."
    assert rendered =~ "C1"
    assert rendered =~ "#ops alice: Alice mentioned Bob in incident response planning."
    assert rendered =~ "Citations"
    assert rendered =~ "answer: Context:"
    assert rendered =~ "Message in Graph"
  end

  test "shows a validation error when question is blank", %{conn: conn} do
    user = create_user!("tenant-qa-empty")
    tenant = create_tenant!("Tenant QA Empty", user)

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, view, _html} = live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/qa")

    view
    |> element("#tenant-qa-answer")
    |> render_click()

    assert render(view) =~ "Question is required"
  end

  test "renders graph answer and summary results", %{conn: conn} do
    user = create_user!("tenant-qa-graph")
    tenant = create_tenant!("Tenant QA Graph", user)
    seed_graph_rag_data!(tenant)

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, view, _html} = live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/qa")

    view
    |> element("#tenant-qa-form")
    |> render_change(%{"question" => "Who is collaborating with Alice?", "limit" => "1"})

    view
    |> element("#tenant-qa-graph-answer")
    |> render_click()

    rendered = render(view)
    assert rendered =~ "Graph Answer"
    assert rendered =~ "Graph Context"
    assert rendered =~ "CO_MENTIONED"
    assert rendered =~ "G1"
    assert rendered =~ "Message in Graph"

    view
    |> element("#tenant-qa-summarize")
    |> render_click()

    rendered = render(view)
    assert rendered =~ "Summary"
    assert rendered =~ "Topic:"
  end

  test "renders extracted entities and facts in QA citations", %{conn: conn} do
    user = create_user!("tenant-qa-extraction")
    tenant = create_tenant!("Tenant QA Extraction", user)
    seed_semantic_extraction_data!(tenant)

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, view, _html} = live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/qa")

    view
    |> element("#tenant-qa-form")
    |> render_change(%{"question" => "What did Bob report?", "limit" => "1"})

    view
    |> element("#tenant-qa-answer")
    |> render_click()

    rendered = render(view)
    assert rendered =~ "person: Alice"
    assert rendered =~ "reported"
    assert rendered =~ "payroll access was limited"
    assert rendered =~ "Facts Over Time"
    assert rendered =~ "Top fact: Bob reported payroll access was limited"
  end

  test "applies temporal bounds to tenant QA results", %{conn: conn} do
    user = create_user!("tenant-qa-bounded")
    tenant = create_tenant!("Tenant QA Bounded", user)
    seed_temporal_semantic_data!(tenant.schema_name)

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, view, _html} = live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/qa")

    view
    |> element("#tenant-qa-form")
    |> render_change(%{
      "question" => "What changed?",
      "limit" => "5",
      "since" => "2026-03-05T12:30:00",
      "until" => "2026-03-05T13:30:00"
    })

    view
    |> element("#tenant-qa-search")
    |> render_click()

    rendered = render(view)
    assert rendered =~ "Bob confirmed payroll access was narrowed."
    refute rendered =~ "Alice opened the incident timeline."
  end

  test "compares two temporal windows in tenant QA", %{conn: conn} do
    user = create_user!("tenant-qa-compare")
    tenant = create_tenant!("Tenant QA Compare", user)
    seed_temporal_semantic_data!(tenant.schema_name)

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, view, _html} = live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/qa")

    view
    |> element("#tenant-qa-form")
    |> render_change(%{
      "question" => "What changed?",
      "limit" => "5",
      "since" => "2026-03-05T11:30:00",
      "until" => "2026-03-05T12:30:00",
      "compare_since" => "2026-03-05T12:30:00",
      "compare_until" => "2026-03-05T13:30:00"
    })

    view
    |> element("#tenant-qa-compare")
    |> render_click()

    rendered = render(view)
    assert rendered =~ "Window Comparison"
    assert rendered =~ "Entity Delta"
    assert rendered =~ "Fact Delta"
    assert rendered =~ "New People"
    assert rendered =~ "New Claims"
    assert rendered =~ "Baseline Window"
    assert rendered =~ "Comparison Window"
    assert rendered =~ "Alice opened the incident timeline."
    assert rendered =~ "Bob confirmed payroll access was narrowed."
  end

  test "hydrates QA form state from query params", %{conn: conn} do
    user = create_user!("tenant-qa-hydrate")
    tenant = create_tenant!("Tenant QA Hydrate", user)

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, _view, html} =
      live(
        conn,
        ~p"/control-plane/tenants/#{tenant.subject_name}/qa?#{%{question: "What changed between these periods?", since: "2026-03-05T11:30:00", until: "2026-03-05T12:30:00", compare_since: "2026-03-05T12:30:00", compare_until: "2026-03-05T13:30:00", limit: "7"}}"
      )

    assert html =~ ~s(value="What changed between these periods?")
    assert html =~ ~s(value="2026-03-05T11:30:00")
    assert html =~ ~s(value="2026-03-05T12:30:00")
    assert html =~ ~s(value="2026-03-05T13:30:00")
    assert html =~ ~s(value="7")
  end

  defp create_user!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      ControlPlane.register_user(%{
        email: "#{prefix}-#{suffix}@example.com",
        name: "Tenant QA User #{suffix}",
        password: "threadr-password-#{suffix}"
      })

    user
  end

  defp create_tenant!(name_prefix, owner_user) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(
        %{
          name: "#{name_prefix} #{suffix}",
          subject_name: "tenant-qa-#{suffix}"
        },
        owner_user: owner_user
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

    _follow_up_message =
      persist_message!(
        tenant.subject_name,
        tenant.schema_name,
        "bob",
        "ops",
        "Bob followed up with Carol on endpoint isolation.",
        ["carol"],
        DateTime.add(observed_at, 60, :second)
      )
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
