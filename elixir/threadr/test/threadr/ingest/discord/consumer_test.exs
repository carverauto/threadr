defmodule Threadr.Ingest.Discord.ConsumerTest do
  use ExUnit.Case, async: true

  alias Nostrum.Struct.Channel
  alias Nostrum.Struct.Event.Ready

  alias Nostrum.Struct.Event.{
    MessageReactionAdd,
    MessageReactionRemoveAll,
    MessageReactionRemoveEmoji,
    ThreadListSync,
    ThreadMembersUpdate
  }

  alias Nostrum.Struct.Emoji
  alias Nostrum.Struct.{Message, ThreadMember, User}
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
    assert envelope.data.metadata["platform_message_id"] == "999888777"
    assert envelope.data.metadata["platform_channel_id"] == "12345"
    assert envelope.data.metadata["platform_guild_id"] == "54321"
    assert envelope.data.metadata["platform_actor_id"] == "1"
    assert envelope.data.metadata["observed_handle"] == "alice"
    assert envelope.data.metadata["observed_display_name"] == "Alice Display"
    assert envelope.data.metadata["conversation_external_id"] == "12345"
    assert envelope.data.metadata["mentioned_handles"] == ["bob", "Carol Display"]
    assert envelope.data.metadata["mentioned_actor_ids"] == ["2", "3"]

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
    assert envelope.data.metadata["platform_actor_id"] == "1"
  end

  test "publishes Discord message edit context events" do
    observed_at = ~U[2026-03-06 03:20:00Z]

    Consumer.put_config(
      tenant_subject_name: "acme-threat-intel",
      channels: ["12345"],
      publisher: {Threadr.TestPublisher, self()}
    )

    :ok =
      Consumer.handle_event(
        {:MESSAGE_UPDATE,
         %Message{
           id: 999_888_777,
           channel_id: 12_345,
           guild_id: 54_321,
           content: "edited hello @bob",
           edited_timestamp: observed_at,
           author: %User{
             id: 1,
             username: "alice",
             global_name: "Alice Display",
             bot: false
           }
         }, nil}
      )

    assert_receive {:published_envelope, envelope}
    assert envelope.type == "chat.context"
    assert envelope.id == "999888777:edit"
    assert envelope.data.event_type == "message_edit"
    assert envelope.data.channel == "12345"
    assert envelope.data.actor == "Alice Display"
    assert envelope.data.metadata["source_message_external_id"] == "999888777"
    assert envelope.data.metadata["observed_handle"] == "alice"
    assert envelope.data.raw["content"] == "edited hello @bob"
  end

  test "publishes Discord reaction context events" do
    Consumer.put_config(
      tenant_subject_name: "acme-threat-intel",
      channels: ["12345"],
      publisher: {Threadr.TestPublisher, self()}
    )

    :ok =
      Consumer.handle_event(
        {:MESSAGE_REACTION_ADD,
         %MessageReactionAdd{
           user_id: 1,
           channel_id: 12_345,
           message_id: 999_888_777,
           guild_id: 54_321,
           member: %{nick: "Alice Display"},
           emoji: %Emoji{id: 55, name: "shipit", animated: false}
         }, nil}
      )

    assert_receive {:published_envelope, envelope}
    assert envelope.type == "chat.context"
    assert envelope.data.event_type == "reaction_add"
    assert envelope.data.channel == "12345"
    assert envelope.data.actor == "Alice Display"
    assert envelope.data.metadata["source_message_external_id"] == "999888777"
    assert envelope.data.metadata["platform_actor_id"] == "1"
    assert envelope.data.metadata["emoji"]["api_name"] == "shipit:55"

    :ok =
      Consumer.handle_event(
        {:MESSAGE_REACTION_REMOVE_ALL,
         %MessageReactionRemoveAll{
           channel_id: 12_345,
           message_id: 999_888_777,
           guild_id: 54_321
         }, nil}
      )

    assert_receive {:published_envelope, remove_all_envelope}
    assert remove_all_envelope.data.event_type == "reaction_remove_all"
    assert remove_all_envelope.data.actor == nil

    :ok =
      Consumer.handle_event(
        {:MESSAGE_REACTION_REMOVE_EMOJI,
         %MessageReactionRemoveEmoji{
           channel_id: 12_345,
           message_id: 999_888_777,
           guild_id: 54_321,
           emoji: %Emoji{name: "wave"}
         }, nil}
      )

    assert_receive {:published_envelope, remove_emoji_envelope}
    assert remove_emoji_envelope.data.event_type == "reaction_remove_emoji"
    assert remove_emoji_envelope.data.metadata["emoji"]["api_name"] == "wave"
  end

  test "publishes Discord thread lifecycle context events" do
    Consumer.put_config(
      tenant_subject_name: "acme-threat-intel",
      channels: ["12345"],
      publisher: {Threadr.TestPublisher, self()}
    )

    thread =
      %Channel{
        id: 77_777,
        guild_id: 54_321,
        parent_id: 12_345,
        owner_id: 1,
        name: "incident-bridge",
        type: 11,
        thread_metadata: %{archived: false, locked: false, auto_archive_duration: 60}
      }

    :ok = Consumer.handle_event({:THREAD_CREATE, thread, nil})

    assert_receive {:published_envelope, create_envelope}
    assert create_envelope.type == "chat.context"
    assert create_envelope.data.event_type == "thread_create"
    assert create_envelope.data.channel == "77777"
    assert create_envelope.data.metadata["thread_external_id"] == "77777"
    assert create_envelope.data.metadata["parent_channel_external_id"] == "12345"
    assert create_envelope.data.metadata["thread_state"]["auto_archive_duration"] == 60

    updated_thread = %{thread | thread_metadata: %{archived: true, locked: true}}

    :ok = Consumer.handle_event({:THREAD_UPDATE, {thread, updated_thread}, nil})

    assert_receive {:published_envelope, update_envelope}
    assert update_envelope.data.event_type == "thread_update"
    assert update_envelope.data.metadata["thread_state"]["archived"] == true
    assert update_envelope.data.metadata["thread_state"]["locked"] == true

    :ok = Consumer.handle_event({:THREAD_DELETE, thread, nil})

    assert_receive {:published_envelope, delete_envelope}
    assert delete_envelope.data.event_type == "thread_delete"
  end

  test "publishes Discord thread membership context events" do
    joined_at = ~U[2026-03-08 14:10:00Z]

    Consumer.put_config(
      tenant_subject_name: "acme-threat-intel",
      channels: ["77777"],
      publisher: {Threadr.TestPublisher, self()}
    )

    :ok =
      Consumer.handle_event(
        {:THREAD_MEMBER_UPDATE,
         %ThreadMember{
           id: 77_777,
           guild_id: 54_321,
           user_id: 1,
           join_timestamp: joined_at,
           flags: 0
         }, nil}
      )

    assert_receive {:published_envelope, member_envelope}
    assert member_envelope.type == "chat.context"
    assert member_envelope.data.event_type == "thread_member_update"
    assert member_envelope.data.channel == "77777"
    assert member_envelope.data.actor == nil
    assert member_envelope.data.metadata["thread_external_id"] == "77777"
    assert member_envelope.data.metadata["platform_actor_id"] == "1"
    assert member_envelope.data.metadata["member_joined_at"] == "2026-03-08T14:10:00Z"

    :ok =
      Consumer.handle_event(
        {:THREAD_MEMBERS_UPDATE,
         %ThreadMembersUpdate{
           id: 77_777,
           guild_id: 54_321,
           member_count: 2,
           added_members: [
             %ThreadMember{
               id: 77_777,
               user_id: 3,
               join_timestamp: joined_at,
               flags: 1
             }
           ],
           removed_member_ids: [9]
         }, nil}
      )

    assert_receive {:published_envelope, members_envelope}
    assert members_envelope.type == "chat.context"
    assert members_envelope.data.event_type == "thread_members_update"
    assert members_envelope.data.channel == "77777"
    assert members_envelope.data.metadata["member_count"] == 2
    assert members_envelope.data.metadata["added_member_ids"] == ["3"]
    assert members_envelope.data.metadata["removed_member_ids"] == ["9"]
    assert hd(members_envelope.data.metadata["added_members"])["member_flags"] == 1
  end

  test "publishes Discord thread sync context events" do
    joined_at = ~U[2026-03-08 14:15:00Z]

    Consumer.put_config(
      tenant_subject_name: "acme-threat-intel",
      channels: ["12345"],
      publisher: {Threadr.TestPublisher, self()}
    )

    :ok =
      Consumer.handle_event(
        {:THREAD_LIST_SYNC,
         %ThreadListSync{
           guild_id: 54_321,
           channel_ids: [12_345],
           threads: [
             %Channel{
               id: 77_777,
               guild_id: 54_321,
               parent_id: 12_345,
               owner_id: 1,
               name: "incident-bridge",
               type: 11,
               thread_metadata: %{archived: false, locked: false}
             }
           ],
           members: [
             %ThreadMember{
               id: 77_777,
               user_id: 1,
               join_timestamp: joined_at,
               flags: 0
             }
           ]
         }, nil}
      )

    assert_receive {:published_envelope, envelope}
    assert envelope.type == "chat.context"
    assert envelope.data.event_type == "thread_list_sync"
    assert envelope.data.channel == "12345"
    assert envelope.data.actor == nil
    assert envelope.data.metadata["platform_guild_id"] == "54321"
    assert envelope.data.metadata["thread_sync_channel_ids"] == ["12345"]
    assert envelope.data.metadata["thread_ids"] == ["77777"]
    assert envelope.data.metadata["member_thread_ids"] == ["77777"]
    assert envelope.data.metadata["member_user_ids"] == ["1"]
    assert hd(envelope.data.metadata["threads"])["parent_channel_external_id"] == "12345"
    assert hd(envelope.data.metadata["members"])["platform_actor_id"] == "1"
  end

  test "publishes Discord presence snapshots as context events" do
    Consumer.put_config(
      tenant_subject_name: "acme-threat-intel",
      publisher: {Threadr.TestPublisher, self()}
    )

    :ok =
      Consumer.handle_event(
        {:PRESENCE_UPDATE,
         {54_321, nil,
          %{
            user: %{id: 1, username: "alice", global_name: "Alice Display"},
            status: :online,
            activities: [%{name: "Incident watch", type: 0, state: "triaging"}],
            client_status: %{desktop: "online"}
          }}, nil}
      )

    assert_receive {:published_envelope, envelope}
    assert envelope.type == "chat.context"
    assert envelope.data.event_type == "presence_snapshot"
    assert envelope.data.channel == nil
    assert envelope.data.actor == "Alice Display"
    assert envelope.data.metadata["platform_guild_id"] == "54321"
    assert envelope.data.metadata["platform_actor_id"] == "1"
    assert envelope.data.metadata["observed_handle"] == "alice"
    assert envelope.data.metadata["presence_state"]["status"] == "online"
    assert hd(envelope.data.metadata["presence_state"]["activities"])["type"] == 0
    assert envelope.data.raw["client_status"]["desktop"] == "online"
  end
end
