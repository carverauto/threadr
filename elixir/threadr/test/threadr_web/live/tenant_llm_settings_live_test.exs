defmodule ThreadrWeb.TenantLlmSettingsLiveTest do
  use ThreadrWeb.ConnCase, async: false

  import AshAuthentication.Phoenix.Plug, only: [store_in_session: 2]
  import Phoenix.LiveViewTest

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Service

  test "tenant managers do not see system provider fields when system mode is selected", %{
    conn: conn
  } do
    user = create_user!("tenant-llm-system")
    tenant = create_tenant!("Tenant LLM", user)

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, _view, html} = live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/llm")

    assert html =~ "Use system provider"
    assert html =~ "System provider details"
    refute html =~ ~s(name="settings[endpoint]")
    refute html =~ ~s(name="settings[provider_name]")
  end

  test "tenant managers can save tenant-specific llm settings", %{conn: conn} do
    user = create_user!("tenant-llm")
    tenant = create_tenant!("Tenant LLM", user)

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, view, html} = live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/llm")

    assert html =~ "Tenant LLM Settings"
    assert html =~ tenant.subject_name

    form =
      form(view, "form", %{
        settings: %{
          use_system: "false"
        }
      })

    render_change(form)

    form
    |> render_submit(%{
      "intent" => "save",
      settings: %{
        use_system: "false",
        provider_name: "openai",
        endpoint: "https://api.openai.com/v1/chat/completions",
        model: "gpt-4.1-mini",
        api_key: "sk-test-tenant-key",
        temperature: "0.2",
        max_tokens: "256",
        system_prompt: "Answer using tenant context only."
      }
    })

    rendered = render(view)
    assert rendered =~ "Tenant LLM settings saved. QA will use the tenant override."

    assert {:ok, settings} = Service.get_tenant_llm_config_for_user(user, tenant.subject_name)
    assert settings.use_system == false
    assert settings.provider_name == "openai"
    assert settings.endpoint == "https://api.openai.com/v1/chat/completions"
    assert settings.model == "gpt-4.1-mini"
    assert settings.temperature == 0.2
    assert settings.max_tokens == 256
    assert settings.system_prompt == "Answer using tenant context only."
    assert settings.api_key_configured == true
  end

  test "tenant managers get a provider default endpoint when left blank", %{conn: conn} do
    user = create_user!("tenant-llm-gemini")
    tenant = create_tenant!("Tenant LLM Gemini", user)

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, view, _html} = live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/llm")

    form(view, "form", %{settings: %{use_system: "false"}})
    |> render_change()

    form(view, "form", %{
      settings: %{
        use_system: "false",
        provider_name: "gemini",
        endpoint: "",
        model: "gemini-2.5-pro",
        api_key: "gemini-test-key"
      }
    })
    |> render_submit(%{"intent" => "save"})

    assert {:ok, settings} = Service.get_tenant_llm_config_for_user(user, tenant.subject_name)
    assert settings.provider_name == "gemini"
    assert settings.endpoint ==
             "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
  end

  defp create_user!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      ControlPlane.register_user(%{
        email: "#{prefix}-#{suffix}@example.com",
        name: "Tenant LLM User #{suffix}",
        password: "threadr-password-#{suffix}"
      })

    user
  end

  defp create_tenant!(prefix, owner) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(
        %{
          name: "#{prefix} #{suffix}",
          subject_name: "tenant-llm-#{suffix}"
        },
        owner_user: owner
      )

    tenant
  end
end
