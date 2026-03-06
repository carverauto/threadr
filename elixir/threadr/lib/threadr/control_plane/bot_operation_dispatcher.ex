defmodule Threadr.ControlPlane.BotOperationDispatcher do
  @moduledoc """
  Supervised worker that drains pending bot reconciliation operations.
  """

  use GenServer

  alias Threadr.ControlPlane

  @name __MODULE__

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  def process_pending_once do
    config = dispatcher_config()
    dispatch_pending(config.batch_size, config)
  end

  def trigger do
    if Process.whereis(@name) do
      GenServer.cast(@name, :trigger)
    else
      :ok
    end
  end

  @impl true
  def init(_opts) do
    state = dispatcher_config()
    maybe_schedule(state)
    {:ok, state}
  end

  @impl true
  def handle_call(:process_pending_once, _from, state) do
    {:reply, dispatch_pending(state.batch_size, state), state}
  end

  @impl true
  def handle_cast(:trigger, state) do
    dispatch_pending(state.batch_size, state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:process_pending, state) do
    dispatch_pending(state.batch_size, state)
    maybe_schedule(state)
    {:noreply, state}
  end

  defp maybe_schedule(%{enabled: true, poll_interval_ms: poll_interval_ms}) do
    Process.send_after(self(), :process_pending, poll_interval_ms)
  end

  defp maybe_schedule(_state), do: :ok

  defp dispatcher_config do
    config = Application.get_env(:threadr, __MODULE__, [])

    %{
      enabled: Keyword.get(config, :enabled, true),
      poll_interval_ms: Keyword.get(config, :poll_interval_ms, 5_000),
      batch_size: Keyword.get(config, :batch_size, 25),
      max_attempts: Keyword.get(config, :max_attempts, 3),
      retry_backoff_ms: Keyword.get(config, :retry_backoff_ms, 5_000)
    }
  end

  defp dispatch_pending(batch_size, config) do
    system_opts = [context: %{system: true}]
    now = DateTime.utc_now()

    with {:ok, operations} <-
           ControlPlane.list_bot_reconcile_operations(
             Keyword.merge(system_opts,
               query: [
                 filter: [status: "pending"],
                 sort: [inserted_at: :asc],
                 limit: batch_size * 5
               ]
             )
           ) do
      operations
      |> Enum.filter(&eligible_operation?(&1, now))
      |> Enum.take(batch_size)
      |> Enum.each(&dispatch_operation(&1, system_opts, config))

      :ok
    end
  end

  defp dispatch_operation(operation, system_opts, config) do
    with {:ok, processing_operation} <- mark_processing(operation, system_opts) do
      with {:ok, bot} <- fetch_bot(processing_operation, system_opts),
           {:ok, reconcile_result} <- reconcile(bot, processing_operation),
           :ok <- apply_reconcile_result(processing_operation, reconcile_result, system_opts),
           {:ok, _operation} <-
             mark_dispatched(processing_operation, reconcile_result, system_opts) do
        :ok
      else
        {:error, reason} ->
          handle_failure(processing_operation, reason, system_opts, config)
          :error
      end
    end
  end

  defp mark_processing(operation, system_opts) do
    ControlPlane.update_bot_reconcile_operation(
      operation,
      %{
        status: "processing",
        attempt_count: operation.attempt_count + 1,
        last_error: nil,
        next_attempt_at: nil
      },
      system_opts
    )
  end

  defp mark_dispatched(operation, reconcile_result, system_opts) do
    ControlPlane.update_bot_reconcile_operation(
      operation,
      %{
        status: "dispatched",
        dispatched_at: DateTime.utc_now(),
        last_error: nil,
        next_attempt_at: nil,
        payload:
          merge_payload(operation.payload, Map.get(reconcile_result, :operation_payload, %{}))
      },
      system_opts
    )
  end

  defp handle_failure(operation, reason, system_opts, config) do
    if operation.attempt_count >= config.max_attempts do
      mark_failed(operation, reason, system_opts)
    else
      requeue(operation, reason, system_opts, config)
    end
  end

  defp mark_failed(operation, reason, system_opts) do
    _ =
      ControlPlane.update_bot_reconcile_operation(
        operation,
        %{
          status: "failed",
          last_error: inspect(reason),
          next_attempt_at: nil
        },
        system_opts
      )

    maybe_mark_bot_error(operation, system_opts)
    :ok
  end

  defp requeue(operation, reason, system_opts, config) do
    _ =
      ControlPlane.update_bot_reconcile_operation(
        operation,
        %{
          status: "pending",
          last_error: inspect(reason),
          next_attempt_at: DateTime.add(DateTime.utc_now(), config.retry_backoff_ms, :millisecond)
        },
        system_opts
      )

    :ok
  end

  defp maybe_mark_bot_error(%{bot_id: nil}, _system_opts), do: :ok

  defp maybe_mark_bot_error(%{bot_id: bot_id}, system_opts) do
    case ControlPlane.get_bot(bot_id, system_opts) do
      {:ok, bot} ->
        _ =
          ControlPlane.report_bot_status(
            bot,
            %{
              target_status: :error,
              status_reason: "reconcile_failed",
              status_metadata: %{"source" => "dispatcher"},
              last_observed_at: DateTime.utc_now()
            },
            system_opts
          )

        :ok

      _ ->
        :ok
    end
  end

  defp fetch_bot(%{bot_id: bot_id, payload: payload}, system_opts) when not is_nil(bot_id) do
    case ControlPlane.get_bot(bot_id, system_opts) do
      {:ok, bot} -> {:ok, bot}
      _ -> bot_from_payload(payload)
    end
  end

  defp fetch_bot(%{payload: payload}, _system_opts), do: bot_from_payload(payload)

  defp bot_from_payload(%{"bot" => bot_payload}) when is_map(bot_payload) do
    {:ok,
     struct(Threadr.ControlPlane.Bot, %{
       id: bot_payload["id"],
       tenant_id: bot_payload["tenant_id"],
       name: bot_payload["name"],
       platform: bot_payload["platform"],
       desired_state: bot_payload["desired_state"],
       status: bot_payload["status"],
       channels: bot_payload["channels"] || [],
       settings: bot_payload["settings"] || %{},
       deployment_name: bot_payload["deployment_name"]
     })}
  end

  defp bot_from_payload(_payload), do: {:error, :missing_bot_payload}

  defp reconcile(bot, operation) do
    case Application.fetch_env!(:threadr, :bot_reconciler).reconcile(bot, operation) do
      :ok -> {:ok, %{}}
      {:ok, result} when is_map(result) -> {:ok, result}
      {:error, _reason} = error -> error
    end
  end

  defp eligible_operation?(%{next_attempt_at: nil}, _now), do: true

  defp eligible_operation?(%{next_attempt_at: %DateTime{} = next_attempt_at}, now),
    do: DateTime.compare(next_attempt_at, now) != :gt

  defp apply_reconcile_result(%{bot_id: nil}, _reconcile_result, _system_opts), do: :ok

  defp apply_reconcile_result(operation, reconcile_result, system_opts) do
    with :ok <- persist_controller_contract(reconcile_result, system_opts),
         :ok <- apply_bot_updates(operation, reconcile_result, system_opts) do
      :ok
    end
  end

  defp apply_bot_updates(operation, reconcile_result, system_opts) do
    case Map.get(reconcile_result, :bot_updates, %{}) do
      bot_updates when map_size(bot_updates) == 0 ->
        :ok

      bot_updates ->
        case ControlPlane.get_bot(operation.bot_id, system_opts) do
          {:ok, bot} ->
            case ControlPlane.update_bot(bot, bot_updates, system_opts) do
              {:ok, _bot} -> :ok
              {:error, reason} -> {:error, reason}
            end

          _ ->
            :ok
        end
    end
  end

  defp persist_controller_contract(reconcile_result, system_opts) do
    case Map.get(reconcile_result, :controller_contract) do
      nil ->
        :ok

      contract_attrs ->
        case ControlPlane.upsert_bot_controller_contract(contract_attrs, system_opts) do
          {:ok, _contract} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp merge_payload(existing, updates) when is_map(existing) and is_map(updates) do
    Map.merge(stringify_map(existing), stringify_map(updates))
  end

  defp merge_payload(existing, _updates), do: existing

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp stringify_map(other), do: other
end
