defmodule Threadr.Ingest.Discord.ConsumerTest do
  use ExUnit.Case, async: true

  alias Nostrum.Struct.Event.Ready
  alias Nostrum.Struct.{Message, User}
  alias Threadr.Ingest.Discord.Consumer

  setup do
    handler_id = "discord-consumer-test-#{System.unique_integer([:positive])}"
    parent = self()

    :ok =
      :telemetry.attach_many(
        handler_id,
        [
          [:threadr, :ingest, :runtime, :ready],
          [:threadr, :ingest, :runtime, :message_received],
          [:threadr, :ingest, :runtime, :message_filtered],
          [:threadr, :ingest, :runtime, :message_published]
        ],
        fn event, _measurements, metadata, pid ->
          send(pid, {:telemetry_event, event, metadata})
        end,
        parent
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  test "emits a ready runtime signal when Discord reaches READY" do
    Consumer.put_config(
      tenant_subject_name: "acme-threat-intel",
      tenant_id: "tenant-123",
      bot_id: "bot-123"
    )

    :ok =
      Consumer.handle_event(
        {:READY,
         %Ready{
           guilds: [%{id: 1}, %{id: 2}],
           shard: {0, 1}
         }, nil}
      )

    assert_receive {:telemetry_event, [:threadr, :ingest, :runtime, :ready], metadata}
    assert metadata.platform == "discord"
    assert metadata.tenant_subject_name == "acme-threat-intel"
    assert metadata.tenant_id == "tenant-123"
    assert metadata.bot_id == "bot-123"
    assert metadata.guild_count == 2
    assert metadata.shard == {0, 1}
  end

  test "publishes normalized tenant-scoped chat events for Discord messages" do
    observed_at = ~U[2026-03-06 03:15:00Z]

    Consumer.put_config(
      tenant_subject_name: "acme-threat-intel",
      tenant_id: "tenant-123",
      bot_id: "bot-123",
      channels: ["12345"],
      publisher: {Threadr.TestPublisher, self()}
    )

    :ok =
      Consumer.handle_event(
        {:MESSAGE_CREATE,
         %Message{
           id: 999_888_777,
           channel_id: 12_345,
           guild_id: 54_321,
           content: "hello @bob",
           timestamp: observed_at,
           author: %User{
             id: 1,
             username: "alice",
             global_name: "Alice Display",
             bot: false
           },
           mentions: [
             %User{id: 2, username: "bob", global_name: nil},
             %User{id: 3, username: "carol", global_name: "Carol Display"}
           ]
         }, nil}
      )

    assert_receive {:published_envelope, envelope}
    assert envelope.id == "999888777"
    assert envelope.source == "threadr.ingest.discord"
    assert envelope.subject == "threadr.tenants.acme-threat-intel.chat.message"

    assert envelope.metadata == %{
             "bot_id" => "bot-123",
             "tenant_id" => "tenant-123",
             "platform_message_id" => "999888777",
             "platform_channel_id" => "12345"
           }

    assert envelope.data.platform == "discord"
    assert envelope.data.actor == "Alice Display"
    assert envelope.data.channel == "12345"
    assert envelope.data.body == "hello @bob"
    assert envelope.data.observed_at == observed_at
    assert envelope.data.mentions == ["bob", "Carol Display"]

    assert envelope.data.raw == %{
             "message_id" => "999888777",
             "channel_id" => "12345",
             "guild_id" => "54321"
           }

    assert_receive {:telemetry_event, [:threadr, :ingest, :runtime, :message_received], metadata}
    assert metadata.channel_id == "12345"
    assert metadata.guild_id == "54321"
    assert metadata.author_bot == false
    assert metadata.content_present == true

    assert_receive {:telemetry_event, [:threadr, :ingest, :runtime, :message_published], metadata}
    assert metadata.channel_id == "12345"
  end

  test "ignores Discord messages from channels outside the configured allowlist" do
    Consumer.put_config(
      tenant_subject_name: "acme-threat-intel",
      channels: ["12345"],
      publisher: {Threadr.TestPublisher, self()}
    )

    :ok =
      Consumer.handle_event(
        {:MESSAGE_CREATE,
         %Message{
           id: 111,
           channel_id: 99_999,
           content: "hello",
           author: %User{id: 1, username: "alice", bot: false},
           mentions: []
         }, nil}
      )

    refute_receive {:published_envelope, _envelope}, 200
    assert_receive {:telemetry_event, [:threadr, :ingest, :runtime, :message_filtered], metadata}
    assert metadata.reason == "channel_not_allowed"
  end

  test "publishes bot-authored Discord messages when explicitly enabled" do
    Consumer.put_config(
      tenant_subject_name: "acme-threat-intel",
      channels: ["12345"],
      discord: %{allow_bot_messages: true},
      publisher: {Threadr.TestPublisher, self()}
    )

    :ok =
      Consumer.handle_event(
        {:MESSAGE_CREATE,
         %Message{
           id: 222,
           channel_id: 12_345,
           content: "smoke from bot",
           author: %User{id: 1, username: "threadr-bot", bot: true},
           mentions: []
         }, nil}
      )

    assert_receive {:published_envelope, envelope}
    assert envelope.id == "222"
    assert envelope.data.body == "smoke from bot"
  end
end
