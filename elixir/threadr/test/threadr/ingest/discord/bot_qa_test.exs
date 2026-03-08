defmodule Threadr.Ingest.Discord.BotQATest do
  use Threadr.DataCase, async: false

  alias Nostrum.Struct.{Message, User}
  alias Threadr.ControlPlane.Service
  alias Threadr.Ingest.Discord.Consumer
  alias Threadr.TenantData.{Actor, Channel, MessageEmbedding}
  alias Threadr.TenantData.Message, as: TenantMessage

  test "replies when a Discord message directly mentions the bot" do
    tenant = create_tenant!("Discord Bot QA")
    actor = create_actor!(tenant.schema_name, "alice")
    channel = create_channel!(tenant.schema_name, "12345")

    message =
      create_message!(
        tenant.schema_name,
        actor.id,
        channel.id,
        "Alice and Bob discussed endpoint isolation last week."
      )

    create_embedding!(tenant.schema_name, message.id, [0.4, 0.5, 0.6])

    Consumer.put_config(
      tenant_subject_name: tenant.subject_name,
      tenant_id: tenant.id,
      bot_id: "bot-123",
      channels: ["12345"],
      publisher: {Threadr.TestPublisher, self()},
      discord_api: {Threadr.TestDiscordApi, self()},
      embedding_provider: Threadr.TestEmbeddingProvider,
      embedding_model: "test-embedding-model",
      generation_provider: Threadr.TestGenerationProvider,
      generation_model: "test-chat",
      discord: %{
        identity: %{
          user_id: "999",
          username: "threadr",
          global_name: "Threadr"
        }
      }
    )

    :ok =
      Consumer.handle_event(
        {:MESSAGE_CREATE,
         %Message{
           id: 999_888_777,
           channel_id: 12_345,
           guild_id: 54_321,
           content: "<@999> what did Alice and Bob talk about last week?",
           author: %User{
             id: 1,
             username: "alice",
             global_name: "Alice Display",
             bot: false
           },
           mentions: [%User{id: 999, username: "threadr", global_name: "Threadr"}]
         }, nil}
      )

    assert_receive {:published_envelope, _envelope}
    assert_receive {:discord_api_create_message, "12345", %{content: content}}
    assert content =~ "<@1>"
    assert content =~ "what did Alice and Bob talk about last week?"
  end

  test "does not reply to Discord messages that do not address the bot" do
    tenant = create_tenant!("Discord Bot QA Idle")

    Consumer.put_config(
      tenant_subject_name: tenant.subject_name,
      channels: ["12345"],
      publisher: {Threadr.TestPublisher, self()},
      discord_api: {Threadr.TestDiscordApi, self()},
      discord: %{
        identity: %{
          user_id: "999",
          username: "threadr",
          global_name: "Threadr"
        }
      }
    )

    :ok =
      Consumer.handle_event(
        {:MESSAGE_CREATE,
         %Message{
           id: 111,
           channel_id: 12_345,
           content: "what did Alice and Bob talk about last week?",
           author: %User{id: 1, username: "alice", bot: false},
           mentions: []
         }, nil}
      )

    assert_receive {:published_envelope, _envelope}
    refute_receive {:discord_api_create_message, _channel_id, _options}, 200
  end

  defp create_tenant!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(%{
        name: "#{prefix} #{suffix}",
        subject_name: "discord-bot-qa-#{suffix}"
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
    TenantMessage
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
