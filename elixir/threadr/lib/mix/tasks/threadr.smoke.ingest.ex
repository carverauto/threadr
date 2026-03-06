defmodule Mix.Tasks.Threadr.Smoke.Ingest do
  @shortdoc "Publishes a tenant-scoped chat message and waits for Broadway persistence"
  @moduledoc """
  Verifies the local tenant-scoped JetStream and Broadway ingest path end to end.

  Examples:

      mix threadr.smoke.ingest
      mix threadr.smoke.ingest --tenant-name "Acme Threat Intel" --mentions bob,carol
  """

  use Mix.Task

  alias Threadr.Messaging.Smoke

  @switches [
    tenant_name: :string,
    tenant_slug: :string,
    tenant_schema: :string,
    tenant_subject: :string,
    platform: :string,
    channel: :string,
    actor: :string,
    body: :string,
    mentions: :string,
    timeout_ms: :integer,
    poll_interval_ms: :integer
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _argv, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    Mix.Task.run("threadr.nats.setup")

    pipeline_pid = ensure_pipeline_started()

    report =
      opts
      |> to_smoke_opts()
      |> Smoke.run()

    print_report(report)

    if pipeline_pid do
      GenServer.stop(pipeline_pid)
    end
  end

  defp ensure_pipeline_started do
    case Process.whereis(Threadr.Messaging.Pipeline) do
      nil ->
        {:ok, pid} = Threadr.Messaging.Pipeline.start_link()
        pid

      _pid ->
        nil
    end
  end

  defp to_smoke_opts(opts) do
    [
      tenant_name: opts[:tenant_name],
      tenant_slug: opts[:tenant_slug],
      tenant_schema: opts[:tenant_schema],
      tenant_subject_name: opts[:tenant_subject],
      platform: opts[:platform],
      channel: opts[:channel],
      actor: opts[:actor],
      body: opts[:body],
      mentions: opts[:mentions],
      timeout_ms: opts[:timeout_ms],
      poll_interval_ms: opts[:poll_interval_ms]
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp print_report(report) do
    result = report.result

    Mix.shell().info("JetStream/Broadway smoke test passed")
    Mix.shell().info("tenant: #{report.tenant_subject_name} (#{report.tenant_schema})")
    Mix.shell().info("external_id: #{report.external_id}")
    Mix.shell().info("elapsed_ms: #{report.elapsed_ms}")
    Mix.shell().info("message_id: #{result.message.id}")
    Mix.shell().info("mentions: #{result.mention_count}")
    Mix.shell().info("relationships: #{result.relationship_count}")
  end
end
