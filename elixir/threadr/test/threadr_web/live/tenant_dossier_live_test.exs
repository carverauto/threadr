defmodule ThreadrWeb.TenantDossierLiveTest do
  use ThreadrWeb.ConnCase, async: false

  import Ash.Expr
  import AshAuthentication.Phoenix.Plug, only: [store_in_session: 2]
  import Phoenix.LiveViewTest
  require Ash.Query

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Service
  alias Threadr.Events.{ChatMessage, Envelope}
  alias Threadr.Messaging.Topology
  alias Threadr.TenantData.{Actor, Extraction, Ingest}

  setup do
    previous_ml_config = Application.get_env(:threadr, Threadr.ML, [])

    Application.put_env(
      :threadr,
      Threadr.ML,
      Keyword.merge(previous_ml_config,
        generation: [provider: Threadr.TestGenerationProvider, model: "test-chat"]
      )
    )

    on_exit(fn ->
      Application.put_env(:threadr, Threadr.ML, previous_ml_config)
    end)

    :ok
  end

  test "renders an actor dossier from ingested graph data", %{conn: conn} do
    user = create_user!("tenant-dossier")
    tenant = create_tenant!("Dossier Tenant", user)

    persist_message!(
      tenant.subject_name,
      "alice",
      "ops",
      "Alice mentioned Bob in incident response planning.",
      ["bob"],
      ~U[2026-03-05 12:00:00Z]
    )

    persist_message!(
      tenant.subject_name,
      "alice",
      "ops",
      "Alice followed up with Carol on endpoint isolation.",
      ["carol"],
      ~U[2026-03-05 12:05:00Z]
    )

    {:ok, actor} = fetch_actor(tenant.schema_name, "alice")

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, _view, html} =
      live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/dossiers/actor/#{actor.id}")

    assert html =~ "Dossier"
    assert html =~ "Alice"
    assert html =~ "Recent Messages"
    assert html =~ "Top Relationships"
    assert html =~ "Bob"
  end

  test "updates an actor dossier when a new related message is ingested", %{conn: conn} do
    user = create_user!("tenant-dossier-live")
    tenant = create_tenant!("Live Dossier Tenant", user)

    persist_message!(
      tenant.subject_name,
      "alice",
      "ops",
      "Alice mentioned Bob in incident response planning.",
      ["bob"],
      ~U[2026-03-05 12:00:00Z]
    )

    {:ok, actor} = fetch_actor(tenant.schema_name, "alice")

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, view, html} =
      live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/dossiers/actor/#{actor.id}")

    assert html =~ "Alice mentioned Bob in incident response planning."
    refute html =~ "Alice followed up with Carol on endpoint isolation."

    persist_message!(
      tenant.subject_name,
      "alice",
      "ops",
      "Alice followed up with Carol on endpoint isolation.",
      ["carol"],
      ~U[2026-03-05 12:05:00Z]
    )

    assert_eventually(fn ->
      render(view) =~ "Alice followed up with Carol on endpoint isolation."
    end)
  end

  test "renders extracted entities and facts in the dossier", %{conn: conn} do
    user = create_user!("tenant-dossier-extraction")
    tenant = create_tenant!("Dossier Extraction Tenant", user)

    {:ok, message} =
      persist_message!(
        tenant.subject_name,
        "alice",
        "ops",
        "Alice told Bob that payroll access was limited on 2026-03-05.",
        ["bob"],
        ~U[2026-03-05 12:00:00Z]
      )

    assert {:ok, _result} =
             Extraction.extract_and_persist_message(
               message,
               tenant.subject_name,
               tenant.schema_name,
               provider: Threadr.TestExtractionProvider,
               generation_provider: Threadr.TestGenerationProvider,
               model: "test-llm"
             )

    {:ok, actor} = fetch_actor(tenant.schema_name, "alice")

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, _view, html} =
      live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/dossiers/actor/#{actor.id}")

    assert html =~ "Extracted Entities"
    assert html =~ "person: Alice"
    assert html =~ "Extracted Facts"
    assert html =~ "Bob"
    assert html =~ "reported"
    assert html =~ "payroll access was limited"
    assert html =~ "Facts Over Time"
    assert html =~ "Top fact: Bob reported payroll access was limited"
  end

  test "compares two dossier periods for an actor", %{conn: conn} do
    user = create_user!("tenant-dossier-compare")
    tenant = create_tenant!("Dossier Compare Tenant", user)

    persist_message!(
      tenant.subject_name,
      "alice",
      "ops",
      "Alice opened the incident timeline.",
      [],
      ~U[2026-03-05 12:00:00Z]
    )

    persist_message!(
      tenant.subject_name,
      "alice",
      "ops",
      "Alice confirmed payroll access was narrowed.",
      [],
      ~U[2026-03-05 13:00:00Z]
    )

    {:ok, actor} = fetch_actor(tenant.schema_name, "alice")

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, view, _html} =
      live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/dossiers/actor/#{actor.id}")

    view
    |> form("#dossier-compare-form", %{
      "since" => "2026-03-05T11:30:00",
      "until" => "2026-03-05T12:30:00",
      "compare_since" => "2026-03-05T12:30:00",
      "compare_until" => "2026-03-05T13:30:00"
    })
    |> render_change()

    view
    |> element("#dossier-compare-submit")
    |> render_click()

    rendered = render(view)
    assert rendered =~ "Comparison Summary"
    assert rendered =~ "Entity Delta"
    assert rendered =~ "Fact Delta"
    assert rendered =~ "New People"
    assert rendered =~ "New Claims"
    assert rendered =~ "Baseline Window"
    assert rendered =~ "Comparison Window"
    assert rendered =~ "Alice opened the incident timeline."
    assert rendered =~ "Alice confirmed payroll access was narrowed."
    assert rendered =~ "/control-plane/tenants/#{tenant.subject_name}/qa?"
    assert rendered =~ "What+changed+for+alice+between+these+periods%3F"
  end

  test "compares two dossier periods for a channel", %{conn: conn} do
    user = create_user!("tenant-dossier-channel-compare")
    tenant = create_tenant!("Dossier Channel Compare Tenant", user)

    persist_message!(
      tenant.subject_name,
      "alice",
      "ops",
      "Alice opened the incident timeline in ops.",
      [],
      ~U[2026-03-05 12:00:00Z]
    )

    persist_message!(
      tenant.subject_name,
      "bob",
      "ops",
      "Bob confirmed the payroll scope changed in ops.",
      [],
      ~U[2026-03-05 13:00:00Z]
    )

    {:ok, channel} = fetch_channel(tenant.schema_name, "ops")

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, view, _html} =
      live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/dossiers/channel/#{channel.id}")

    view
    |> form("#dossier-compare-form", %{
      "since" => "2026-03-05T11:30:00",
      "until" => "2026-03-05T12:30:00",
      "compare_since" => "2026-03-05T12:30:00",
      "compare_until" => "2026-03-05T13:30:00"
    })
    |> render_change()

    view
    |> element("#dossier-compare-submit")
    |> render_click()

    rendered = render(view)
    assert rendered =~ "Comparison Summary"
    assert rendered =~ "Entity Delta"
    assert rendered =~ "Fact Delta"
    assert rendered =~ "New People"
    assert rendered =~ "New Claims"
    assert rendered =~ "Baseline Window"
    assert rendered =~ "Comparison Window"
    assert rendered =~ "Alice opened the incident timeline in ops."
    assert rendered =~ "Bob confirmed the payroll scope changed in ops."
  end

  test "hydrates QA handoff links from the dossier context", %{conn: conn} do
    user = create_user!("tenant-dossier-qa-handoff")
    tenant = create_tenant!("Dossier QA Handoff Tenant", user)

    persist_message!(
      tenant.subject_name,
      "alice",
      "ops",
      "Alice mentioned Bob in incident response planning.",
      ["bob"],
      ~U[2026-03-05 12:00:00Z]
    )

    {:ok, actor} = fetch_actor(tenant.schema_name, "alice")

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, view, html} =
      live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/dossiers/actor/#{actor.id}")

    assert html =~ "/control-plane/tenants/#{tenant.subject_name}/qa?"
    assert html =~ "What+does+alice+know%3F"

    view
    |> form("#dossier-compare-form", %{
      "since" => "2026-03-05T11:30:00",
      "until" => "2026-03-05T12:30:00",
      "compare_since" => "2026-03-05T12:30:00",
      "compare_until" => "2026-03-05T13:30:00"
    })
    |> render_change()

    rendered = render(view)
    assert rendered =~ "Compare in QA"
    assert rendered =~ "compare_since=2026-03-05T12%3A30%3A00"
    assert rendered =~ "compare_until=2026-03-05T13%3A30%3A00"
  end

  test "hydrates compare form state from query params and preserves dossier origin in history links",
       %{conn: conn} do
    user = create_user!("tenant-dossier-origin")
    tenant = create_tenant!("Dossier Origin Tenant", user)

    {:ok, baseline_message} =
      persist_message!(
        tenant.subject_name,
        "alice",
        "ops",
        "Alice opened the incident timeline.",
        [],
        ~U[2026-03-05 12:00:00Z]
      )

    {:ok, comparison_message} =
      persist_message!(
        tenant.subject_name,
        "bob",
        "ops",
        "Bob told Alice that payroll access was limited on 2026-03-05.",
        [],
        ~U[2026-03-05 13:00:00Z]
      )

    assert {:ok, _} =
             Extraction.extract_and_persist_message(
               baseline_message,
               tenant.subject_name,
               tenant.schema_name,
               provider: Threadr.TestExtractionProvider,
               generation_provider: Threadr.TestGenerationProvider,
               model: "test-llm"
             )

    assert {:ok, _} =
             Extraction.extract_and_persist_message(
               comparison_message,
               tenant.subject_name,
               tenant.schema_name,
               provider: Threadr.TestExtractionProvider,
               generation_provider: Threadr.TestGenerationProvider,
               model: "test-llm"
             )

    {:ok, actor} = fetch_actor(tenant.schema_name, "alice")

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, view, html} =
      live(
        conn,
        ~p"/control-plane/tenants/#{tenant.subject_name}/dossiers/actor/#{actor.id}?#{%{since: "2026-03-05T11:30:00", until: "2026-03-05T12:30:00", compare_since: "2026-03-05T12:30:00", compare_until: "2026-03-05T13:30:00"}}"
      )

    assert html =~ ~s(value="2026-03-05T11:30:00")
    assert html =~ ~s(value="2026-03-05T13:30:00")

    view
    |> element("#dossier-compare-submit")
    |> render_click()

    rendered = render(view)
    assert rendered =~ "origin_surface=dossier"
    assert rendered =~ "origin_node_kind=actor"
    assert rendered =~ "origin_node_id=#{actor.id}"
    assert rendered =~ "origin_compare_since=2026-03-05T12%3A30%3A00"
  end

  defp create_user!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      ControlPlane.register_user(%{
        email: "#{prefix}-#{suffix}@example.com",
        name: "Tenant Dossier User #{suffix}",
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
          subject_name: "dossier-live-#{suffix}"
        },
        owner_user: owner_user
      )

    tenant
  end

  defp persist_message!(tenant_subject_name, actor, channel, body, mentions, observed_at) do
    envelope =
      Envelope.new(
        ChatMessage.from_map(%{
          platform: "discord",
          actor: actor,
          channel: channel,
          body: body,
          mentions: mentions,
          observed_at: observed_at,
          raw: %{"body" => body}
        }),
        "chat.message",
        Topology.subject_for(:chat_messages, tenant_subject_name),
        %{source: "discord", occurred_at: observed_at}
      )

    Ingest.persist_envelope(envelope)
  end

  defp fetch_actor(tenant_schema, handle) do
    Actor
    |> Ash.Query.filter(expr(handle == ^handle))
    |> Ash.read_one(tenant: tenant_schema)
  end

  defp fetch_channel(tenant_schema, name) do
    Threadr.TenantData.Channel
    |> Ash.Query.filter(expr(name == ^name))
    |> Ash.read_one(tenant: tenant_schema)
  end

  defp assert_eventually(fun, attempts \\ 20)

  defp assert_eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(100)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp assert_eventually(_fun, 0), do: flunk("condition was not met before timeout")
end
