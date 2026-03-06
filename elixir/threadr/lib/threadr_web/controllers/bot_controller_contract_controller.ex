defmodule ThreadrWeb.BotControllerContractController do
  use ThreadrWeb, :controller

  alias Threadr.ControlPlane.Service

  def index(conn, _params) do
    with {:ok, contracts} <- Service.list_bot_controller_contracts() do
      json(conn, %{data: Enum.map(contracts, &contract_json/1)})
    else
      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{detail: inspect(reason)}})
    end
  end

  def show(conn, %{"subject_name" => subject_name, "id" => bot_id}) do
    with {:ok, contract} <-
           Service.get_bot_controller_contract_for_controller(subject_name, bot_id) do
      json(conn, %{data: contract_json(contract)})
    else
      {:error, {:tenant_not_found, _}} ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Tenant not found"}})

      {:error, {:bot, :not_found, _}} ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Bot not found"}})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{detail: inspect(reason)}})
    end
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
end
