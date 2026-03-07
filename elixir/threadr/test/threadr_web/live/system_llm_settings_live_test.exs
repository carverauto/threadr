defmodule ThreadrWeb.SystemLlmSettingsLiveTest do
  use ThreadrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Service

  test "operator admins can save system llm settings", %{conn: conn} do
    {user, password} = create_operator_admin!("system-llm-admin")

    conn =
      conn
      |> init_test_session(%{})
      |> post("/auth/user/password/sign_in", %{
        "user" => %{
          "email" => to_string(user.email),
          "password" => password
        }
      })

    {:ok, view, html} = live(conn, ~p"/control-plane/admin/llm")

    assert html =~ "System LLM Settings"

    view
    |> form("form", %{
      settings: %{
        provider_name: "openai",
        endpoint: "https://api.openai.com/v1/chat/completions",
        model: "gpt-4.1-mini",
        api_key: "sk-test-system-key",
        temperature: "0.1",
        max_tokens: "384",
        system_prompt: "Answer using tenant context."
      }
    })
    |> render_submit(%{"intent" => "save"})

    rendered = render(view)
    assert rendered =~ "System LLM settings saved."

    assert {:ok, settings} = Service.get_system_llm_config_for_user(user)
    assert settings.provider_name == "openai"
    assert settings.endpoint == "https://api.openai.com/v1/chat/completions"
    assert settings.model == "gpt-4.1-mini"
    assert settings.temperature == 0.1
    assert settings.max_tokens == 384
    assert settings.system_prompt == "Answer using tenant context."
    assert settings.api_key_configured
  end

  test "operator admins get a provider default endpoint when left blank", %{conn: conn} do
    {user, password} = create_operator_admin!("system-llm-anthropic")

    conn =
      conn
      |> init_test_session(%{})
      |> post("/auth/user/password/sign_in", %{
        "user" => %{
          "email" => to_string(user.email),
          "password" => password
        }
      })

    {:ok, view, _html} = live(conn, ~p"/control-plane/admin/llm")

    view
    |> form("form", %{
      settings: %{
        provider_name: "anthropic",
        endpoint: "",
        model: "claude-3-5-sonnet-latest",
        api_key: "anthropic-test-key"
      }
    })
    |> render_submit(%{"intent" => "save"})

    assert {:ok, settings} = Service.get_system_llm_config_for_user(user)
    assert settings.provider_name == "anthropic"
    assert settings.endpoint == "https://api.anthropic.com/v1/messages"
  end

  test "non operator admins are denied system llm settings", %{conn: conn} do
    {user, password} = create_user!("system-llm-member")

    conn =
      conn
      |> init_test_session(%{})
      |> post("/auth/user/password/sign_in", %{
        "user" => %{
          "email" => to_string(user.email),
          "password" => password
        }
      })

    assert {:error, {:live_redirect, %{to: "/control-plane/tenants"}}} =
             live(conn, ~p"/control-plane/admin/llm")
  end

  defp create_operator_admin!(prefix) do
    suffix = System.unique_integer([:positive])

    password = "bootstrap-password-#{suffix}"

    {:ok, user} =
      ControlPlane.create_bootstrap_user(
        %{
          email: "#{prefix}-#{suffix}@example.com",
          name: "System LLM Admin #{suffix}",
          is_operator_admin: true,
          must_rotate_password: false,
          password: password
        },
        context: %{system: true}
      )

    {user, password}
  end

  defp create_user!(prefix) do
    suffix = System.unique_integer([:positive])
    password = "threadr-password-#{suffix}"

    {:ok, user} =
      ControlPlane.register_user(%{
        email: "#{prefix}-#{suffix}@example.com",
        name: "Tenant User #{suffix}",
        password: password
      })

    {user, password}
  end
end
