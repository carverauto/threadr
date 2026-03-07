defmodule ThreadrWeb.Api.V1.HistoryControllerTest do
  use ThreadrWeb.ConnCase, async: false

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Service
  alias Threadr.Events.{ChatMessage, Envelope}
  alias Threadr.Messaging.Topology
  alias Threadr.TenantData.Ingest

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

  test "GET /api/v1/tenants/:subject_name/history returns tenant history", %{conn: conn} do
    owner = create_user!("history-api")
    tenant = create_tenant!("History API", owner)

    persist_message!(
      tenant.subject_name,
      "alice",
      "ops",
      "Alice mentioned Bob in incident response planning.",
      ["bob"],
      ~U[2026-03-05 12:00:00Z]
    )

    conn =
      conn
      |> api_key_conn(owner)
      |> get(~p"/api/v1/tenants/#{tenant.subject_name}/history")

    assert %{"data" => data} = json_response(conn, 200)
    assert data["tenant_subject_name"] == tenant.subject_name
    assert data["membership_role"] == "owner"
    assert hd(data["messages"])["body"] =~ "Alice mentioned Bob"
  end

  test "POST /api/v1/tenants/:subject_name/history/compare compares windows", %{conn: conn} do
    owner = create_user!("history-compare-api")
    tenant = create_tenant!("History Compare API", owner)

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
      |> api_key_conn(owner)
      |> post(~p"/api/v1/tenants/#{tenant.subject_name}/history/compare", %{
        "since" => "2026-03-05T11:30:00",
        "until" => "2026-03-05T12:30:00",
        "compare_since" => "2026-03-05T12:30:00",
        "compare_until" => "2026-03-05T13:30:00"
      })

    assert %{"data" => data} = json_response(conn, 200)
    assert data["tenant_subject_name"] == tenant.subject_name
    assert data["answer"]["provider"] == "test"

    assert data["comparison"]["baseline"]["messages"] |> hd() |> Map.fetch!("body") ==
             "Alice opened the incident timeline."

    assert data["comparison"]["comparison"]["messages"] |> hd() |> Map.fetch!("body") ==
             "Bob confirmed payroll access was narrowed."

    assert Map.has_key?(data, "entity_delta")
    assert Map.has_key?(data, "fact_delta")
    assert data["answer"]["content"] =~ "Baseline Window:"
    assert data["answer"]["content"] =~ "Comparison Window:"
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
end
