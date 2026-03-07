defmodule Threadr.ControlPlane.BotStatusObserverTest do
  use Threadr.DataCase, async: false

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.BotStatusObserver
  alias Threadr.ControlPlane.Service

  defmodule FakeKubernetesClient do
    @behaviour Threadr.ControlPlane.KubernetesClient

    @impl true
    def apply_deployment(_namespace, _name, _manifest), do: {:ok, %{}}

    @impl true
    def delete_deployment(_namespace, _name), do: {:ok, %{}}

    @impl true
    def get_deployment(namespace, name) do
      send(test_pid(), {:get_deployment, namespace, name})

      deployment =
        Application.fetch_env!(:threadr, __MODULE__)
        |> Keyword.fetch!(:deployment)

      {:ok, deployment}
    end

    defp test_pid do
      Application.fetch_env!(:threadr, __MODULE__)
      |> Keyword.fetch!(:notify)
    end
  end

  setup do
    previous_client = Application.get_env(:threadr, :kubernetes_client)
    previous_config = Application.get_env(:threadr, FakeKubernetesClient)
    test_pid = self()

    Application.put_env(:threadr, :kubernetes_client, FakeKubernetesClient)
    Application.put_env(:threadr, FakeKubernetesClient, notify: test_pid, deployment: nil)

    on_exit(fn ->
      Application.put_env(:threadr, :kubernetes_client, previous_client)
      Application.put_env(:threadr, FakeKubernetesClient, previous_config)
    end)

    :ok
  end

  test "marks a bot running when the deployment is fully ready" do
    owner = create_user!("owner")
    tenant = create_tenant!("Ready", owner)
    bot = create_bot!(tenant, %{status: "reconciling"})

    Application.put_env(:threadr, FakeKubernetesClient,
      notify: self(),
      deployment: ready_deployment(bot.deployment_name, replicas: 1)
    )

    deployment_name = bot.deployment_name
    assert :ok = BotStatusObserver.observe_once()
    assert_receive {:get_deployment, "threadr", ^deployment_name}

    assert {:ok, reloaded_bot} = ControlPlane.get_bot(bot.id, context: %{system: true})
    assert reloaded_bot.status == :running
  end

  test "marks a bot stopped when the deployment is scaled to zero" do
    owner = create_user!("owner")
    tenant = create_tenant!("Stopped", owner)
    bot = create_bot!(tenant, %{desired_state: "stopped", status: "reconciling"})

    Application.put_env(:threadr, FakeKubernetesClient,
      notify: self(),
      deployment: ready_deployment(bot.deployment_name, replicas: 0, available: 0, ready: 0)
    )

    deployment_name = bot.deployment_name
    assert :ok = BotStatusObserver.observe_once()
    assert_receive {:get_deployment, "threadr", ^deployment_name}

    assert {:ok, reloaded_bot} = ControlPlane.get_bot(bot.id, context: %{system: true})
    assert reloaded_bot.status == :stopped
  end

  test "marks a bot degraded when the deployment is not fully available" do
    owner = create_user!("owner")
    tenant = create_tenant!("Degraded", owner)
    bot = create_bot!(tenant, %{status: "reconciling"})

    Application.put_env(:threadr, FakeKubernetesClient,
      notify: self(),
      deployment:
        ready_deployment(bot.deployment_name,
          replicas: 2,
          available: 1,
          ready: 1,
          updated: 1,
          unavailable: 1
        )
    )

    deployment_name = bot.deployment_name
    assert :ok = BotStatusObserver.observe_once()
    assert_receive {:get_deployment, "threadr", ^deployment_name}

    assert {:ok, reloaded_bot} = ControlPlane.get_bot(bot.id, context: %{system: true})
    assert reloaded_bot.status == :degraded
  end

  test "marks a running bot error when the deployment is missing" do
    owner = create_user!("owner")
    tenant = create_tenant!("Missing", owner)
    bot = create_bot!(tenant, %{status: "reconciling"})

    Application.put_env(:threadr, FakeKubernetesClient, notify: self(), deployment: nil)

    deployment_name = bot.deployment_name
    assert :ok = BotStatusObserver.observe_once()
    assert_receive {:get_deployment, "threadr", ^deployment_name}

    assert {:ok, reloaded_bot} = ControlPlane.get_bot(bot.id, context: %{system: true})
    assert reloaded_bot.status == :error
  end

  defp ready_deployment(name, opts) do
    replicas = Keyword.get(opts, :replicas, 1)
    available = Keyword.get(opts, :available, replicas)
    ready = Keyword.get(opts, :ready, replicas)
    updated = Keyword.get(opts, :updated, replicas)
    unavailable = Keyword.get(opts, :unavailable, max(replicas - available, 0))

    %{
      "metadata" => %{"name" => name, "generation" => 1},
      "spec" => %{"replicas" => replicas},
      "status" => %{
        "observedGeneration" => 1,
        "availableReplicas" => available,
        "readyReplicas" => ready,
        "updatedReplicas" => updated,
        "unavailableReplicas" => unavailable
      }
    }
  end

  defp create_user!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      ControlPlane.register_user(%{
        email: "#{prefix}-#{suffix}@example.com",
        name: "Observer User #{suffix}",
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

  defp create_bot!(tenant, attrs) do
    {:ok, bot} =
      ControlPlane.create_bot(
        Map.merge(
          %{
            tenant_id: tenant.id,
            name: "irc-main",
            platform: "irc",
            desired_state: "running",
            channels: ["#threadr"],
            settings: %{"server" => "irc.example.com", "nick" => "threadr-bot"},
            deployment_name: "threadr-#{tenant.subject_name}-irc-main"
          },
          Map.drop(attrs, [:status])
        ),
        context: %{system: true}
      )

    case Map.get(attrs, :status) do
      "reconciling" ->
        {:ok, bot} = ControlPlane.request_bot_reconcile(bot, %{}, context: %{system: true})
        bot

      status when status in ["running", "stopped", "degraded", "error", "deleting"] ->
        {:ok, bot} =
          ControlPlane.report_bot_status(
            bot,
            %{target_status: status},
            context: %{system: true}
          )

        bot

      _ ->
        bot
    end
  end
end
