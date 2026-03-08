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
  alias Threadr.ControlPlane.SmokeServer

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

    Application.put_env(:threadr, :control_plane_token, token)
    server_pid = start_server!(port, token)

    try do
      wait_for_contract_api!("http://127.0.0.1:#{port}", token, timeout_ms)

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

  defp start_server!(port, _token) do
    case Supervisor.start_child(
           Threadr.Supervisor,
           {SmokeServer, port: port}
         ) do
      {:ok, pid} ->
        pid

      {:error, {:already_started, pid}} ->
        pid

      {:error, reason} ->
        Mix.raise("failed to start smoke control-plane server: #{inspect(reason)}")
    end
  end

  defp stop_server(pid) do
    _ = GenServer.stop(pid, :normal, 5_000)
    :ok
  end

  defp wait_for_contract_api!(base_url, token, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_contract_api(base_url, token, deadline)
  end

  defp do_wait_for_contract_api(base_url, token, deadline) do
    case Req.get(
           "#{base_url}/api/control-plane/bot-contracts",
           headers: [{"authorization", "Bearer #{token}"}],
           receive_timeout: 500
         ) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, response} ->
        maybe_wait_for_contract_api(
          deadline,
          "unexpected status #{response.status}",
          base_url,
          token
        )

      {:error, reason} ->
        maybe_wait_for_contract_api(deadline, inspect(reason), base_url, token)
    end
  end

  defp maybe_wait_for_contract_api(deadline, reason, base_url, token) do
    if System.monotonic_time(:millisecond) >= deadline do
      Mix.raise("timed out waiting for control-plane API readiness: #{reason}")
    end

    Process.sleep(100)
    do_wait_for_contract_api(base_url, token, deadline)
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
