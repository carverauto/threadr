defmodule ThreadrWeb.UserRoutes do
  @moduledoc """
  Shared top-level destinations for signed-in users.
  """

  alias Threadr.ControlPlane.Service

  def home_path(user) do
    if Service.operator_admin?(user) do
      "/control-plane/tenants"
    else
      "/bots"
    end
  end
end
