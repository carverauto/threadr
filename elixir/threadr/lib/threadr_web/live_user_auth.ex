defmodule ThreadrWeb.LiveUserAuth do
  @moduledoc """
  Helpers for loading and requiring authenticated users in LiveView.
  """

  import Phoenix.Component
  use ThreadrWeb, :verified_routes

  alias ThreadrWeb.UserRoutes

  def on_mount(:current_user, _params, session, socket) do
    {:cont, AshAuthentication.Phoenix.LiveSession.assign_new_resources(socket, session)}
  end

  def on_mount(:live_user_optional, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end

  def on_mount(:live_user_required, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}
    end
  end

  def on_mount(:password_rotation_required, _params, _session, socket) do
    if socket.assigns[:current_user] && socket.assigns.current_user.must_rotate_password do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/settings/password")}
    else
      {:cont, socket}
    end
  end

  def on_mount(:live_no_user, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:halt,
       Phoenix.LiveView.redirect(socket, to: UserRoutes.home_path(socket.assigns.current_user))}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end
end
