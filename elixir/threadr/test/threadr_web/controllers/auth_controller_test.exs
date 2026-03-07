defmodule ThreadrWeb.AuthControllerTest do
  use ThreadrWeb.ConnCase, async: false

  alias Threadr.ControlPlane

  test "POST /auth/user/password/register signs in the new user", %{conn: conn} do
    suffix = System.unique_integer([:positive])

    conn =
      post(conn, "/auth/user/password/register", %{
        "user" => %{
          "email" => "register-#{suffix}@example.com",
          "name" => "Register User #{suffix}",
          "password" => "threadr-password-#{suffix}"
        }
      })

    assert redirected_to(conn) == "/control-plane/tenants"
    assert get_session(conn, "user_token")
  end

  test "POST /auth/user/password/register works with the stock register form payload", %{
    conn: conn
  } do
    suffix = System.unique_integer([:positive])

    conn =
      post(conn, "/auth/user/password/register", %{
        "user" => %{
          "email" => "register-form-#{suffix}@example.com",
          "password" => "threadr-password-#{suffix}"
        }
      })

    assert redirected_to(conn) == "/control-plane/tenants"
    assert get_session(conn, "user_token")
  end

  test "POST /auth/user/password/sign_in signs in an existing user", %{conn: conn} do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      ControlPlane.register_user(%{
        email: "signin-#{suffix}@example.com",
        name: "Sign In User #{suffix}",
        password: "threadr-password-#{suffix}"
      })

    conn =
      post(conn, "/auth/user/password/sign_in", %{
        "user" => %{
          "email" => to_string(user.email),
          "password" => "threadr-password-#{suffix}"
        }
      })

    assert redirected_to(conn) == "/control-plane/tenants"
    assert get_session(conn, "user_token")
  end
end
