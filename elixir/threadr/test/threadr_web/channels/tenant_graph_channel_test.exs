defmodule ThreadrWeb.TenantGraphChannelTest do
  use ThreadrWeb.ConnCase, async: false

  import Phoenix.ChannelTest

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Service
  alias Threadr.TenantData.LiveUpdates

  @endpoint ThreadrWeb.Endpoint

  test "pushes an initial snapshot and refreshes on tenant ingest PubSub" do
    user = create_user!("tenant-graph-channel")
    tenant = create_tenant!("Graph Channel Tenant", user)

    {:ok, _reply, socket} =
      socket(ThreadrWeb.UserSocket, "graph-user:#{user.id}", %{user_id: user.id})
      |> subscribe_and_join(ThreadrWeb.TenantGraphChannel, "graph:#{tenant.subject_name}", %{})

    assert_push "snapshot_meta", %{revision: initial_revision}
    assert_push "snapshot", {:binary, initial_frame}
    assert is_binary(initial_frame)

    :ok =
      LiveUpdates.broadcast_message_persisted(tenant.subject_name, %{
        message_id: Ecto.UUID.generate(),
        actor_id: Ecto.UUID.generate(),
        channel_id: Ecto.UUID.generate(),
        observed_at: DateTime.utc_now() |> DateTime.truncate(:second),
        actor_ids: []
      })

    assert_push "snapshot_meta", %{revision: next_revision}, 1_000
    assert_push "snapshot", {:binary, next_frame}, 1_000
    assert is_binary(next_frame)

    assert socket.topic == "graph:#{tenant.subject_name}"
    assert is_integer(initial_revision)
    assert is_integer(next_revision)
  end

  defp create_user!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      ControlPlane.register_user(%{
        email: "#{prefix}-#{suffix}@example.com",
        name: "Tenant Graph Channel User #{suffix}",
        password: "threadr-password-#{suffix}"
      })

    user
  end

  defp create_tenant!(name_prefix, owner_user) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(
        %{
          name: "#{name_prefix} #{suffix}",
          subject_name: "graph-channel-#{suffix}"
        },
        owner_user: owner_user
      )

    tenant
  end
end
