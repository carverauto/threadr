defmodule ThreadrWeb.Api.V1.BotController do
  use ThreadrWeb, :controller

  alias Threadr.ControlPlane.Service

  def index(conn, %{"subject_name" => subject_name}) do
    with {:ok, user} <- current_user(conn),
         {:ok, bots} <- Service.list_bots_for_user(user, subject_name) do
      json(conn, %{data: Enum.map(bots, &bot_json/1)})
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{errors: %{detail: "Unauthorized"}})

      {:error, {:tenant_not_found, _}} ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Tenant not found"}})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{errors: %{detail: "Forbidden"}})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{detail: inspect(reason)}})
    end
  end

  def create(conn, %{"subject_name" => subject_name, "bot" => bot_params}) do
    with {:ok, user} <- current_user(conn),
         {:ok, bot} <- Service.create_bot_for_user(user, subject_name, bot_params) do
      conn
      |> put_status(:created)
      |> json(%{data: bot_json(bot)})
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{errors: %{detail: "Unauthorized"}})

      {:error, {:tenant_not_found, _}} ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Tenant not found"}})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{errors: %{detail: "Forbidden"}})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{detail: inspect(reason)}})
    end
  end

  def update(conn, %{"subject_name" => subject_name, "id" => bot_id, "bot" => bot_params}) do
    with {:ok, user} <- current_user(conn),
         {:ok, bot} <- Service.update_bot_for_user(user, subject_name, bot_id, bot_params) do
      json(conn, %{data: bot_json(bot)})
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{errors: %{detail: "Unauthorized"}})

      {:error, {:tenant_not_found, _}} ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Tenant not found"}})

      {:error, {:bot, :not_found, _}} ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Bot not found"}})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{errors: %{detail: "Forbidden"}})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{detail: inspect(reason)}})
    end
  end

  def delete(conn, %{"subject_name" => subject_name, "id" => bot_id}) do
    with {:ok, user} <- current_user(conn),
         :ok <- Service.delete_bot_for_user(user, subject_name, bot_id) do
      send_resp(conn, :no_content, "")
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{errors: %{detail: "Unauthorized"}})

      {:error, {:tenant_not_found, _}} ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Tenant not found"}})

      {:error, {:bot, :not_found, _}} ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Bot not found"}})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{errors: %{detail: "Forbidden"}})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{detail: inspect(reason)}})
    end
  end

  defp current_user(%{assigns: %{current_user: %{id: _} = user}}), do: {:ok, user}
  defp current_user(_conn), do: {:error, :unauthorized}

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
