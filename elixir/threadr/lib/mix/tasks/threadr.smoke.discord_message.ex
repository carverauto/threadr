defmodule Mix.Tasks.Threadr.Smoke.DiscordMessage do
  @shortdoc "Posts or waits for a Discord message and verifies Broadway persistence"
  @moduledoc """
  Boots the app with Discord ingest and Broadway enabled, then waits for the
  next Discord message in the target channel to persist into the tenant schema.
  It can optionally post its own smoke message using the configured bot token.

  Required environment:

      THREADR_INGEST_ENABLED=true
      THREADR_PLATFORM=discord
      THREADR_TENANT_SUBJECT=...
      THREADR_CHANNELS='[\"123456789\"]'
      THREADR_DISCORD_TOKEN=...

  Example:

      THREADR_INGEST_ENABLED=true \\
      THREADR_PLATFORM=discord \\
      THREADR_BROADWAY_ENABLED=true \\
      THREADR_TENANT_SUBJECT=threadr-smoke-discord \\
      THREADR_CHANNELS='[\"1218931466357182486\"]' \\
      THREADR_DISCORD_TOKEN=... \\
      mix threadr.smoke.discord_message --channel 1218931466357182486 --post-test-message
  """

  use Mix.Task

  import Ash.Expr
  require Ash.Query

  alias Gnat.Jetstream.API.Consumer
  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Service
  alias Threadr.Messaging.{Pipeline, Topology}
  alias Threadr.TenantData.Message

  @switches [
    tenant_name: :string,
    tenant_slug: :string,
    tenant_schema: :string,
    tenant_subject: :string,
    channel: :string,
    post_test_message: :boolean,
    message_body: :string,
    timeout_ms: :integer,
    poll_interval_ms: :integer
  ]

  @default_timeout_ms 120_000
  @default_poll_interval_ms 500
  @default_tenant_name "Threadr Discord Smoke"
  @smoke_pipeline_name Threadr.Messaging.DiscordSmokePipeline

  @impl Mix.Task
  def run(args) do
    {opts, _argv, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    disable_default_pipeline!()
    Mix.Task.run("app.start")
    Mix.Task.run("threadr.nats.setup")

    assert_discord_runtime_config!()
    wait_for_runtime_ready!(Keyword.get(opts, :timeout_ms, @default_timeout_ms))

    tenant = ensure_tenant!(opts)
    channel = normalize_required_string(opts[:channel] || configured_channel!(), :channel)
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    poll_interval_ms = Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms)

    {message, message_body} =
      with_isolated_pipeline!(tenant.subject_name, fn ->
        started_at = DateTime.utc_now()
        message_body = maybe_post_test_message(opts, channel)

        Mix.shell().info("Discord message smoke is ready")
        Mix.shell().info("tenant_subject: #{tenant.subject_name}")
        Mix.shell().info("tenant_schema: #{tenant.schema_name}")
        Mix.shell().info("channel: #{channel}")

        if message_body do
          Mix.shell().info("posted smoke message: #{message_body}")
        else
          Mix.shell().info("waiting for the next Discord message to persist...")
        end

        message =
          await_message!(
            tenant.schema_name,
            channel,
            started_at,
            timeout_ms,
            poll_interval_ms
          )

        {message, message_body}
      end)

    Mix.shell().info("Discord message smoke test passed")
    Mix.shell().info("message_id: #{message.id}")
    Mix.shell().info("external_id: #{message.external_id}")
    Mix.shell().info("observed_at: #{message.observed_at}")
    Mix.shell().info("body: #{message.body}")

    if message_body do
      Mix.shell().info("expected_body: #{message_body}")
    end
  end

  defp assert_discord_runtime_config! do
    config = Threadr.Ingest.config()

    cond do
      not Threadr.Ingest.enabled?(config) ->
        Mix.raise("Discord message smoke requires THREADR_INGEST_ENABLED=true")

      Threadr.Ingest.platform(config) != "discord" ->
        Mix.raise("Discord message smoke requires THREADR_PLATFORM=discord")

      Process.whereis(Threadr.Ingest.Discord.Bot) == nil ->
        Mix.raise("Discord ingest runtime did not start")

      true ->
        :ok
    end
  end

  defp configured_channel! do
    case Threadr.Ingest.config()[:channels] do
      [channel | _rest] ->
        channel

      _ ->
        Mix.raise(
          "Discord message smoke requires --channel or THREADR_CHANNELS with at least one channel"
        )
    end
  end

  defp disable_default_pipeline! do
    config = Application.fetch_env!(:threadr, Threadr.Messaging.Topology)

    Application.put_env(
      :threadr,
      Threadr.Messaging.Topology,
      Keyword.put(config, :pipeline_enabled, false)
    )
  end

  defp with_isolated_pipeline!(tenant_subject_name, fun) when is_function(fun, 0) do
    consumer_name = "THREADR_DISCORD_SMOKE_#{System.unique_integer([:positive])}"
    previous_config = Application.fetch_env!(:threadr, Threadr.Messaging.Topology)
    updated_config = Keyword.put(previous_config, :consumer_name, consumer_name)
    Application.put_env(:threadr, Threadr.Messaging.Topology, updated_config)

    create_smoke_consumer!(consumer_name, tenant_subject_name)
    {:ok, pid} = Pipeline.start_link(name: @smoke_pipeline_name, consumer_name: consumer_name)

    try do
      fun.()
    after
      if Process.alive?(pid), do: Process.exit(pid, :normal)
      :ok = Consumer.delete(Topology.connection_name(), Topology.stream_name(), consumer_name)
      Application.put_env(:threadr, Threadr.Messaging.Topology, previous_config)
    end
  end

  defp create_smoke_consumer!(consumer_name, tenant_subject_name) do
    spec = %Consumer{
      stream_name: Topology.stream_name(),
      durable_name: consumer_name,
      ack_policy: :explicit,
      replay_policy: :instant,
      deliver_policy: :new,
      filter_subject: "threadr.tenants.#{tenant_subject_name}.>"
    }

    case Consumer.create(Topology.connection_name(), spec) do
      {:ok, _consumer} ->
        :ok

      {:error, reason} ->
        Mix.raise("failed to create Discord smoke JetStream consumer: #{inspect(reason)}")
    end
  end

  defp maybe_post_test_message(opts, channel) do
    if Keyword.get(opts, :post_test_message, false) do
      message_body =
        opts[:message_body] ||
          "threadr discord smoke #{System.system_time(:millisecond)}"

      post_test_message!(channel, message_body)
      message_body
    else
      nil
    end
  end

  defp wait_for_runtime_ready!(timeout_ms) do
    handler_id = "threadr-discord-message-smoke-#{System.unique_integer([:positive])}"
    Application.ensure_all_started(:telemetry)

    :ok =
      :telemetry.attach_many(
        handler_id,
        [
          [:threadr, :ingest, :runtime, :ready],
          [:threadr, :ingest, :runtime, :error],
          [:threadr, :ingest, :runtime, :disconnected]
        ],
        &__MODULE__.handle_telemetry_event/4,
        self()
      )

    try do
      receive do
        {:discord_message_smoke_event, [:threadr, :ingest, :runtime, :ready],
         %{platform: "discord"}} ->
          :ok

        {:discord_message_smoke_event, [:threadr, :ingest, :runtime, :error], metadata} ->
          Mix.raise("Discord ingest runtime reported an error: #{inspect(metadata)}")

        {:discord_message_smoke_event, [:threadr, :ingest, :runtime, :disconnected], metadata} ->
          Mix.raise("Discord ingest runtime disconnected before ready: #{inspect(metadata)}")
      after
        timeout_ms ->
          Mix.raise("timed out waiting for Discord runtime readiness after #{timeout_ms}ms")
      end
    after
      :telemetry.detach(handler_id)
    end
  end

  def handle_telemetry_event(event, _measurements, metadata, pid) do
    send(pid, {:discord_message_smoke_event, event, metadata})
  end

  defp ensure_tenant!(opts) do
    tenant_subject_name =
      normalize_optional_string(Keyword.get(opts, :tenant_subject)) ||
        normalize_optional_string(Threadr.Ingest.config()[:tenant_subject_name])

    tenant_name =
      case Keyword.fetch(opts, :tenant_name) do
        {:ok, name} ->
          normalize_required_string(name, :tenant_name)

        :error when is_binary(tenant_subject_name) ->
          tenant_subject_name
          |> String.replace("-", " ")
          |> String.split(" ", trim: true)
          |> Enum.map_join(" ", &String.capitalize/1)

        :error ->
          @default_tenant_name
      end
      |> normalize_required_string(:tenant_name)

    normalized_attrs =
      %{name: tenant_name}
      |> maybe_put(:slug, normalize_optional_string(Keyword.get(opts, :tenant_slug)))
      |> maybe_put(:schema_name, normalize_optional_string(Keyword.get(opts, :tenant_schema)))
      |> maybe_put(:subject_name, tenant_subject_name)
      |> Service.normalize_tenant_attrs()

    case ControlPlane.get_tenant_by_subject_name(
           normalized_attrs.subject_name,
           context: %{system: true}
         ) do
      {:ok, tenant} when not is_nil(tenant) ->
        tenant

      _ ->
        case Service.create_tenant(normalized_attrs) do
          {:ok, tenant} -> tenant
          {:error, reason} -> Mix.raise("failed to provision smoke tenant: #{inspect(reason)}")
        end
    end
  end

  defp await_message!(tenant_schema, channel, started_at, timeout_ms, poll_interval_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await_message(tenant_schema, channel, started_at, deadline, poll_interval_ms)
  end

  defp do_await_message(tenant_schema, channel, started_at, deadline, poll_interval_ms) do
    query =
      Message
      |> Ash.Query.filter(
        expr(
          channel.name == ^channel and
            channel.platform == "discord" and
            observed_at >= ^started_at
        )
      )
      |> Ash.Query.sort(observed_at: :desc)
      |> Ash.Query.limit(1)
      |> Ash.Query.load([:channel, :actor])

    case Ash.read(query, tenant: tenant_schema) do
      {:ok, [message]} ->
        message

      {:ok, []} ->
        if System.monotonic_time(:millisecond) >= deadline do
          Mix.raise(
            "timed out waiting for a Discord message in #{channel} for tenant schema #{tenant_schema}"
          )
        end

        Process.sleep(poll_interval_ms)
        do_await_message(tenant_schema, channel, started_at, deadline, poll_interval_ms)

      {:error, reason} ->
        Mix.raise("failed to query persisted Discord messages: #{inspect(reason)}")
    end
  end

  defp maybe_put(attrs, _key, nil), do: attrs
  defp maybe_put(attrs, key, value), do: Map.put(attrs, key, value)

  defp post_test_message!(channel, body) do
    token =
      Threadr.Ingest.config()
      |> Keyword.fetch!(:discord)
      |> Map.get(:token)

    if is_nil(token) or String.trim(token) == "" do
      Mix.raise("Discord message smoke requires THREADR_DISCORD_TOKEN to post a test message")
    end

    response =
      Req.post!(
        "https://discord.com/api/v10/channels/#{channel}/messages",
        headers: [{"authorization", "Bot #{token}"}],
        json: %{content: body}
      )

    if response.status not in 200..299 do
      Mix.raise(
        "failed to post Discord smoke message: status=#{response.status} body=#{inspect(response.body)}"
      )
    end
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_required_string(value, key) when is_binary(value) do
    case normalize_optional_string(value) do
      nil -> Mix.raise("expected #{inspect(key)} to be a non-empty string")
      trimmed -> trimmed
    end
  end
end
