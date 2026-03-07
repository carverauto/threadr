defmodule ThreadrWeb.Api.V1.BotPlatformController do
  use ThreadrWeb, :controller

  def index(conn, _params) do
    json(conn, %{data: Threadr.ControlPlane.BotConfig.platform_schemas()})
  end
end
