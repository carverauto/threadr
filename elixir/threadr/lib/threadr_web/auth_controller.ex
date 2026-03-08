defmodule ThreadrWeb.AuthController do
  use ThreadrWeb, :controller
  use AshAuthentication.Phoenix.Controller

  alias ThreadrWeb.UserRoutes

  def success(conn, activity, user, _token) do
    return_to =
      if user.must_rotate_password do
        ~p"/settings/password"
      else
        get_session(conn, :return_to) || UserRoutes.home_path(user)
      end

    message =
      case activity do
        {:password, :reset} -> "Your password has been reset"
        {:password, :register} -> "Your account has been created"
        _ when user.must_rotate_password -> "Rotate your bootstrap password before continuing"
        _ -> "You are now signed in"
      end

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    |> assign(:current_user, user)
    |> put_flash(:info, message)
    |> redirect(to: return_to)
  end

  def failure(conn, _activity, _reason) do
    conn
    |> put_flash(:error, "Incorrect email or password")
    |> redirect(to: ~p"/sign-in")
  end

  def sign_out(conn, _params) do
    conn
    |> clear_session(:threadr)
    |> put_flash(:info, "You are now signed out")
    |> redirect(to: ~p"/")
  end
end
