defmodule ThreadrWeb.TenantBotLiveTest do
  use ThreadrWeb.ConnCase, async: false

  import AshAuthentication.Phoenix.Plug, only: [store_in_session: 2]
  import Phoenix.LiveViewTest

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Service

  test "regular users get a personal bot workspace and can manage bots from /bots", %{conn: conn} do
    user = create_user!("tenant-bot-owner")

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, view, html} = live(conn, ~p"/bots")

    assert html =~ "My Bots"
    refute html =~ "Tenant Bots"
    refute html =~ "/control-plane/tenants"

    view
    |> form("#tenant-bot-form", %{
      bot: %{
        name: "irc-main",
        platform: "irc",
        desired_state: "running",
        channels: "#threadr\n#ops",
        image: "",
        irc_host: "irc.example.com",
        irc_nick: "threadr-bot",
        irc_password: "super-secret",
        irc_port: "6697",
        irc_realname: "Threadr Bot",
        irc_ssl: "true",
        irc_user: "threadr"
      }
    })
    |> render_submit()

    rendered = render(view)
    assert rendered =~ "Bot created: irc-main"
    assert rendered =~ "irc-main"
    assert rendered =~ "#threadr, #ops"

    [membership] = personal_memberships!(user)
    tenant = membership.tenant

    {:ok, [bot]} = Service.list_bots_for_user(user, tenant.subject_name)
    assert bot.name == "irc-main"
    assert bot.platform == "irc"
    assert bot.desired_state == "running"

    view
    |> element("#tenant-bot-edit-#{bot.id}")
    |> render_click()

    rendered = render(view)
    assert rendered =~ "Edit Bot"
    assert rendered =~ "irc.example.com"

    view
    |> form("#tenant-bot-form", %{
      bot: %{
        name: "irc-main",
        desired_state: "stopped",
        channels: "#ops",
        image: "ghcr.io/example/threadr-bot:test",
        irc_host: "irc2.example.com",
        irc_nick: "threadr-bot-2",
        irc_password: "second-secret",
        irc_port: "6667",
        irc_realname: "Threadr Bot 2",
        irc_ssl: "false",
        irc_user: "threadr2"
      }
    })
    |> render_submit()

    rendered = render(view)
    assert rendered =~ "Bot updated: irc-main"
    assert rendered =~ "desired: stopped"
    assert rendered =~ "THREADR_IRC_HOST=irc2.example.com"
    assert rendered =~ "image=ghcr.io/example/threadr-bot:test"

    {:ok, [updated_bot]} = Service.list_bots_for_user(user, tenant.subject_name)
    assert updated_bot.id == bot.id
    assert updated_bot.desired_state == "stopped"
    assert updated_bot.channels == ["#ops"]

    view
    |> element("#tenant-bot-delete-#{bot.id}")
    |> render_click()

    rendered = render(view)
    assert rendered =~ "Bot deleted"
    refute rendered =~ "irc-main"

    assert {:ok, []} = Service.list_bots_for_user(user, tenant.subject_name)

    view
    |> form("#tenant-bot-form", %{
      bot: %{
        platform: "discord"
      }
    })
    |> render_change()

    rendered = render(view)
    assert rendered =~ "Discord Token"
    refute rendered =~ "IRC Host"
    refute rendered =~ "Application ID"
    refute rendered =~ "Public Key"

    view
    |> form("#tenant-bot-form", %{
      bot: %{
        name: "discord-main",
        platform: "discord",
        desired_state: "running",
        channels: "123456789012345678\n234567890123456789",
        image: "",
        discord_token: "discord-token"
      }
    })
    |> render_submit()

    rendered = render(view)
    assert rendered =~ "Bot created: discord-main"
    assert rendered =~ "discord-main"
    assert rendered =~ "123456789012345678, 234567890123456789"
    assert rendered =~ "THREADR_DISCORD_TOKEN=[REDACTED]"

    {:ok, [discord_bot]} = Service.list_bots_for_user(user, tenant.subject_name)
    assert discord_bot.name == "discord-main"
    assert discord_bot.platform == "discord"
    assert discord_bot.channels == ["123456789012345678", "234567890123456789"]
  end

  test "operator admins can still open the tenant-scoped bot inventory", %{conn: conn} do
    {operator, password} = create_operator!("tenant-bot-operator")
    tenant = create_tenant!("Bot Tenant", operator)

    conn =
      conn
      |> init_test_session(%{})
      |> post("/auth/user/password/sign_in", %{
        "user" => %{
          "email" => to_string(operator.email),
          "password" => password
        }
      })

    {:ok, _view, html} = live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/bots")

    assert html =~ "Tenant Bots"
    assert html =~ tenant.subject_name
    assert html =~ "/control-plane/tenants/#{tenant.subject_name}/history"
  end

  test "non-manager memberships are denied tenant bot management", %{conn: conn} do
    owner = create_user!("tenant-bot-admin")
    member = create_user!("tenant-bot-member")
    tenant = create_tenant!("Bot Access Tenant", owner)

    {:ok, _membership} =
      ControlPlane.create_tenant_membership(
        %{user_id: member.id, tenant_id: tenant.id, role: "member"},
        context: %{system: true}
      )

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(member)

    assert {:error, {:live_redirect, %{to: "/bots"}}} =
             live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/bots")
  end

  defp create_user!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      ControlPlane.register_user(%{
        email: "#{prefix}-#{suffix}@example.com",
        name: "Tenant Bot User #{suffix}",
        password: "threadr-password-#{suffix}"
      })

    user
  end

  defp create_operator!(prefix) do
    suffix = System.unique_integer([:positive])
    password = "threadr-password-#{suffix}"

    {:ok, user} =
      ControlPlane.create_bootstrap_user(
        %{
          email: "#{prefix}-#{suffix}@example.com",
          name: "Tenant Bot Operator #{suffix}",
          is_operator_admin: true,
          must_rotate_password: false,
          password: password
        },
        context: %{system: true}
      )

    {user, password}
  end

  defp create_tenant!(name_prefix, owner_user) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(
        %{
          name: "#{name_prefix} #{suffix}",
          subject_name: "tenant-bots-#{suffix}"
        },
        owner_user: owner_user
      )

    tenant
  end

  defp personal_memberships!(user) do
    {:ok, memberships} = Service.list_user_memberships(user)

    Enum.filter(memberships, fn membership ->
      metadata = membership.tenant.metadata || %{}
      metadata["workspace"] == "personal" and metadata["owner_user_id"] == user.id
    end)
  end
end
