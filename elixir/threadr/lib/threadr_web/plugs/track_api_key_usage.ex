defmodule ThreadrWeb.Plugs.TrackApiKeyUsage do
  @moduledoc """
  Persists `last_used_at` for API keys that authenticated the current request.
  """

  alias Threadr.ControlPlane.Service

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:current_user] do
      %{__metadata__: %{api_key: %{id: api_key_id}}} when is_binary(api_key_id) ->
        _ = Service.touch_api_key(api_key_id)
        conn

      _ ->
        conn
    end
  end
end
