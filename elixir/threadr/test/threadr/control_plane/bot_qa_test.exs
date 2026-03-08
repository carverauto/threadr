defmodule Threadr.ControlPlane.BotQATest do
  use Threadr.DataCase, async: false

  alias Threadr.ControlPlane.Service
  alias Threadr.TenantData.{Actor, Channel, Message, MessageEmbedding}

  test "answers tenant questions for bot runtimes with tenant-scoped QA" do
    tenant = create_tenant!("Bot QA")
    actor = create_actor!(tenant.schema_name, "alice")
    channel = create_channel!(tenant.schema_name, "ops")

    message =
      create_message!(
        tenant.schema_name,
        actor.id,
        channel.id,
        "Alice and Bob discussed endpoint isolation last week."
      )

    create_embedding!(tenant.schema_name, message.id, [0.4, 0.5, 0.6], "test-embedding-model")

    assert {:ok, result} =
             Service.answer_tenant_question_for_bot(
               tenant.subject_name,
               "What did Alice and Bob talk about last week?",
               embedding_provider: Threadr.TestEmbeddingProvider,
               embedding_model: "test-embedding-model",
               generation_provider: Threadr.TestGenerationProvider,
               generation_model: "test-chat",
               limit: 1
             )

    assert result.mode in [:graph_rag, :semantic_qa]
    assert result.answer.content =~ "What did Alice and Bob talk about last week?"
  end

  test "returns insufficient context when no embeddings exist" do
    tenant = create_tenant!("Bot QA Empty")

    assert {:error, :no_message_embeddings} =
             Service.answer_tenant_question_for_bot(
               tenant.subject_name,
               "What happened?",
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
      %{platform: "irc", handle: handle, display_name: String.capitalize(handle)},
      tenant: tenant_schema
    )
    |> Ash.create!()
  end

  defp create_channel!(tenant_schema, name) do
    Channel
    |> Ash.Changeset.for_create(
      :create,
      %{platform: "irc", name: name},
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

  defp create_embedding!(tenant_schema, message_id, embedding, model) do
    MessageEmbedding
    |> Ash.Changeset.for_create(
      :create,
      %{
        model: model,
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
