defmodule ThreadrWeb.Api.V1.BotPlatformControllerTest do
  use ThreadrWeb.ConnCase, async: true

  alias Threadr.ControlPlane.Service

  test "GET /api/v1/bot-platforms returns platform configuration metadata", %{conn: conn} do
    user = create_user!("platforms")

    conn =
      conn
      |> api_key_conn(user)
      |> get(~p"/api/v1/bot-platforms")

    assert %{"data" => data} = json_response(conn, 200)

    assert data["irc"] == %{
             "platform" => "irc",
             "required_env" => ["THREADR_IRC_HOST", "THREADR_IRC_NICK"],
             "optional_env" => [
               "THREADR_IRC_PASSWORD",
               "THREADR_IRC_PORT",
               "THREADR_IRC_REALNAME",
               "THREADR_IRC_SSL",
               "THREADR_IRC_USER"
             ],
             "legacy_settings" => [
               "host",
               "nick",
               "password",
               "port",
               "realname",
               "server",
               "ssl",
               "user"
             ],
             "channel_format" => "irc-channel",
             "supports_image_override" => true
           }

    assert data["discord"] == %{
             "platform" => "discord",
             "required_env" => ["THREADR_DISCORD_TOKEN"],
             "optional_env" => [],
             "legacy_settings" => ["token"],
             "channel_format" => "discord-channel-id",
             "supports_image_override" => true
           }
  end

  defp api_key_conn(conn, user) do
    {:ok, _api_key, plaintext_api_key} = Service.create_api_key(user, %{name: "platform-api"})

    conn
    |> put_req_header("authorization", "Bearer #{plaintext_api_key}")
    |> put_req_header("accept", "application/json")
  end

  defp create_user!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      Threadr.ControlPlane.register_user(%{
        email: "#{prefix}-#{suffix}@example.com",
        name: "User #{suffix}",
        password: "threadr-password-#{suffix}"
      })

    user
  end
end
