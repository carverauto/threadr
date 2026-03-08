defmodule ThreadrWeb.BotStatusControllerTest do
  use ThreadrWeb.ConnCase, async: false

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Service

  setup do
    previous_token = Application.get_env(:threadr, :control_plane_token)
    Application.put_env(:threadr, :control_plane_token, "threadr-test-control-plane-token")

    on_exit(fn ->
      Application.put_env(:threadr, :control_plane_token, previous_token)
    end)

    :ok
  end

  test "POST /api/control-plane/tenants/:subject_name/bots/:id/status updates bot status for the controller",
       %{conn: conn} do
    owner = create_user!("owner")
    tenant = create_tenant!("Observed", owner)
    bot = create_bot!(tenant)
    observed_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    conn =
      conn
      |> control_plane_conn()
      |> post(~p"/api/control-plane/tenants/#{tenant.subject_name}/bots/#{bot.id}/status", %{
        "status" => %{
          "status" => "running",
          "reason" => "deployment_available",
          "deployment_name" => bot.deployment_name,
          "observed_at" => observed_at,
          "metadata" => %{"available_replicas" => 1, "ready_replicas" => 1}
        }
      })

    assert %{
             "data" => %{
               "id" => bot_id,
               "status" => "running",
               "status_reason" => "deployment_available",
               "deployment_name" => deployment_name,
               "status_metadata" => %{
                 "available_replicas" => 1,
                 "ready_replicas" => 1,
                 "source" => "controller_callback"
               },
               "last_observed_at" => last_observed_at
             }
           } = json_response(conn, 200)

    assert bot_id == bot.id
    assert deployment_name == bot.deployment_name
    assert {:ok, _, _} = DateTime.from_iso8601(last_observed_at)
    assert String.starts_with?(last_observed_at, String.trim_trailing(observed_at, "Z"))

    assert {:ok, reloaded_bot} = ControlPlane.get_bot(bot.id, context: %{system: true})
    assert reloaded_bot.status == :running
    assert reloaded_bot.status_reason == "deployment_available"
    assert reloaded_bot.status_metadata["source"] == "controller_callback"
  end

  test "POST /api/control-plane/tenants/:subject_name/bots/:id/status returns 401 without the control-plane token",
       %{conn: conn} do
    owner = create_user!("owner")
    tenant = create_tenant!("Unauthorized", owner)
    bot = create_bot!(tenant)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> post(~p"/api/control-plane/tenants/#{tenant.subject_name}/bots/#{bot.id}/status", %{
        "status" => %{"status" => "running"}
      })

    assert json_response(conn, 401) == %{"errors" => %{"detail" => "Unauthorized"}}
  end

  test "POST /api/control-plane/tenants/:subject_name/bots/:id/status returns 409 for stale deployment names",
       %{conn: conn} do
    owner = create_user!("owner")
    tenant = create_tenant!("Mismatch", owner)
    bot = create_bot!(tenant)

    conn =
      conn
      |> control_plane_conn()
      |> post(~p"/api/control-plane/tenants/#{tenant.subject_name}/bots/#{bot.id}/status", %{
        "status" => %{
          "status" => "running",
          "deployment_name" => "threadr-#{tenant.subject_name}-new-rollout"
        }
      })

    assert json_response(conn, 409) == %{"errors" => %{"detail" => "Deployment mismatch"}}
  end

  test "POST /api/control-plane/tenants/:subject_name/bots/:id/status returns 409 for stale generations",
       %{conn: conn} do
    owner = create_user!("owner")
    tenant = create_tenant!("Generation", owner)
    bot = create_bot!(tenant)
    emit_controller_contract!(bot)

    conn =
      conn
      |> control_plane_conn()
      |> post(~p"/api/control-plane/tenants/#{tenant.subject_name}/bots/#{bot.id}/status", %{
        "status" => %{
          "status" => "running",
          "deployment_name" => bot.deployment_name,
          "generation" => 999
        }
      })

    assert json_response(conn, 409) == %{"errors" => %{"detail" => "Generation mismatch"}}
  end

  test "POST /api/control-plane/tenants/:subject_name/bots/:id/status returns 404 for missing bots",
       %{conn: conn} do
    owner = create_user!("owner")
    tenant = create_tenant!("Missing", owner)

    conn =
      conn
      |> control_plane_conn()
      |> post(
        ~p"/api/control-plane/tenants/#{tenant.subject_name}/bots/#{Ecto.UUID.generate()}/status",
        %{"status" => %{"status" => "running"}}
      )

    assert json_response(conn, 404) == %{"errors" => %{"detail" => "Bot not found"}}
  end

  test "POST /api/control-plane/tenants/:subject_name/bots/:id/status finalizes deleted bots",
       %{conn: conn} do
    owner = create_user!("owner")
    tenant = create_tenant!("Deleted", owner)
    bot = create_bot!(tenant)
    emit_controller_contract!(bot)
    {:ok, bot} = ControlPlane.begin_bot_delete(bot, %{}, context: %{system: true})

    conn =
      conn
      |> control_plane_conn()
      |> post(~p"/api/control-plane/tenants/#{tenant.subject_name}/bots/#{bot.id}/status", %{
        "status" => %{
          "status" => "deleted",
          "reason" => "deployment_deleted",
          "deployment_name" => bot.deployment_name,
          "generation" => 1
        }
      })

    assert %{"data" => %{"id" => bot_id, "status" => "deleted"}} = json_response(conn, 200)
    assert bot_id == bot.id

    assert {:error, %Ash.Error.Invalid{errors: errors}} =
             ControlPlane.get_bot(bot.id, context: %{system: true})

    assert Enum.any?(errors, &match?(%Ash.Error.Query.NotFound{}, &1))

    assert {:error, %Ash.Error.Invalid{errors: contract_errors}} =
             ControlPlane.get_bot_controller_contract(bot.id, context: %{system: true})

    assert Enum.any?(contract_errors, &match?(%Ash.Error.Query.NotFound{}, &1))
  end

  test "GET /api/control-plane/bot-contracts returns emitted contracts for the controller", %{
    conn: conn
  } do
    owner = create_user!("owner")
    tenant = create_tenant!("Contract Index", owner)
    bot = create_bot!(tenant)
    emit_controller_contract!(bot)

    conn =
      conn
      |> control_plane_conn()
      |> get(~p"/api/control-plane/bot-contracts")

    assert %{"data" => contracts} = json_response(conn, 200)
    contract = Enum.find(contracts, &(&1["bot_id"] == bot.id))
    assert contract
    assert contract["bot_id"] == bot.id
    assert contract["generation"] == 1
    assert contract["deployment_name"] == bot.deployment_name
    assert contract["contract"]["apiVersion"] == "cache.threadr.ai/v1alpha1"
    assert contract["contract"]["kind"] == "ThreadrBot"
    assert contract["contract"]["metadata"]["name"] == bot.deployment_name
    assert get_in(contract, ["contract", "spec", "controlPlane", "generation"]) == 1
  end

  test "GET /api/control-plane/tenants/:subject_name/bots/:id/contract returns the current desired-state contract",
       %{conn: conn} do
    owner = create_user!("owner")
    tenant = create_tenant!("Contract Show", owner)
    bot = create_bot!(tenant)
    emit_controller_contract!(bot)

    conn =
      conn
      |> control_plane_conn()
      |> get(~p"/api/control-plane/tenants/#{tenant.subject_name}/bots/#{bot.id}/contract")

    assert %{
             "data" => %{
               "bot_id" => bot_id,
               "generation" => 1,
               "deployment_name" => deployment_name,
               "operation" => "apply"
             }
           } = json_response(conn, 200)

    assert bot_id == bot.id
    assert deployment_name == bot.deployment_name
  end

  defp control_plane_conn(conn) do
    conn
    |> put_req_header("authorization", "Bearer threadr-test-control-plane-token")
    |> put_req_header("accept", "application/json")
  end

  defp create_user!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      ControlPlane.register_user(%{
        email: "#{prefix}-#{suffix}@example.com",
        name: "Controller User #{suffix}",
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
          subject_name: "#{String.downcase(prefix)}-#{suffix}"
        },
        owner_user: owner
      )

    tenant
  end

  defp create_bot!(tenant) do
    {:ok, bot} =
      ControlPlane.create_bot(
        %{
          tenant_id: tenant.id,
          name: "irc-main",
          platform: "irc",
          channels: ["#threadr"],
          settings: %{"server" => "irc.example.com", "nick" => "threadr-bot"},
          deployment_name: "threadr-#{tenant.subject_name}-irc-main"
        },
        context: %{system: true}
      )

    {:ok, bot} = ControlPlane.request_bot_reconcile(bot, %{}, context: %{system: true})
    bot
  end

  defp emit_controller_contract!(bot) do
    {:ok, _operation} =
      ControlPlane.create_bot_reconcile_operation(
        %{
          tenant_id: bot.tenant_id,
          bot_id: bot.id,
          operation: if(bot.desired_state == "deleted", do: "delete", else: "apply"),
          status: "pending",
          payload: %{},
          attempt_count: 0,
          next_attempt_at: DateTime.utc_now()
        },
        context: %{system: true}
      )

    drain_bot_operations!()
  end

  defp drain_bot_operations! do
    assert :ok = Threadr.ControlPlane.BotOperationDispatcher.process_pending_once()
  end
end
