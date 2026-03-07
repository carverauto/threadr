defmodule ThreadrWeb.Api.V1.BotControllerTest do
  use ThreadrWeb.ConnCase, async: false

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Service

  defmodule FakeKubernetesClient do
    @behaviour Threadr.ControlPlane.KubernetesClient

    @impl true
    def apply_deployment(namespace, name, manifest) do
      test_pid().({:apply_deployment, namespace, name, manifest})
      {:ok, %{"namespace" => namespace, "name" => name}}
    end

    @impl true
    def delete_deployment(namespace, name) do
      test_pid().({:delete_deployment, namespace, name})
      {:ok, %{"namespace" => namespace, "name" => name}}
    end

    @impl true
    def get_deployment(namespace, name) do
      test_pid().({:get_deployment, namespace, name})

      case Keyword.get(config(), :deployment) do
        nil -> {:ok, nil}
        deployment -> {:ok, deployment}
      end
    end

    defp test_pid do
      config()
      |> Keyword.fetch!(:notify)
    end

    defp config, do: Application.fetch_env!(:threadr, __MODULE__)
  end

  setup do
    previous_client = Application.get_env(:threadr, :kubernetes_client)
    previous_reconciler = Application.get_env(:threadr, :bot_reconciler)
    previous_client_config = Application.get_env(:threadr, FakeKubernetesClient)
    test_pid = self()

    Application.put_env(:threadr, :kubernetes_client, FakeKubernetesClient)
    Application.put_env(:threadr, :bot_reconciler, Threadr.ControlPlane.KubernetesBotReconciler)

    Application.put_env(:threadr, FakeKubernetesClient,
      notify: fn message -> send(test_pid, message) end
    )

    on_exit(fn ->
      Application.put_env(:threadr, :kubernetes_client, previous_client)
      Application.put_env(:threadr, :bot_reconciler, previous_reconciler)
      Application.put_env(:threadr, FakeKubernetesClient, previous_client_config)
    end)

    :ok
  end

  test "GET /api/v1/tenants/:subject_name/bots returns bots for accessible tenants", %{conn: conn} do
    owner = create_user!("owner")
    tenant = create_tenant!("Owned", owner)
    bot = create_bot!(tenant)

    conn =
      conn
      |> api_key_conn(owner)
      |> get(~p"/api/v1/tenants/#{tenant.subject_name}/bots")

    assert %{"data" => [returned_bot]} = json_response(conn, 200)
    assert returned_bot["id"] == bot.id
    assert returned_bot["name"] == bot.name
  end

  test "POST /api/v1/tenants/:subject_name/bots creates a bot for tenant managers", %{conn: conn} do
    owner = create_user!("owner")
    tenant = create_tenant!("Owned", owner)

    conn =
      conn
      |> api_key_conn(owner)
      |> post(~p"/api/v1/tenants/#{tenant.subject_name}/bots", %{
        "bot" => %{
          "name" => "irc-main",
          "platform" => "irc",
          "channels" => ["#threadr"],
          "settings" => %{
            "server" => "irc.example.com",
            "nick" => "threadr-bot",
            "password" => "super-secret"
          }
        }
      })

    assert %{"data" => bot} = json_response(conn, 201)
    assert bot["name"] == "irc-main"
    assert bot["platform"] == "irc"
    assert bot["tenant_id"] == tenant.id
    drain_bot_operations!()
    contract = controller_contract_for_bot!(bot["id"])
    deployment_name = contract.deployment_name
    workload = contract.contract["spec"]["workload"]
    assert String.starts_with?(deployment_name, "threadr-owned-")
    assert contract.operation == "apply"
    assert contract.generation == 1
    assert contract.contract["apiVersion"] == "cache.threadr.ai/v1alpha1"
    assert contract.contract["kind"] == "ThreadrBot"
    assert contract.contract["metadata"]["name"] == deployment_name
    assert contract.contract["metadata"]["namespace"] == "threadr"
    assert contract.contract["spec"]["controlPlane"]["generation"] == 1
    assert workload["replicas"] == 1
    assert workload["image"] == "threadr-bot:latest"
    assert bot["settings"]["env"]["THREADR_IRC_HOST"] == "irc.example.com"
    assert bot["settings"]["env"]["THREADR_IRC_NICK"] == "threadr-bot"
    assert bot["settings"]["env"]["THREADR_IRC_PASSWORD"] == "[REDACTED]"

    assert workload["env"] == [
             %{"name" => "THREADR_INGEST_ENABLED", "value" => "true"},
             %{"name" => "THREADR_BOT_ID", "value" => bot["id"]},
             %{"name" => "THREADR_TENANT_ID", "value" => tenant.id},
             %{"name" => "THREADR_TENANT_SUBJECT", "value" => tenant.subject_name},
             %{"name" => "THREADR_PLATFORM", "value" => "irc"},
             %{"name" => "THREADR_CHANNELS", "value" => "[\"#threadr\"]"},
             %{"name" => "THREADR_IRC_HOST", "value" => "irc.example.com"},
             %{"name" => "THREADR_IRC_NICK", "value" => "threadr-bot"},
             %{"name" => "THREADR_IRC_PASSWORD", "value" => "super-secret"}
           ]

    assert {:ok, [operation]} =
             ControlPlane.list_bot_reconcile_operations(
               context: %{system: true},
               query: [filter: [tenant_id: tenant.id], sort: [inserted_at: :desc], limit: 1]
             )

    assert operation.operation == "apply"
    assert operation.status == "dispatched"
    assert operation.payload["bot"]["name"] == "irc-main"

    assert {:ok, reloaded_bot} = ControlPlane.get_bot(bot["id"], context: %{system: true})
    assert reloaded_bot.status == :reconciling
    assert reloaded_bot.deployment_name == deployment_name
    assert reloaded_bot.desired_generation == 1
  end

  test "PATCH /api/v1/tenants/:subject_name/bots/:id updates a bot for tenant managers", %{
    conn: conn
  } do
    owner = create_user!("owner")
    tenant = create_tenant!("Owned", owner)
    bot = create_bot!(tenant)

    conn =
      conn
      |> api_key_conn(owner)
      |> patch(~p"/api/v1/tenants/#{tenant.subject_name}/bots/#{bot.id}", %{
        "bot" => %{
          "desired_state" => "stopped",
          "channels" => ["#ops"],
          "settings" => %{
            "server" => "irc2.example.com",
            "nick" => "threadr-bot-2",
            "password" => "second-secret"
          }
        }
      })

    assert %{"data" => updated_bot} = json_response(conn, 200)
    assert updated_bot["id"] == bot.id
    assert updated_bot["desired_state"] == "stopped"
    assert updated_bot["channels"] == ["#ops"]
    assert updated_bot["settings"]["env"]["THREADR_IRC_HOST"] == "irc2.example.com"
    assert updated_bot["settings"]["env"]["THREADR_IRC_NICK"] == "threadr-bot-2"
    assert updated_bot["settings"]["env"]["THREADR_IRC_PASSWORD"] == "[REDACTED]"
    drain_bot_operations!()
    contract = controller_contract_for_bot!(bot.id)
    deployment_name = contract.deployment_name
    workload = contract.contract["spec"]["workload"]
    assert contract.operation == "apply"
    assert contract.generation == 1
    assert contract.contract["spec"]["desiredState"] == "stopped"
    assert contract.contract["metadata"]["name"] == deployment_name
    assert workload["replicas"] == 0

    assert {:ok, [operation]} =
             ControlPlane.list_bot_reconcile_operations(
               context: %{system: true},
               query: [filter: [bot_id: bot.id], sort: [inserted_at: :desc], limit: 1]
             )

    assert operation.operation == "apply"
    assert operation.status == "dispatched"
    assert operation.payload["bot"]["desired_state"] == "stopped"

    assert {:ok, reloaded_bot} = ControlPlane.get_bot(bot.id, context: %{system: true})
    assert reloaded_bot.status == :reconciling
    assert reloaded_bot.deployment_name == deployment_name
    assert reloaded_bot.desired_generation == 1
  end

  test "POST /api/v1/tenants/:subject_name/bots renders Discord bot settings into the contract",
       %{
         conn: conn
       } do
    owner = create_user!("owner")
    tenant = create_tenant!("Owned", owner)

    conn =
      conn
      |> api_key_conn(owner)
      |> post(~p"/api/v1/tenants/#{tenant.subject_name}/bots", %{
        "bot" => %{
          "name" => "discord-main",
          "platform" => "discord",
          "channels" => ["123456789"],
          "settings" => %{
            "token" => "discord-super-secret",
            "application_id" => "1227806998788051027",
            "public_key" => "8bb798d162e922cfa9e1fed25808b1d4fb474355d094e89bfaa13cd9e0fe2163"
          }
        }
      })

    assert %{"data" => bot} = json_response(conn, 201)
    assert bot["platform"] == "discord"
    assert bot["channels"] == ["123456789"]
    assert bot["settings"]["env"]["THREADR_DISCORD_TOKEN"] == "[REDACTED]"
    assert bot["settings"]["env"]["THREADR_DISCORD_APPLICATION_ID"] == "1227806998788051027"

    assert bot["settings"]["env"]["THREADR_DISCORD_PUBLIC_KEY"] ==
             "8bb798d162e922cfa9e1fed25808b1d4fb474355d094e89bfaa13cd9e0fe2163"

    drain_bot_operations!()
    contract = controller_contract_for_bot!(bot["id"])
    workload = contract.contract["spec"]["workload"]

    assert contract.contract["spec"]["platform"] == "discord"

    assert workload["env"] == [
             %{"name" => "THREADR_INGEST_ENABLED", "value" => "true"},
             %{"name" => "THREADR_BOT_ID", "value" => bot["id"]},
             %{"name" => "THREADR_TENANT_ID", "value" => tenant.id},
             %{"name" => "THREADR_TENANT_SUBJECT", "value" => tenant.subject_name},
             %{"name" => "THREADR_PLATFORM", "value" => "discord"},
             %{"name" => "THREADR_CHANNELS", "value" => "[\"123456789\"]"},
             %{"name" => "THREADR_DISCORD_APPLICATION_ID", "value" => "1227806998788051027"},
             %{
               "name" => "THREADR_DISCORD_PUBLIC_KEY",
               "value" => "8bb798d162e922cfa9e1fed25808b1d4fb474355d094e89bfaa13cd9e0fe2163"
             },
             %{"name" => "THREADR_DISCORD_TOKEN", "value" => "discord-super-secret"}
           ]
  end

  test "POST /api/v1/tenants/:subject_name/bots rejects invalid platform config", %{conn: conn} do
    owner = create_user!("owner")
    tenant = create_tenant!("Owned", owner)

    conn =
      conn
      |> api_key_conn(owner)
      |> post(~p"/api/v1/tenants/#{tenant.subject_name}/bots", %{
        "bot" => %{
          "name" => "irc-main",
          "platform" => "irc",
          "channels" => ["#threadr"],
          "settings" => %{"server" => "irc.example.com"}
        }
      })

    assert %{"errors" => %{"detail" => detail}} = json_response(conn, 422)
    assert detail =~ "missing required env THREADR_IRC_NICK"
  end

  test "DELETE /api/v1/tenants/:subject_name/bots/:id deletes a bot for tenant managers", %{
    conn: conn
  } do
    owner = create_user!("owner")
    tenant = create_tenant!("Owned", owner)
    bot = create_bot!(tenant)

    conn =
      conn
      |> api_key_conn(owner)
      |> delete(~p"/api/v1/tenants/#{tenant.subject_name}/bots/#{bot.id}")

    assert response(conn, 204) == ""

    conn =
      conn
      |> recycle()
      |> api_key_conn(owner)
      |> get(~p"/api/v1/tenants/#{tenant.subject_name}/bots")

    assert %{"data" => []} = json_response(conn, 200)
    drain_bot_operations!()
    contract = controller_contract_for_bot!(bot.id)
    deployment_name = contract.deployment_name
    assert contract.operation == "delete"
    assert contract.generation == 1
    assert contract.contract["spec"]["desiredState"] == "deleted"
    assert contract.contract["spec"]["workload"]["replicas"] == 0

    assert {:ok, [operation]} =
             ControlPlane.list_bot_reconcile_operations(
               context: %{system: true},
               query: [filter: [tenant_id: tenant.id], sort: [inserted_at: :desc], limit: 1]
             )

    assert operation.operation == "delete"
    assert operation.status == "dispatched"
    assert operation.payload["bot"]["id"] == bot.id
    assert operation.payload["controller_contract"]["deployment_name"] == deployment_name
  end

  test "POST /api/v1/tenants/:subject_name/bots returns 403 for non-manager memberships", %{
    conn: conn
  } do
    owner = create_user!("owner")
    member = create_user!("member")
    tenant = create_tenant!("Owned", owner)

    {:ok, _membership} =
      ControlPlane.create_tenant_membership(
        %{
          user_id: member.id,
          tenant_id: tenant.id,
          role: "member"
        },
        context: %{system: true}
      )

    conn =
      conn
      |> api_key_conn(member)
      |> post(~p"/api/v1/tenants/#{tenant.subject_name}/bots", %{
        "bot" => %{
          "name" => "irc-main",
          "platform" => "irc",
          "channels" => ["#threadr"],
          "settings" => %{"server" => "irc.example.com", "nick" => "threadr-bot"}
        }
      })

    assert json_response(conn, 403) == %{"errors" => %{"detail" => "Forbidden"}}
  end

  test "PATCH /api/v1/tenants/:subject_name/bots/:id returns 403 for non-manager memberships", %{
    conn: conn
  } do
    owner = create_user!("owner")
    member = create_user!("member")
    tenant = create_tenant!("Owned", owner)
    bot = create_bot!(tenant)

    {:ok, _membership} =
      ControlPlane.create_tenant_membership(
        %{
          user_id: member.id,
          tenant_id: tenant.id,
          role: "member"
        },
        context: %{system: true}
      )

    conn =
      conn
      |> api_key_conn(member)
      |> patch(~p"/api/v1/tenants/#{tenant.subject_name}/bots/#{bot.id}", %{
        "bot" => %{"desired_state" => "stopped"}
      })

    assert json_response(conn, 403) == %{"errors" => %{"detail" => "Forbidden"}}
  end

  defp api_key_conn(conn, user) do
    {:ok, _api_key, plaintext_api_key} = Service.create_api_key(user, %{name: "bot-api"})

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
          deployment_name: "threadr-#{tenant.subject_name}-irc-main-existing"
        },
        context: %{system: true}
      )

    {:ok, bot} =
      ControlPlane.report_bot_status(
        bot,
        %{target_status: :running, deployment_name: bot.deployment_name},
        context: %{system: true}
      )

    bot
  end

  defp controller_contract_for_bot!(bot_id) do
    assert {:ok, contract} =
             ControlPlane.get_bot_controller_contract(bot_id, context: %{system: true})

    contract
  end

  defp drain_bot_operations! do
    assert :ok = Threadr.ControlPlane.BotOperationDispatcher.process_pending_once()
  end
end
