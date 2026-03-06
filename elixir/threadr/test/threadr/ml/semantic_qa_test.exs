defmodule Threadr.ML.SemanticQATest do
  use Threadr.DataCase, async: false

  alias Threadr.ControlPlane.Service
  alias Threadr.ML.SemanticQA
  alias Threadr.TenantData.{Actor, Channel, Message, MessageEmbedding}

  test "retrieves the closest tenant messages and answers against that context" do
    tenant = create_tenant!("Semantic QA")
    actor = create_actor!(tenant.schema_name, "alice")
    channel = create_channel!(tenant.schema_name, "ops")

    message_1 =
      create_message!(
        tenant.schema_name,
        actor.id,
        channel.id,
        "Alice mentioned Bob in incident response planning."
      )

    create_embedding!(
      tenant.schema_name,
      message_1.id,
      [0.4, 0.5, 0.6],
      "test-embedding-model",
      %{source: "primary"}
    )

    second_message =
      create_message!(
        tenant.schema_name,
        actor.id,
        channel.id,
        "Alice discussed malware clusters without naming anyone."
      )

    create_embedding!(tenant.schema_name, second_message.id, [0.1, 0.2, 0.3])

    assert {:ok, result} =
             SemanticQA.answer_question(
               tenant.subject_name,
               "Who did Alice mention?",
               embedding_provider: Threadr.TestEmbeddingProvider,
               embedding_model: "test-embedding-model",
               generation_provider: Threadr.TestGenerationProvider,
               generation_model: "test-chat",
               limit: 2
             )

    assert result.tenant_schema == tenant.schema_name
    assert result.query.provider == "test"
    assert result.query.model == "test-embedding-model"
    assert length(result.matches) == 2
    assert hd(result.matches).body == "Alice mentioned Bob in incident response planning."
    assert hd(result.matches).similarity > List.last(result.matches).similarity
    assert result.context =~ "[C1]"
    assert result.context =~ "#ops alice: Alice mentioned Bob in incident response planning."
    assert length(result.citations) == 2
    assert hd(result.citations).label == "C1"
    assert hd(result.citations).body == "Alice mentioned Bob in incident response planning."
    assert result.answer.provider == "test"
    assert result.answer.model == "test-chat"
    assert result.answer.metadata["context"]["question"] == "Who did Alice mention?"
    assert result.answer.content =~ "Question:"
  end

  test "returns an error when no tenant message embeddings exist" do
    tenant = create_tenant!("Semantic QA Empty")

    assert {:error, :no_message_embeddings} =
             SemanticQA.search_messages(
               tenant.subject_name,
               "Who did Alice mention?",
               embedding_provider: Threadr.TestEmbeddingProvider,
               embedding_model: "test-embedding-model"
             )
  end

  defp create_tenant!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(%{
        name: "#{prefix} #{suffix}",
        subject_name: "#{String.downcase(String.replace(prefix, " ", "-"))}-#{suffix}"
      })

    tenant
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
    |> Ash.Changeset.for_create(
      :create,
      %{platform: "discord", name: name},
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

  defp create_embedding!(
         tenant_schema,
         message_id,
         embedding,
         model \\ "test-embedding-model",
         metadata \\ %{}
       ) do
    MessageEmbedding
    |> Ash.Changeset.for_create(
      :create,
      %{
        model: model,
        dimensions: length(embedding),
        embedding: embedding,
        metadata: metadata,
        message_id: message_id
      },
      tenant: tenant_schema
    )
    |> Ash.create!()
  end
end
