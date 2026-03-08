defmodule ThreadrWeb.PasswordSettingsLiveTest do
  use ThreadrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Threadr.ControlPlane

  test "bootstrap users are redirected to password rotation and can update their password", %{
    conn: conn
  } do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      ControlPlane.create_bootstrap_user(
        %{
          email: "bootstrap-#{suffix}@example.com",
          name: "Bootstrap User #{suffix}",
          is_operator_admin: true,
          must_rotate_password: true,
          password: "bootstrap-password-#{suffix}"
        },
        context: %{system: true}
      )

    conn =
      conn
      |> init_test_session(%{})
      |> post("/auth/user/password/sign_in", %{
        "user" => %{
          "email" => to_string(user.email),
          "password" => "bootstrap-password-#{suffix}"
        }
      })

    assert {:error, {:redirect, %{to: "/settings/password", flash: flash}}} =
             live(conn, ~p"/control-plane/tenants")

    assert flash["info"] =~ "Rotate your bootstrap password"

    {:ok, view, html} = live(conn, ~p"/settings/password")

    assert html =~ "Rotate your bootstrap password before using the control plane."

    view
    |> form("form", %{
      password: %{
        current_password: "bootstrap-password-#{suffix}",
        password: "rotated-password-#{suffix}",
        password_confirmation: "rotated-password-#{suffix}"
      }
    })
    |> render_submit()

    assert_redirect(view, "/control-plane/tenants")
  end

  test "password validation errors do not echo submitted passwords in the UI", %{conn: conn} do
    suffix = System.unique_integer([:positive])
    current_password = "bootstrap-password-#{suffix}"
    attempted_password = "short-#{suffix}"

    {:ok, user} =
      ControlPlane.create_bootstrap_user(
        %{
          email: "bootstrap-invalid-#{suffix}@example.com",
          name: "Bootstrap Invalid #{suffix}",
          is_operator_admin: true,
          must_rotate_password: true,
          password: current_password
        },
        context: %{system: true}
      )

    conn =
      conn
      |> init_test_session(%{})
      |> post("/auth/user/password/sign_in", %{
        "user" => %{
          "email" => to_string(user.email),
          "password" => current_password
        }
      })

    {:ok, view, _html} = live(conn, ~p"/settings/password")

    html =
      view
      |> form("form", %{
        password: %{
          current_password: current_password,
          password: attempted_password,
          password_confirmation: "#{attempted_password}-mismatch"
        }
      })
      |> render_submit()

    assert html =~ "Password update failed:"
    assert html =~ "length must be greater than or equal to 12"
    assert html =~ "confirmation did not match value"
    refute html =~ "%Ash.Error.Invalid"
    refute html =~ "REDACTED"
  end
end
