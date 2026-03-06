defmodule Threadr.ControlPlane.BotOperationDispatcherTest do
  use Threadr.DataCase, async: false

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.BotOperationDispatcher
  alias Threadr.ControlPlane.Service

  defmodule FailingReconciler do
    @behaviour Threadr.ControlPlane.BotReconciler

    @impl true
    def reconcile(_bot, _operation), do: {:error, :dispatcher_test_failure}
  end

  setup do
    previous = Application.get_env(:threadr, :bot_reconciler)

    previous_dispatcher =
      Application.get_env(:threadr, Threadr.ControlPlane.BotOperationDispatcher)

    on_exit(fn -> Application.put_env(:threadr, :bot_reconciler, previous) end)

    on_exit(fn ->
      Application.put_env(
        :threadr,
        Threadr.ControlPlane.BotOperationDispatcher,
        previous_dispatcher
      )
    end)

    :ok
  end

  test "failed bot reconciliation retries before marking the operation failed" do
    Application.put_env(:threadr, :bot_reconciler, FailingReconciler)

    Application.put_env(:threadr, Threadr.ControlPlane.BotOperationDispatcher,
      enabled: true,
      poll_interval_ms: 5_000,
      batch_size: 25,
      max_attempts: 2,
      retry_backoff_ms: 0
    )

    owner = create_user!("owner")
    tenant = create_tenant!("Owned", owner)

    {:ok, bot} =
      ControlPlane.create_bot(
        %{
          tenant_id: tenant.id,
          name: "irc-main",
          platform: "irc",
          channels: ["#threadr"],
          settings: %{"server" => "irc.example.com", "nick" => "threadr-bot"}
        },
        context: %{system: true}
      )

    {:ok, bot} = ControlPlane.request_bot_reconcile(bot, %{}, context: %{system: true})

    {:ok, _operation} =
      ControlPlane.create_bot_reconcile_operation(
        %{
          tenant_id: tenant.id,
          bot_id: bot.id,
          operation: "apply",
          status: "pending",
          payload: %{
            "operation" => "apply",
            "bot" => %{
              "id" => bot.id,
              "tenant_id" => bot.tenant_id,
              "name" => bot.name,
              "platform" => bot.platform,
              "desired_state" => bot.desired_state,
              "status" => bot.status,
              "channels" => bot.channels,
              "settings" => bot.settings,
              "deployment_name" => bot.deployment_name
            }
          },
          attempt_count: 0,
          next_attempt_at: DateTime.utc_now()
        },
        context: %{system: true}
      )

    assert :ok = BotOperationDispatcher.process_pending_once()

    assert {:ok, [operation]} =
             ControlPlane.list_bot_reconcile_operations(
               context: %{system: true},
               query: [filter: [bot_id: bot.id], sort: [inserted_at: :desc], limit: 1]
             )

    assert operation.operation == "apply"
    assert operation.status == "pending"
    assert operation.attempt_count == 1
    assert operation.last_error =~ "dispatcher_test_failure"
    assert not is_nil(operation.next_attempt_at)

    assert {:ok, reloaded_bot} = ControlPlane.get_bot(bot.id, context: %{system: true})
    assert reloaded_bot.status == :reconciling

    assert :ok = BotOperationDispatcher.process_pending_once()

    assert {:ok, [operation]} =
             ControlPlane.list_bot_reconcile_operations(
               context: %{system: true},
               query: [filter: [bot_id: bot.id], sort: [inserted_at: :desc], limit: 1]
             )

    assert operation.status == "failed"
    assert operation.attempt_count == 2
    assert is_nil(operation.next_attempt_at)

    assert {:ok, reloaded_bot} = ControlPlane.get_bot(bot.id, context: %{system: true})
    assert reloaded_bot.status == :error
  end

  defp create_user!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      ControlPlane.register_user(%{
        email: "#{prefix}-#{suffix}@example.com",
        name: "Dispatcher User #{suffix}",
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
end
