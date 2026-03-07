defmodule ThreadrWeb.TenantHistoryLiveTest do
  use ThreadrWeb.ConnCase, async: false

  import AshAuthentication.Phoenix.Plug, only: [store_in_session: 2]
  import Phoenix.LiveViewTest

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Service
  alias Threadr.Events.{ChatMessage, Envelope}
  alias Threadr.Messaging.Topology
  alias Threadr.TenantData.Ingest

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

    {:ok, _message} = Ingest.persist_envelope(envelope)
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
