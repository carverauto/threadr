defmodule ThreadrWeb.HealthController do
  use ThreadrWeb, :controller

  alias Threadr.Repo

  def live(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def ready(conn, _params) do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
      {:ok, _result} ->
        json(conn, %{status: "ok"})

      {:error, _reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "error"})
    end
  rescue
    _error ->
      conn
      |> put_status(:service_unavailable)
      |> json(%{status: "error"})
  end
end
