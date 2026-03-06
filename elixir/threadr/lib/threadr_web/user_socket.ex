defmodule ThreadrWeb.UserSocket do
  use Phoenix.Socket

  channel "graph:*", ThreadrWeb.TenantGraphChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) when is_binary(token) do
    case Phoenix.Token.verify(ThreadrWeb.Endpoint, "user socket", token, max_age: 86_400) do
      {:ok, user_id} when is_binary(user_id) ->
        {:ok, assign(socket, :user_id, user_id)}

      _ ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(%{assigns: %{user_id: user_id}}), do: "users_socket:#{user_id}"
end
