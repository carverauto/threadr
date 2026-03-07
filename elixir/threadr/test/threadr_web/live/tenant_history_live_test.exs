defmodule ThreadrWeb.TenantHistoryLiveTest do
  use ThreadrWeb.ConnCase, async: false

  import AshAuthentication.Phoenix.Plug, only: [store_in_session: 2]
  import Phoenix.LiveViewTest

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Service
  alias Threadr.Events.{ChatMessage, Envelope}
  alias Threadr.Messaging.Topology
  alias Threadr.TenantData.{Extraction, Ingest}

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

  test "renders tenant history and filters messages", %{conn: conn} do
    user = create_user!("tenant-history")
    tenant = create_tenant!("History Tenant", user)

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
      "carol",
      "intel",
      "Carol reviewed malware cluster overlaps.",
      [],
      ~U[2026-03-05 13:30:00Z]
    )

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, view, html} = live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/history")

    assert html =~ "Tenant History"
    assert html =~ "Alice mentioned Bob in incident response planning."
    assert html =~ "Carol reviewed malware cluster overlaps."

    view
    |> form("#tenant-history-form", %{
      "actor_handle" => "alice",
      "query" => "",
      "channel_name" => "",
      "since" => "",
      "until" => "",
      "limit" => "50"
    })
    |> render_change()

    rendered = render(view)
    assert rendered =~ "Alice mentioned Bob in incident response planning."
    refute rendered =~ "Carol reviewed malware cluster overlaps."
  end

  test "updates tenant history when a new message is ingested", %{conn: conn} do
    user = create_user!("tenant-history-live")
    tenant = create_tenant!("Live History Tenant", user)

    persist_message!(
      tenant.subject_name,
      "alice",
      "ops",
      "Alice opened the incident channel.",
      [],
      ~U[2026-03-05 12:00:00Z]
    )

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, view, html} = live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/history")

    assert html =~ "Alice opened the incident channel."
    refute html =~ "Bob confirmed the first phishing recipient."

    persist_message!(
      tenant.subject_name,
      "bob",
      "ops",
      "Bob confirmed the first phishing recipient.",
      [],
      ~U[2026-03-05 12:05:00Z]
    )

    assert_eventually(fn ->
      render(view) =~ "Bob confirmed the first phishing recipient."
    end)
  end

  test "renders extracted entities and facts for messages", %{conn: conn} do
    user = create_user!("tenant-history-extraction")
    tenant = create_tenant!("History Extraction Tenant", user)

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

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, _view, html} = live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/history")

    assert html =~ "person: Alice"
    assert html =~ "Bob"
    assert html =~ "reported"
    assert html =~ "payroll access was limited"
    assert html =~ "Facts Over Time"
    assert html =~ "Top fact: Bob reported payroll access was limited"
  end

  test "filters history by extracted entity and fact type", %{conn: conn} do
    user = create_user!("tenant-history-filters")
    tenant = create_tenant!("History Filter Tenant", user)

    {:ok, message_one} =
      persist_message!(
        tenant.subject_name,
        "alice",
        "ops",
        "Alice told Bob that payroll access was limited on 2026-03-05.",
        ["bob"],
        ~U[2026-03-05 12:00:00Z]
      )

    {:ok, _message_two} =
      persist_message!(
        tenant.subject_name,
        "carol",
        "intel",
        "Carol reviewed the phishing timeline.",
        [],
        ~U[2026-03-05 13:00:00Z]
      )

    assert {:ok, _} =
             Extraction.extract_and_persist_message(
               message_one,
               tenant.subject_name,
               tenant.schema_name,
               provider: Threadr.TestExtractionProvider,
               generation_provider: Threadr.TestGenerationProvider,
               model: "test-llm"
             )

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, view, _html} = live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/history")

    view
    |> form("#tenant-history-form", %{
      "query" => "",
      "actor_handle" => "",
      "channel_name" => "",
      "entity_name" => "Alice",
      "entity_type" => "person",
      "fact_type" => "access_statement",
      "since" => "",
      "until" => "",
      "limit" => "50"
    })
    |> render_change()

    rendered = render(view)
    assert rendered =~ "Alice told Bob that payroll access was limited on 2026-03-05."
    refute rendered =~ "Carol reviewed the phishing timeline."
  end

  test "compares two history windows", %{conn: conn} do
    user = create_user!("tenant-history-compare")
    tenant = create_tenant!("History Compare Tenant", user)

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
      "bob",
      "ops",
      "Bob confirmed payroll access was narrowed.",
      [],
      ~U[2026-03-05 13:00:00Z]
    )

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, view, _html} = live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/history")

    view
    |> form("#tenant-history-form", %{
      "query" => "",
      "actor_handle" => "",
      "channel_name" => "",
      "entity_name" => "",
      "entity_type" => "",
      "fact_type" => "",
      "since" => "2026-03-05T11:30:00",
      "until" => "2026-03-05T12:30:00",
      "compare_since" => "2026-03-05T12:30:00",
      "compare_until" => "2026-03-05T13:30:00",
      "limit" => "50"
    })
    |> render_change()

    view
    |> element("#tenant-history-compare-submit")
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
    assert rendered =~ "Bob confirmed payroll access was narrowed."
  end

  test "renders a back link to QA when opened from a QA compare drill-down", %{conn: conn} do
    user = create_user!("tenant-history-origin-qa")
    tenant = create_tenant!("History Origin QA Tenant", user)

    persist_message!(
      tenant.subject_name,
      "alice",
      "ops",
      "Alice opened the incident timeline.",
      [],
      ~U[2026-03-05 12:00:00Z]
    )

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, _view, html} =
      live(
        conn,
        ~p"/control-plane/tenants/#{tenant.subject_name}/history?#{%{entity_name: "Alice", entity_type: "person", since: "2026-03-05T11:30:00", until: "2026-03-05T12:30:00", origin_surface: "qa", origin_question: "What changed for Alice?", origin_since: "2026-03-05T11:30:00", origin_until: "2026-03-05T12:30:00", origin_compare_since: "2026-03-05T12:30:00", origin_compare_until: "2026-03-05T13:30:00"}}"
      )

    assert html =~ "Back to Comparison"
    assert html =~ "/control-plane/tenants/#{tenant.subject_name}/qa?"
    assert html =~ "question=What+changed+for+Alice%3F"
    assert html =~ "compare_since=2026-03-05T12%3A30%3A00"
  end

  defp create_user!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      ControlPlane.register_user(%{
        email: "#{prefix}-#{suffix}@example.com",
        name: "Tenant History User #{suffix}",
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
          subject_name: "history-live-#{suffix}"
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
