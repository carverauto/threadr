defmodule Threadr.ControlPlane.SmokeServer do
  @moduledoc """
  Minimal machine API used by the operator smoke test.

  The smoke flow already runs inside a fully booted Threadr application, so
  spinning up a second Phoenix runtime adds avoidable flakiness. This plug
  exposes only the control-plane endpoints the operator smoke binary needs.
  """

  use Plug.Router

  alias Threadr.ControlPlane.BotConfig
  alias Threadr.ControlPlane.Service

  plug(Plug.Logger)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Phoenix.json_library()
  )

  plug(:match)
  plug(:authenticate)
  plug(:dispatch)

  get "/health/ready" do
    send_json(conn, 200, %{status: "ok"})
  end

  get "/api/control-plane/bot-contracts" do
    case Service.list_bot_controller_contracts() do
      {:ok, contracts} ->
        send_json(conn, 200, %{data: Enum.map(contracts, &contract_json/1)})

      {:error, reason} ->
        send_json(conn, 422, %{errors: %{detail: inspect(reason)}})
    end
  end

  post "/api/control-plane/tenants/:subject_name/bots/:id/status" do
    case Map.fetch(conn.body_params, "status") do
      {:ok, status_params} ->
        report_status(conn, subject_name, id, status_params)

      :error ->
        send_json(conn, 422, %{errors: %{detail: "Missing status payload"}})
    end
  end

  match _ do
    send_json(conn, 404, %{errors: %{detail: "Not found"}})
  end

  def child_spec(opts) do
    ip = Keyword.get(opts, :ip, {127, 0, 0, 1})
    port = Keyword.fetch!(opts, :port)

    %{
      id: {__MODULE__, port},
      restart: :temporary,
      start:
        {Bandit, :start_link,
         [[plug: __MODULE__, ip: ip, port: port, scheme: :http, startup_log: false]]}
    }
  end

  defp authenticate(conn, _opts) do
    with {:ok, expected_token} <- fetch_expected_token(),
         {:ok, provided_token} <- fetch_provided_token(conn),
         true <- secure_match?(provided_token, expected_token) do
      conn
    else
      _reason ->
        conn
        |> send_json(401, %{errors: %{detail: "Unauthorized"}})
        |> halt()
    end
  end

  defp fetch_expected_token do
    case Application.get_env(:threadr, :control_plane_token) do
      token when is_binary(token) and token != "" -> {:ok, token}
      _ -> {:error, :missing_control_plane_token}
    end
  end

  defp fetch_provided_token(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" ->
        {:ok, token}

      ["bearer " <> token] when token != "" ->
        {:ok, token}

      _ ->
        case Plug.Conn.get_req_header(conn, "x-threadr-control-plane-token") do
          [token] when token != "" -> {:ok, token}
          _ -> {:error, :missing_token}
        end
    end
  end

  defp secure_match?(provided_token, expected_token)
       when byte_size(provided_token) == byte_size(expected_token) do
    Plug.Crypto.secure_compare(provided_token, expected_token)
  end

  defp secure_match?(_provided_token, _expected_token), do: false

  defp report_status(conn, subject_name, bot_id, status_params) do
    case Service.report_bot_status_for_controller(subject_name, bot_id, status_params) do
      {:ok, bot} ->
        send_json(conn, 200, %{data: bot_json(bot)})

      {:error, {:tenant_not_found, _}} ->
        send_json(conn, 404, %{errors: %{detail: "Tenant not found"}})

      {:error, {:bot, :not_found, _}} ->
        send_json(conn, 404, %{errors: %{detail: "Bot not found"}})

      {:error, {:deployment_mismatch, _, _}} ->
        send_json(conn, 409, %{errors: %{detail: "Deployment mismatch"}})

      {:error, {:generation_mismatch, _, _}} ->
        send_json(conn, 409, %{errors: %{detail: "Generation mismatch"}})

      {:error, reason} ->
        send_json(conn, 422, %{errors: %{detail: inspect(reason)}})
    end
  end

  defp send_json(conn, status, payload) do
    body = Phoenix.json_library().encode!(payload)

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, body)
  end

  defp contract_json(contract) do
    %{
      id: contract.id,
      tenant_id: contract.tenant_id,
      bot_id: contract.bot_id,
      generation: contract.generation,
      operation: contract.operation,
      deployment_name: contract.deployment_name,
      namespace: contract.namespace,
      contract: contract.contract,
      inserted_at: contract.inserted_at,
      updated_at: contract.updated_at
    }
  end

  defp bot_json(bot) do
    %{
      id: bot.id,
      tenant_id: bot.tenant_id,
      name: bot.name,
      platform: bot.platform,
      desired_state: bot.desired_state,
      status: bot.status,
      status_reason: bot.status_reason,
      status_metadata: bot.status_metadata,
      last_observed_at: bot.last_observed_at,
      desired_generation: bot.desired_generation,
      observed_generation: bot.observed_generation,
      channels: bot.channels,
      settings: BotConfig.redact_settings(bot.settings),
      deployment_name: bot.deployment_name,
      inserted_at: bot.inserted_at,
      updated_at: bot.updated_at
    }
  end
end
