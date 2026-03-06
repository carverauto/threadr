defmodule Threadr.IngestTest do
  use ExUnit.Case, async: true

  alias Threadr.Ingest

  test "publish_chat_message emits a normalized tenant-scoped envelope" do
    observed_at = ~U[2026-03-05 23:00:00Z]

    config = [
      tenant_subject_name: "acme-threat-intel",
      tenant_id: "tenant-123",
      bot_id: "bot-123",
      publisher: {Threadr.TestPublisher, self()}
    ]

    :ok =
      Ingest.publish_chat_message(config, %{
        platform: "discord",
        actor: "alice",
        body: "hello @bob and @carol",
        channel: "12345",
        platform_message_id: "msg-1",
        platform_channel_id: "12345",
        observed_at: observed_at,
        mentions: ["bob", "dave"],
        raw: %{"guild_id" => "guild-1"},
        external_id: "discord-1"
      })

    assert_receive {:published_envelope, envelope}

    assert envelope.id == "discord-1"
    assert envelope.type == "chat.message"
    assert envelope.source == "threadr.ingest.discord"

    assert envelope.subject ==
             "threadr.tenants.acme-threat-intel.chat.message"

    assert envelope.metadata == %{
             "bot_id" => "bot-123",
             "tenant_id" => "tenant-123",
             "platform_message_id" => "msg-1",
             "platform_channel_id" => "12345"
           }

    assert envelope.data.platform == "discord"
    assert envelope.data.actor == "alice"
    assert envelope.data.channel == "12345"
    assert envelope.data.body == "hello @bob and @carol"
    assert envelope.data.observed_at == observed_at
    assert envelope.data.mentions == ["bob", "dave", "carol"]
    assert envelope.data.raw == %{"guild_id" => "guild-1"}
  end

  test "extract_mentions normalizes handles from message text" do
    assert Ingest.extract_mentions("hi @Alice and @bob.test and @bob.test") ==
             ["Alice", "bob.test"]
  end
end
