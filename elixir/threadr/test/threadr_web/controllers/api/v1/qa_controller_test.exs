defmodule ThreadrWeb.Api.V1.QaControllerTest do
  use ThreadrWeb.ConnCase, async: false

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

  test "POST /api/v1/tenants/:subject_name/qa/search requires authentication", %{conn: conn} do
    conn =
      post(conn, ~p"/api/v1/tenants/acme/qa/search", %{"question" => "Who did Alice mention?"})

    assert json_response(conn, 401) == %{"errors" => %{"detail" => "Unauthorized"}}
  end

  test "POST /api/v1/tenants/:subject_name/qa/search returns ranked tenant matches", %{conn: conn} do
    owner = create_user!("owner")
    tenant = create_tenant!("QA Owned", owner)
    seed_semantic_data!(tenant.schema_name)

    conn =
      conn
      |> api_key_conn(owner)
      |> post(~p"/api/v1/tenants/#{tenant.subject_name}/qa/search", %{
        "question" => "Who did Alice mention?",
        "limit" => 2
      })

    assert %{"data" => data} = json_response(conn, 200)
    assert data["tenant_subject_name"] == tenant.subject_name
    assert data["query"]["provider"] == "test"
    assert length(data["matches"]) == 2
    assert length(data["citations"]) == 2
    assert hd(data["citations"])["label"] == "C1"
    assert hd(data["matches"])["body"] == "Alice mentioned Bob in incident response planning."
    assert hd(data["matches"])["similarity"] > List.last(data["matches"])["similarity"]
    assert data["context"] =~ "[C1]"
    assert data["context"] =~ "#ops alice: Alice mentioned Bob in incident response planning."
  end

  test "POST /api/v1/tenants/:subject_name/qa/answer returns an answer grounded in tenant context",
       %{conn: conn} do
    owner = create_user!("owner")
    tenant = create_tenant!("QA Owned", owner)
    seed_semantic_data!(tenant.schema_name)

    conn =
      conn
      |> api_key_conn(owner)
      |> post(~p"/api/v1/tenants/#{tenant.subject_name}/qa/answer", %{
        "question" => "Who did Alice mention?"
      })

    assert %{"data" => data} = json_response(conn, 200)
    assert data["tenant_subject_name"] == tenant.subject_name
    assert data["answer"]["provider"] == "test"
    assert data["answer"]["model"] == "test-llm"
    assert data["answer"]["metadata"]["context"]["question"] == "Who did Alice mention?"
    assert hd(data["citations"])["label"] == "C1"
    assert data["answer"]["content"] =~ "Question:"
  end

  test "POST /api/v1/tenants/:subject_name/qa/answer returns 422 when no embeddings exist", %{
    conn: conn
  } do
    owner = create_user!("owner")
    tenant = create_tenant!("QA Empty", owner)

    conn =
      conn
      |> api_key_conn(owner)
      |> post(~p"/api/v1/tenants/#{tenant.subject_name}/qa/answer", %{
        "question" => "Who did Alice mention?"
      })

    assert json_response(conn, 422) == %{
             "errors" => %{"detail" => "No tenant message embeddings available"}
           }
  end

  defp api_key_conn(conn, user) do
    {:ok, _api_key, plaintext_api_key} = Service.create_api_key(user, %{name: "CLI"})

    conn
    |> put_req_header("authorization", "Bearer #{plaintext_api_key}")
    |> put_req_header("accept", "application/json")
  end

  defp create_user!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      ControlPlane.register_user(%{
        email: "#{prefix}-#{suffix}@example.com",
        name: "User #{suffix}",
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
          subject_name: "#{String.downcase(String.replace(prefix, " ", "-"))}-#{suffix}"
        },
        owner_user: owner
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
