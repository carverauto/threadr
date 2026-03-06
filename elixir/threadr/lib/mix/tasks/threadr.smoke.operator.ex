defmodule Mix.Tasks.Threadr.Smoke.Operator do
  @shortdoc "Runs the cross-system Phoenix and operator smoke test"
  @moduledoc """
  Provisions a real control-plane `ThreadrBot` contract, boots a temporary
  Phoenix server, runs the Go operator smoke binary against it, and verifies
  the controller callback updated bot state for the current generation.

  Examples:

      mix threadr.smoke.operator
      mix threadr.smoke.operator --tenant-subject threadr-smoke --bot-name irc-main
  """

  use Mix.Task

  alias Threadr.ControlPlane.Smoke

  @switches [
    tenant_name: :string,
    tenant_subject: :string,
    bot_name: :string,
    platform: :string,
    channel: :string,
    port: :integer,
    timeout_ms: :integer
  ]

  @default_timeout_ms 30_000
  @control_plane_token "threadr-smoke-token"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    port = Keyword.get(opts, :port, find_available_port!())
    token = System.get_env("THREADR_CONTROL_PLANE_TOKEN") || @control_plane_token

    %{tenant: tenant, bot: bot, contract: contract} =
      Smoke.provision_bot_contract!(Keyword.put(opts, :timeout_ms, timeout_ms))

    server_pid = start_server!(port, token)

    try do
      wait_for_http!("127.0.0.1", port, timeout_ms)

      operator_output =
        run_operator_smoke!(
          "http://127.0.0.1:#{port}",
          token,
          contract.namespace,
          contract.deployment_name,
          timeout_ms
        )

      bot =
        await_controller_callback!(
          bot.id,
          contract.generation,
          contract.deployment_name,
          timeout_ms
        )

      Mix.shell().info("Phoenix/operator smoke test passed")
      Mix.shell().info("tenant_subject: #{tenant.subject_name}")
      Mix.shell().info("bot_id: #{bot.id}")
      Mix.shell().info("deployment_name: #{contract.deployment_name}")
      Mix.shell().info("bot_status: #{bot.status}")
      Mix.shell().info("status_reason: #{bot.status_reason}")
      Mix.shell().info("observed_generation: #{bot.observed_generation}")
      Mix.shell().info("operator_result:\n#{summarize_operator_output(operator_output)}")
    after
      stop_server(server_pid)
    end
  end

  defp run_operator_smoke!(base_url, token, namespace, deployment_name, timeout_ms) do
    operator_dir = Path.expand("../../k8s/operators/ircbot-operator", File.cwd!())

    env = [
      {"THREADR_CONTROL_PLANE_BASE_URL", base_url},
      {"THREADR_CONTROL_PLANE_TOKEN", token},
      {"THREADR_BOT_SMOKE_NAMESPACE", namespace},
      {"THREADR_BOT_SMOKE_DEPLOYMENT_NAME", deployment_name},
      {"THREADR_BOT_SMOKE_TIMEOUT", "#{div(timeout_ms, 1_000)}s"}
    ]

    case System.cmd("go", ["run", "./cmd/threadrbot-smoke"],
           cd: operator_dir,
           env: env,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        output

      {output, status} ->
        Mix.raise("operator smoke failed with status #{status}:\n#{output}")
    end
  end

  defp await_controller_callback!(bot_id, generation, deployment_name, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await_controller_callback(bot_id, generation, deployment_name, deadline)
  end

  defp do_await_controller_callback(bot_id, generation, deployment_name, deadline) do
    bot = Smoke.reload_bot!(bot_id)

    if bot.observed_generation == generation and bot.deployment_name == deployment_name and
         bot.status in [:reconciling, :running, :stopped, :degraded] do
      bot
    else
      if System.monotonic_time(:millisecond) >= deadline do
        Mix.raise(
          "timed out waiting for controller callback, last bot state: #{inspect(bot, pretty: true)}"
        )
      end

      Process.sleep(250)
      do_await_controller_callback(bot_id, generation, deployment_name, deadline)
    end
  end

  defp start_server!(port, token) do
    server_log = Path.join(System.tmp_dir!(), "threadr-operator-smoke-server-#{port}.log")

    {pid, 0} =
      System.cmd(
        "sh",
        ["-lc", "mix phx.server > #{server_log} 2>&1 & echo $!"],
        cd: File.cwd!(),
        env: [
          {"PHX_SERVER", "true"},
          {"PORT", Integer.to_string(port)},
          {"THREADR_CONTROL_PLANE_TOKEN", token},
          {"MIX_ENV", Atom.to_string(Mix.env())}
        ]
      )

    {String.trim(pid), server_log}
  end

  defp stop_server({pid, _server_log}) do
    _ = System.cmd("kill", ["-TERM", pid])
    :ok
  end

  defp wait_for_http!(host, port, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_http(host, port, deadline)
  end

  defp do_wait_for_http(host, port, deadline) do
    case :gen_tcp.connect(String.to_charlist(host), port, [:binary, active: false], 500) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      {:error, _reason} ->
        if System.monotonic_time(:millisecond) >= deadline do
          Mix.raise("timed out waiting for Phoenix server on #{host}:#{port}")
        end

        Process.sleep(100)
        do_wait_for_http(host, port, deadline)
    end
  end

  defp find_available_port! do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  defp summarize_operator_output(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.filter(fn line ->
      String.starts_with?(line, "ThreadrBot smoke passed") or
        String.starts_with?(line, "threadrbot:") or
        String.starts_with?(line, "deployment:")
    end)
    |> Enum.join("\n")
  end
end
