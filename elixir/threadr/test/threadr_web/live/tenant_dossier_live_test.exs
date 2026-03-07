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
  alias Threadr.TenantData.{Actor, Ingest}

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

    {:ok, _message} = Ingest.persist_envelope(envelope)
  end

  defp fetch_actor(tenant_schema, handle) do
    Actor
    |> Ash.Query.filter(expr(handle == ^handle))
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
