defmodule Mix.Tasks.Threadr.Smoke.Discord do
  @shortdoc "Waits for a real Discord gateway READY event from the ingest runtime"
  @moduledoc """
  Boots the app with the configured Discord ingest runtime and waits for a real
  Discord gateway `READY` event.

  Required environment:

      THREADR_INGEST_ENABLED=true
      THREADR_PLATFORM=discord
      THREADR_TENANT_SUBJECT=...
      THREADR_CHANNELS='["123456789"]'
      THREADR_DISCORD_TOKEN=...

  Example:

      THREADR_INGEST_ENABLED=true \\
      THREADR_PLATFORM=discord \\
      THREADR_TENANT_SUBJECT=threadr-smoke \\
      THREADR_CHANNELS='["123456789"]' \\
      THREADR_DISCORD_TOKEN=... \\
      mix threadr.smoke.discord
  """

  use Mix.Task

  @switches [timeout_ms: :integer]
  @default_timeout_ms 30_000

  @impl Mix.Task
  def run(args) do
    {opts, _argv, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    handler_id = "threadr-discord-smoke-#{System.unique_integer([:positive])}"

    Application.ensure_all_started(:telemetry)
    attach_telemetry!(handler_id)

    try do
      Mix.Task.run("app.start")
      assert_discord_runtime_config!()
      assert_runtime_started!()

      metadata = await_ready!(timeout_ms)

      Mix.shell().info("Discord ingest smoke test passed")
      Mix.shell().info("tenant_subject: #{metadata[:tenant_subject_name]}")
      Mix.shell().info("bot_id: #{metadata[:bot_id] || "n/a"}")
      Mix.shell().info("guild_count: #{metadata[:guild_count] || 0}")
      Mix.shell().info("shard: #{format_shard(metadata[:shard])}")
    after
      :telemetry.detach(handler_id)
    end
  end

  defp attach_telemetry!(handler_id) do
    events = [
      [:threadr, :ingest, :runtime, :ready],
      [:threadr, :ingest, :runtime, :error],
      [:threadr, :ingest, :runtime, :disconnected]
    ]

    :ok =
      :telemetry.attach_many(
        handler_id,
        events,
        &__MODULE__.handle_telemetry_event/4,
        self()
      )
  end

  def handle_telemetry_event(event, _measurements, metadata, pid) do
    send(pid, {:ingest_runtime_event, event, metadata})
  end

  defp assert_discord_runtime_config! do
    config = Threadr.Ingest.config()

    cond do
      not Threadr.Ingest.enabled?(config) ->
        Mix.raise("Discord ingest smoke requires THREADR_INGEST_ENABLED=true")

      Threadr.Ingest.platform(config) != "discord" ->
        Mix.raise("Discord ingest smoke requires THREADR_PLATFORM=discord")

      true ->
        :ok
    end
  end

  defp assert_runtime_started! do
    if Process.whereis(Threadr.Ingest.Discord.Bot) do
      :ok
    else
      Mix.raise(
        "Discord ingest runtime did not start; check THREADR_DISCORD_TOKEN and runtime config"
      )
    end
  end

  defp await_ready!(timeout_ms) do
    receive do
      {:ingest_runtime_event, [:threadr, :ingest, :runtime, :ready],
       %{platform: "discord"} = metadata} ->
        metadata

      {:ingest_runtime_event, [:threadr, :ingest, :runtime, :error],
       %{platform: "discord"} = metadata} ->
        Mix.raise("Discord ingest runtime reported an error: #{inspect(metadata)}")

      {:ingest_runtime_event, [:threadr, :ingest, :runtime, :disconnected],
       %{platform: "discord"} = metadata} ->
        Mix.raise("Discord ingest runtime disconnected before ready: #{inspect(metadata)}")
    after
      timeout_ms ->
        Mix.raise("timed out waiting for Discord READY event after #{timeout_ms}ms")
    end
  end

  defp format_shard(nil), do: "none"
  defp format_shard({id, total}), do: "#{id}/#{total}"
end
