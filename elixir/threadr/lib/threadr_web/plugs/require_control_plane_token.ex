defmodule ThreadrWeb.Plugs.RequireControlPlaneToken do
  @moduledoc """
  Authenticates machine-to-machine control-plane requests with a shared bearer token.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, expected_token} <- fetch_expected_token(),
         {:ok, provided_token} <- fetch_provided_token(conn),
         true <- secure_match?(provided_token, expected_token) do
      assign(conn, :control_plane_authenticated, true)
    else
      _reason ->
        conn
        |> put_status(:unauthorized)
        |> json(%{errors: %{detail: "Unauthorized"}})
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
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" ->
        {:ok, token}

      ["bearer " <> token] when token != "" ->
        {:ok, token}

      _ ->
        case get_req_header(conn, "x-threadr-control-plane-token") do
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
end
