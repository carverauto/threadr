defmodule Threadr.ControlPlane.BotStatusObserver do
  @moduledoc """
  Periodically reads Deployment status from Kubernetes and updates bot health.
  """

  use GenServer

  alias Threadr.ControlPlane

  @name __MODULE__

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  def observe_once do
    config = observer_config()
    observe_bots(config.batch_size, config)
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
    state = observer_config()
    maybe_schedule(state)
    {:ok, state}
  end

  @impl true
  def handle_cast(:trigger, state) do
    observe_bots(state.batch_size, state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:observe_bots, state) do
    observe_bots(state.batch_size, state)
    maybe_schedule(state)
    {:noreply, state}
  end

  defp maybe_schedule(%{enabled: true, poll_interval_ms: poll_interval_ms}) do
    Process.send_after(self(), :observe_bots, poll_interval_ms)
  end

  defp maybe_schedule(_state), do: :ok

  defp observer_config do
    config = Application.get_env(:threadr, __MODULE__, [])

    %{
      enabled: Keyword.get(config, :enabled, false),
      poll_interval_ms: Keyword.get(config, :poll_interval_ms, 10_000),
      batch_size: Keyword.get(config, :batch_size, 50)
    }
  end

  defp observe_bots(batch_size, _config) do
    system_opts = [context: %{system: true}]

    with {:ok, bots} <-
           ControlPlane.list_bots(
             Keyword.merge(system_opts,
               query: [sort: [updated_at: :asc], limit: batch_size * 5]
             )
           ) do
      bots
      |> Enum.filter(&eligible_bot?/1)
      |> Enum.take(batch_size)
      |> Enum.each(&observe_bot(&1, system_opts))

      :ok
    end
  end

  defp eligible_bot?(bot) do
    is_binary(bot.deployment_name) and bot.deployment_name != "" and
      bot.desired_state != "deleted"
  end

  defp observe_bot(bot, system_opts) do
    with {:ok, tenant} <- ControlPlane.get_tenant(bot.tenant_id, system_opts),
         {:ok, deployment} <-
           kubernetes_client().get_deployment(tenant.kubernetes_namespace, bot.deployment_name),
         observed_status <- deployment_status(bot, deployment) do
      maybe_update_status(bot, observed_status, system_opts)
    else
      {:error, _reason} ->
        :ok
    end
  end

  defp maybe_update_status(bot, observed_status, system_opts) do
    update_attrs = %{
      status_reason: status_reason(bot, observed_status),
      status_metadata: %{"source" => "kubernetes_poll"},
      last_observed_at: DateTime.utc_now()
    }

    if observation_unchanged?(bot, update_attrs) do
      :ok
    else
      case ControlPlane.report_bot_status(
             bot,
             Map.put(update_attrs, :target_status, observed_status),
             system_opts
           ) do
        {:ok, _bot} -> :ok
        {:error, _reason} -> :ok
      end
    end
  end

  defp observation_unchanged?(bot, update_attrs) do
    bot.status_reason == update_attrs.status_reason and
      bot.status_metadata == update_attrs.status_metadata
  end

  defp deployment_status(%{desired_state: "stopped"}, nil), do: :stopped
  defp deployment_status(_bot, nil), do: :error

  defp deployment_status(bot, deployment) do
    desired_replicas = deployment |> get_in(["spec", "replicas"]) |> to_integer(1)
    available_replicas = deployment |> get_in(["status", "availableReplicas"]) |> to_integer()
    ready_replicas = deployment |> get_in(["status", "readyReplicas"]) |> to_integer()
    updated_replicas = deployment |> get_in(["status", "updatedReplicas"]) |> to_integer()
    unavailable_replicas = deployment |> get_in(["status", "unavailableReplicas"]) |> to_integer()
    generation = deployment |> get_in(["metadata", "generation"]) |> to_integer()

    observed_generation =
      deployment
      |> get_in(["status", "observedGeneration"])
      |> to_integer()

    cond do
      get_in(deployment, ["metadata", "deletionTimestamp"]) ->
        :deleting

      desired_replicas == 0 and ready_replicas == 0 and available_replicas == 0 ->
        :stopped

      desired_replicas == 0 ->
        :reconciling

      observed_generation < generation ->
        :reconciling

      ready_replicas >= desired_replicas and available_replicas >= desired_replicas and
          updated_replicas >= desired_replicas ->
        :running

      progress_deadline_exceeded?(deployment) ->
        :degraded

      unavailable_replicas > 0 or ready_replicas > 0 or available_replicas > 0 ->
        :degraded

      bot.desired_state == "stopped" ->
        :reconciling

      true ->
        :reconciling
    end
  end

  defp status_reason(_bot, :running), do: "deployment_ready"
  defp status_reason(_bot, :stopped), do: "deployment_scaled_to_zero"
  defp status_reason(_bot, :deleting), do: "deployment_deleting"
  defp status_reason(_bot, :degraded), do: "deployment_not_fully_available"
  defp status_reason(_bot, :error), do: "deployment_missing"
  defp status_reason(%{desired_state: "stopped"}, :reconciling), do: "waiting_for_scale_down"
  defp status_reason(_bot, :reconciling), do: "waiting_for_rollout"
  defp status_reason(_bot, _status), do: nil

  defp progress_deadline_exceeded?(deployment) do
    deployment
    |> get_in(["status", "conditions"])
    |> List.wrap()
    |> Enum.any?(fn condition ->
      condition["type"] == "Progressing" and condition["reason"] == "ProgressDeadlineExceeded"
    end)
  end

  defp to_integer(value), do: to_integer(value, 0)

  defp to_integer(nil, default), do: default
  defp to_integer(value, _default) when is_integer(value), do: value

  defp to_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, _rest} -> integer
      :error -> default
    end
  end

  defp to_integer(_value, default), do: default

  defp kubernetes_client do
    Application.fetch_env!(:threadr, :kubernetes_client)
  end
end
