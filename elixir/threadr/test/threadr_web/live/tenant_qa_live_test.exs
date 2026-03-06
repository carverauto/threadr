defmodule ThreadrWeb.TenantQaLiveTest do
  use ThreadrWeb.ConnCase, async: false

  import AshAuthentication.Phoenix.Plug, only: [store_in_session: 2]
  import Phoenix.LiveViewTest

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Service
  alias Threadr.TenantData.{Actor, Channel, Message, MessageEmbedding}

  setup do
    previous_ml_config = Application.get_env(:threadr, Threadr.ML, [])

    Application.put_env(
      :threadr,
      Threadr.ML,
      Keyword.merge(previous_ml_config,
        embeddings: [provider: Threadr.TestEmbeddingProvider, model: "test-embedding-model"],
        generation: [provider: Threadr.TestGenerationProvider, model: "test-chat"]
      )
    )

    on_exit(fn ->
      Application.put_env(:threadr, Threadr.ML, previous_ml_config)
    end)

    :ok
  end

  test "renders tenant workspace and grounded answer results", %{conn: conn} do
    user = create_user!("tenant-qa")
    tenant = create_tenant!("Tenant QA", user)
    seed_semantic_data!(tenant.schema_name)

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, view, html} = live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/qa")

    assert html =~ "Tenant QA Workspace"
    assert html =~ tenant.subject_name

    view
    |> element("#tenant-qa-form")
    |> render_change(%{"question" => "Who did Alice mention?", "limit" => "2"})

    view
    |> element("#tenant-qa-answer")
    |> render_click()

    rendered = render(view)
    assert rendered =~ "Alice mentioned Bob in incident response planning."
    assert rendered =~ "C1"
    assert rendered =~ "#ops alice: Alice mentioned Bob in incident response planning."
    assert rendered =~ "Citations"
    assert rendered =~ "answer: Context:"
  end

  test "shows a validation error when question is blank", %{conn: conn} do
    user = create_user!("tenant-qa-empty")
    tenant = create_tenant!("Tenant QA Empty", user)

    conn =
      conn
      |> init_test_session(%{})
      |> store_in_session(user)

    {:ok, view, _html} = live(conn, ~p"/control-plane/tenants/#{tenant.subject_name}/qa")

    view
    |> element("#tenant-qa-answer")
    |> render_click()

    assert render(view) =~ "Question is required"
  end

  defp create_user!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      ControlPlane.register_user(%{
        email: "#{prefix}-#{suffix}@example.com",
        name: "Tenant QA User #{suffix}",
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
          subject_name: "tenant-qa-#{suffix}"
        },
        owner_user: owner_user
      )

    tenant
  end

  defp seed_semantic_data!(tenant_schema) do
    actor = create_actor!(tenant_schema, "alice")
    channel = create_channel!(tenant_schema, "ops")

    first_message =
      create_message!(
        tenant_schema,
        actor.id,
        channel.id,
        "Alice mentioned Bob in incident response planning."
      )

    second_message =
      create_message!(
        tenant_schema,
        actor.id,
        channel.id,
        "Alice discussed malware clusters without naming anyone."
      )

    create_embedding!(tenant_schema, first_message.id, [0.4, 0.5, 0.6])
    create_embedding!(tenant_schema, second_message.id, [0.1, 0.2, 0.3])
  end

  defp create_actor!(tenant_schema, handle) do
    Actor
    |> Ash.Changeset.for_create(
      :create,
      %{platform: "discord", handle: handle, display_name: String.capitalize(handle)},
      tenant: tenant_schema
    )
    |> Ash.create!()
  end

  defp create_channel!(tenant_schema, name) do
    Channel
    |> Ash.Changeset.for_create(:create, %{platform: "discord", name: name},
      tenant: tenant_schema
    )
    |> Ash.create!()
  end

  defp create_message!(tenant_schema, actor_id, channel_id, body) do
    Message
    |> Ash.Changeset.for_create(
      :create,
      %{
        external_id: Ecto.UUID.generate(),
        body: body,
        observed_at: DateTime.utc_now(),
        raw: %{"body" => body},
        metadata: %{},
        actor_id: actor_id,
        channel_id: channel_id
      },
      tenant: tenant_schema
    )
    |> Ash.create!()
  end

  defp create_embedding!(tenant_schema, message_id, embedding) do
    MessageEmbedding
    |> Ash.Changeset.for_create(
      :create,
      %{
        model: "test-embedding-model",
        dimensions: length(embedding),
        embedding: embedding,
        metadata: %{},
        message_id: message_id
      },
      tenant: tenant_schema
    )
    |> Ash.create!()
  end
end
