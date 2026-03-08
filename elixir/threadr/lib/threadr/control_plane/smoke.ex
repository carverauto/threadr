defmodule Threadr.ControlPlane.Smoke do
  @moduledoc """
  Helpers for local control-plane smoke verification flows.
  """

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Service

  @default_bot_name "irc-main"
  @default_platform "irc"
  @default_channel "#threadr"
  @default_contract_timeout_ms 5_000

  def provision_bot_contract!(opts \\ []) do
    tenant = create_tenant!(opts)
    bot = create_or_reuse_bot!(tenant, opts)
    drain_bot_operations!()

    contract =
      await_bot_contract!(
        tenant,
        bot.id,
        Keyword.get(opts, :timeout_ms, @default_contract_timeout_ms)
      )

    bot = reload_bot!(bot.id)

    %{
      tenant: tenant,
      bot: bot,
      contract: contract
    }
  end

  def default_tenant_name do
    "Threadr Operator Smoke #{System.unique_integer([:positive])}"
  end

  def default_tenant_subject do
    "threadr-operator-smoke-#{System.unique_integer([:positive])}"
  end

  def create_tenant!(opts) do
    attrs =
      %{
        name: Keyword.get(opts, :tenant_name, default_tenant_name()),
        subject_name: Keyword.get(opts, :tenant_subject, default_tenant_subject())
      }
      |> Service.normalize_tenant_attrs()

    case fetch_tenant_by_subject(attrs.subject_name) do
      {:ok, tenant} ->
        tenant

      {:error, _reason} ->
        case Service.create_tenant(attrs) do
          {:ok, tenant} ->
            tenant

          {:error, reason} ->
            case fetch_tenant_by_subject(attrs.subject_name) do
              {:ok, tenant} ->
                tenant

              {:error, _lookup_reason} ->
                raise "failed to create smoke tenant: #{inspect(reason)}"
            end
        end
    end
  end

  def create_or_reuse_bot!(tenant, opts) do
    name = Keyword.get(opts, :bot_name, @default_bot_name)
    platform = Keyword.get(opts, :platform, @default_platform)

    existing_bot =
      ControlPlane.list_bots(
        context: %{system: true},
        query: [filter: [tenant_id: tenant.id], sort: [inserted_at: :desc]]
      )
      |> case do
        {:ok, bots} -> Enum.find(bots, &(&1.name == name))
        _ -> nil
      end

    case existing_bot do
      nil ->
        case Service.create_bot(%{
               tenant_id: tenant.id,
               name: name,
               platform: platform,
               channels: [Keyword.get(opts, :channel, @default_channel)],
               settings: smoke_bot_settings(platform, name)
             }) do
          {:ok, bot} ->
            bot

          {:error, reason} ->
            case fetch_existing_bot(tenant.id, name) do
              {:ok, bot} -> bot
              :error -> raise "failed to create smoke bot: #{inspect(reason)}"
            end
        end

      bot ->
        bot
    end
  end

  defp fetch_tenant_by_subject(subject_name) do
    ControlPlane.get_tenant_by_subject_name(subject_name, context: %{system: true})
  end

  defp fetch_existing_bot(tenant_id, name) do
    ControlPlane.list_bots(
      context: %{system: true},
      query: [filter: [tenant_id: tenant_id], sort: [inserted_at: :desc]]
    )
    |> case do
      {:ok, bots} ->
        case Enum.find(bots, &(&1.name == name)) do
          nil -> :error
          bot -> {:ok, bot}
        end

      _ ->
        :error
    end
  end

  defp smoke_bot_settings("irc", bot_name) do
    %{
      "env" => %{
        "THREADR_IRC_HOST" => "irc.example.test",
        "THREADR_IRC_NICK" => "#{bot_name}-smoke"
      }
    }
  end

  defp smoke_bot_settings("discord", _bot_name) do
    %{
      "env" => %{
        "THREADR_DISCORD_TOKEN" => "discord-smoke-token"
      }
    }
  end

  defp smoke_bot_settings(_platform, _bot_name), do: %{}

  def drain_bot_operations! do
    case Threadr.ControlPlane.BotOperationDispatcher.process_pending_once() do
      :ok -> :ok
      other -> raise "failed to drain bot operations: #{inspect(other)}"
    end
  end

  def reload_bot!(bot_id) do
    case ControlPlane.get_bot(bot_id, context: %{system: true}) do
      {:ok, bot} -> bot
      {:error, reason} -> raise "failed to reload smoke bot: #{inspect(reason)}"
    end
  end

  def await_bot_contract!(tenant, bot_id, timeout_ms \\ @default_contract_timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await_bot_contract(tenant, bot_id, deadline)
  end

  defp do_await_bot_contract(tenant, bot_id, deadline) do
    case Service.get_bot_controller_contract_for_controller(tenant.subject_name, bot_id) do
      {:ok, contract} ->
        contract

      {:error, reason} ->
        if System.monotonic_time(:millisecond) >= deadline do
          raise "timed out waiting for bot contract: #{inspect(reason)}"
        end

        Process.sleep(100)
        do_await_bot_contract(tenant, bot_id, deadline)
    end
  end
end
