defmodule ThreadrWeb.ApiKeyLiveTest do
  use ThreadrWeb.ConnCase, async: false

  import AshAuthentication.Phoenix.Plug, only: [store_in_session: 2]
  import Phoenix.LiveViewTest

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Service

  test "signed-in users can create and revoke API keys", %{conn: conn} do
    user = create_user!("live")

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, view, html} = live(conn, ~p"/settings/api-keys")

    assert html =~ "API Keys"
    assert html =~ to_string(user.email)

    view
    |> form("form", %{api_key: %{name: "CI automation"}})
    |> render_submit()

    assert render(view) =~ "API key created"
    assert render(view) =~ "CI automation"

    {:ok, [api_key]} = Service.list_user_api_keys(user)

    view
    |> element("button[phx-value-id='#{api_key.id}']")
    |> render_click()

    {:ok, [revoked_api_key]} = Service.list_user_api_keys(user)
    assert not is_nil(revoked_api_key.revoked_at)
  end

  defp create_user!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      ControlPlane.register_user(%{
        email: "#{prefix}-#{suffix}@example.com",
        name: "Live User #{suffix}",
        password: "threadr-password-#{suffix}"
      })

    user
  end
end
