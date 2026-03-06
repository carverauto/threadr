defmodule Threadr.ControlPlane.PolicyTest do
  use Threadr.DataCase, async: false

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Service

  test "direct tenant reads are scoped to tenant membership" do
    owner = create_user!("owner")
    other_user = create_user!("other")
    tenant = create_tenant!("Owned", owner)

    assert {:error, %Ash.Error.Invalid{errors: errors}} =
             ControlPlane.get_tenant_by_subject_name(tenant.subject_name, actor: other_user)

    assert Enum.any?(errors, &match?(%Ash.Error.Query.NotFound{}, &1))
  end

  test "direct bot creation is blocked for non-manager tenant members" do
    owner = create_user!("owner")
    member = create_user!("member")
    tenant = create_tenant!("Managed", owner)

    {:ok, _membership} =
      ControlPlane.create_tenant_membership(
        %{user_id: member.id, tenant_id: tenant.id, role: "member"},
        context: %{system: true}
      )

    assert {:error, %Ash.Error.Forbidden{}} =
             ControlPlane.create_bot(
               %{
                 tenant_id: tenant.id,
                 name: "irc-main",
                 platform: "irc",
                 channels: ["#threadr"],
                 settings: %{"server" => "irc.example.com", "nick" => "threadr-bot"}
               },
               actor: member
             )
  end

  test "direct api key creation cannot target another user" do
    owner = create_user!("owner")
    other_user = create_user!("other")

    assert {:error, %Ash.Error.Forbidden{}} =
             ControlPlane.create_api_key(
               %{user_id: owner.id, name: "forbidden"},
               actor: other_user
             )
  end

  test "direct tenant membership creation is blocked for non-manager tenant members" do
    owner = create_user!("owner")
    member = create_user!("member")
    invitee = create_user!("invitee")
    tenant = create_tenant!("Managed", owner)

    {:ok, _membership} =
      ControlPlane.create_tenant_membership(
        %{user_id: member.id, tenant_id: tenant.id, role: "member"},
        context: %{system: true}
      )

    assert {:error, %Ash.Error.Forbidden{}} =
             ControlPlane.create_tenant_membership(
               %{user_id: invitee.id, tenant_id: tenant.id, role: "member"},
               actor: member
             )
  end

  test "direct tenant membership reads are allowed for tenant managers" do
    owner = create_user!("owner")
    member = create_user!("member")
    tenant = create_tenant!("Managed", owner)

    {:ok, _membership} =
      ControlPlane.create_tenant_membership(
        %{user_id: member.id, tenant_id: tenant.id, role: "member"},
        context: %{system: true}
      )

    assert {:ok, memberships} =
             ControlPlane.list_tenant_memberships(
               actor: owner,
               query: [filter: [tenant_id: tenant.id]]
             )

    assert Enum.count(memberships) == 2
  end

  defp create_user!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      ControlPlane.register_user(%{
        email: "#{prefix}-#{suffix}@example.com",
        name: "Policy User #{suffix}",
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
          subject_name: "#{String.downcase(prefix)}-#{suffix}"
        },
        owner_user: owner
      )

    tenant
  end
end
