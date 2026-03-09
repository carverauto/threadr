defmodule Threadr.TenantData.ConversationSummaryDispatcher do
  @moduledoc """
  Supervised worker that periodically refreshes reconstructed conversation summaries.
  """

  use GenServer

  require Logger

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Analysis
  alias Threadr.TenantData.ConversationSummarizer

  @name __MODULE__
  @required_tenant_migration_version 20_260_308_195_500

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  def process_pending_once do
    config = dispatcher_config()
    dispatch_pending(config.batch_size)
  end

  def trigger do
    if dispatcher_config().enabled and Process.whereis(@name) do
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
  def handle_cast(:trigger, state) do
    if state.enabled do
      dispatch_pending(state.batch_size)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:process_pending, state) do
    dispatch_pending(state.batch_size)
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
      enabled: Keyword.get(config, :enabled, false),
      poll_interval_ms: Keyword.get(config, :poll_interval_ms, 60_000),
      batch_size: Keyword.get(config, :batch_size, 10)
    }
  end

  defp dispatch_pending(batch_size) when is_integer(batch_size) and batch_size > 0 do
    case ControlPlane.list_tenants(context: %{system: true}) do
      {:ok, tenants} ->
        tenants
        |> Enum.filter(&eligible_tenant?/1)
        |> Enum.sort_by(& &1.schema_name)
        |> Enum.reduce_while(batch_size, fn tenant, remaining ->
          if remaining <= 0 do
            {:halt, remaining}
          else
            {:cont, remaining - dispatch_tenant(tenant, remaining)}
          end
        end)

        :ok

      {:error, reason} ->
        Logger.warning("conversation summary dispatch failed: #{inspect(reason)}")
        :error
    end
  end

  defp dispatch_tenant(tenant, remaining) do
    conversation_ids = pending_conversation_ids(tenant, remaining)

    if conversation_ids == [] do
      0
    else
      case Analysis.generation_runtime_opts_for_tenant_subject(tenant.subject_name) do
        {:ok, runtime_opts} ->
          Enum.reduce(conversation_ids, 0, fn conversation_id, count ->
            case ConversationSummarizer.summarize_conversation(
                   conversation_id,
                   tenant.schema_name,
                   runtime_opts
                 ) do
              {:ok, _conversation} ->
                count + 1

              {:error, reason} ->
                Logger.warning(
                  "conversation summary refresh failed for #{tenant.subject_name}:#{conversation_id}: #{inspect(reason)}"
                )

                count
            end
          end)

        {:error, reason} ->
          Logger.warning(
            "conversation summary runtime resolution failed for #{tenant.subject_name}: #{inspect(reason)}"
          )

          0
      end
    end
  end

  defp eligible_tenant?(tenant) do
    tenant.status == "active" and tenant.tenant_migration_status == "succeeded" and
      is_integer(tenant.tenant_migration_version) and
      tenant.tenant_migration_version >= @required_tenant_migration_version and
      is_binary(tenant.schema_name) and is_binary(tenant.subject_name)
  end

  defp pending_conversation_ids(tenant, remaining) do
    ConversationSummarizer.pending_conversation_ids(tenant.schema_name, remaining)
  rescue
    error in Postgrex.Error ->
      Logger.warning(
        "conversation summary skipped for #{tenant.subject_name}: schema not ready (#{Exception.message(error)})"
      )

      []
  end
end
