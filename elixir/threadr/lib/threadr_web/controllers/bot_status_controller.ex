defmodule ThreadrWeb.BotStatusController do
  use ThreadrWeb, :controller

  alias Threadr.ControlPlane.Service

  def update(conn, %{"subject_name" => subject_name, "id" => bot_id, "status" => status_params}) do
    with {:ok, bot} <-
           Service.report_bot_status_for_controller(subject_name, bot_id, status_params) do
      json(conn, %{data: bot_json(bot)})
    else
      {:error, {:tenant_not_found, _}} ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Tenant not found"}})

      {:error, {:bot, :not_found, _}} ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Bot not found"}})

      {:error, {:deployment_mismatch, _, _}} ->
        conn
        |> put_status(:conflict)
        |> json(%{errors: %{detail: "Deployment mismatch"}})

      {:error, {:generation_mismatch, _, _}} ->
        conn
        |> put_status(:conflict)
        |> json(%{errors: %{detail: "Generation mismatch"}})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{detail: inspect(reason)}})
    end
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
      settings: Threadr.ControlPlane.BotConfig.redact_settings(bot.settings),
      deployment_name: bot.deployment_name,
      inserted_at: bot.inserted_at,
      updated_at: bot.updated_at
    }
  end
end
