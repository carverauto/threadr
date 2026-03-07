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
end
