defmodule Threadr.Ingest.Discord.Consumer do
  @moduledoc """
  Nostrum consumer that normalizes Discord messages into Threadr chat events.
  """

  use Nostrum.Consumer

  alias Nostrum.Struct.Channel

  alias Nostrum.Struct.Event.{
    MessageReactionAdd,
    MessageReactionRemove,
    MessageReactionRemoveAll,
    MessageReactionRemoveEmoji,
    ThreadListSync,
    ThreadMembersUpdate
  }

  alias Nostrum.Struct.Message
  alias Nostrum.Struct.Emoji
  alias Nostrum.Struct.ThreadMember
  alias Threadr.Ingest.BotQA
  alias Threadr.Ingest

  @config_key {__MODULE__, :config}

  def put_config(config) do
    :persistent_term.put(@config_key, config)
  end

  @impl true
  def handle_event({:READY, ready, _ws_state}) do
    config =
      @config_key
      |> :persistent_term.get([])
      |> BotQA.with_discord_identity(ready.user)

    put_config(config)

    Threadr.Ingest.emit_runtime_event(config, :ready, %{
      platform: "discord",
      guild_count: ready.guilds |> List.wrap() |> length(),
      shard: ready.shard
    })

    :ok
  end

  @impl true
  def handle_event({:MESSAGE_CREATE, %Message{} = message, _ws_state}) do
    config = :persistent_term.get(@config_key, [])
    metadata = message_metadata(message)

    Ingest.emit_runtime_event(config, :message_received, metadata)

    cond do
      ignored_author?(message) ->
        Ingest.emit_runtime_event(
          config,
          :message_filtered,
          Map.put(metadata, :reason, "ignored_author")
        )

        :ok

      blank?(message.content) ->
        Ingest.emit_runtime_event(
          config,
          :message_filtered,
          Map.put(metadata, :reason, "blank_content")
        )

        :ok

      not Ingest.channel_allowed?(config[:channels], Integer.to_string(message.channel_id)) ->
        Ingest.emit_runtime_event(
          config,
          :message_filtered,
          Map.put(metadata, :reason, "channel_not_allowed")
        )

        :ok

      true ->
        normalized_metadata = normalized_message_metadata(message)

        :ok =
          Ingest.publish_chat_message(config, %{
            platform: "discord",
            actor: actor_handle(message),
            body: message.content,
            channel: Integer.to_string(message.channel_id),
            platform_channel_id: Integer.to_string(message.channel_id),
            platform_message_id: to_string(message.id),
            observed_at: message.timestamp || DateTime.utc_now(),
            mentions: mention_handles(message),
            metadata: normalized_metadata,
            raw: %{
              "message_id" => to_string(message.id),
              "channel_id" => Integer.to_string(message.channel_id),
              "guild_id" => stringify(message.guild_id)
            },
            external_id: to_string(message.id)
          })

        Ingest.emit_runtime_event(config, :message_published, metadata)

        :ok =
          BotQA.maybe_answer_discord(config, %{
            actor: actor_handle(message),
            actor_id: message.author.id,
            body: message.content,
            channel_id: Integer.to_string(message.channel_id),
            platform_message_id: to_string(message.id)
          })
    end
  end

  @impl true
  def handle_event({:MESSAGE_UPDATE, %Message{} = message, _ws_state}) do
    config = :persistent_term.get(@config_key, [])

    if Ingest.channel_allowed?(config[:channels], Integer.to_string(message.channel_id)) do
      Ingest.publish_context_event(config, %{
        platform: "discord",
        event_type: "message_edit",
        channel: Integer.to_string(message.channel_id),
        actor: actor_handle_or_nil(message),
        observed_at: Map.get(message, :edited_timestamp) || DateTime.utc_now(),
        external_id: "#{message.id}:edit",
        platform_channel_id: Integer.to_string(message.channel_id),
        platform_message_id: stringify(message.id),
        metadata:
          normalized_message_metadata(message)
          |> Map.put("source_message_external_id", stringify(message.id)),
        raw: %{
          "message_id" => stringify(message.id),
          "channel_id" => Integer.to_string(message.channel_id),
          "guild_id" => stringify(message.guild_id),
          "content" => Map.get(message, :content)
        }
      })
    else
      :ok
    end
  end

  @impl true
  def handle_event({:MESSAGE_DELETE, message, _ws_state}) do
    config = :persistent_term.get(@config_key, [])
    channel_id = stringify(Map.get(message, :channel_id))

    if Ingest.channel_allowed?(config[:channels], channel_id) do
      Ingest.publish_context_event(config, %{
        platform: "discord",
        event_type: "message_delete",
        channel: channel_id,
        observed_at: DateTime.utc_now(),
        external_id: "#{stringify(Map.get(message, :id))}:delete",
        platform_channel_id: channel_id,
        platform_message_id: stringify(Map.get(message, :id)),
        metadata: %{
          "source_message_external_id" => stringify(Map.get(message, :id)),
          "platform_channel_id" => channel_id,
          "platform_guild_id" => stringify(Map.get(message, :guild_id))
        },
        raw: %{
          "message_id" => stringify(Map.get(message, :id)),
          "channel_id" => channel_id,
          "guild_id" => stringify(Map.get(message, :guild_id))
        }
      })
    else
      :ok
    end
  end

  @impl true
  def handle_event({:MESSAGE_REACTION_ADD, %MessageReactionAdd{} = reaction, _ws_state}) do
    publish_reaction_context_event(reaction, "reaction_add")
  end

  @impl true
  def handle_event({:MESSAGE_REACTION_REMOVE, %MessageReactionRemove{} = reaction, _ws_state}) do
    publish_reaction_context_event(reaction, "reaction_remove")
  end

  @impl true
  def handle_event(
        {:MESSAGE_REACTION_REMOVE_ALL, %MessageReactionRemoveAll{} = reaction, _ws_state}
      ) do
    publish_reaction_context_event(reaction, "reaction_remove_all")
  end

  @impl true
  def handle_event(
        {:MESSAGE_REACTION_REMOVE_EMOJI, %MessageReactionRemoveEmoji{} = reaction, _ws_state}
      ) do
    publish_reaction_context_event(reaction, "reaction_remove_emoji")
  end

  @impl true
  def handle_event({:THREAD_CREATE, %Channel{} = thread, _ws_state}) do
    publish_thread_context_event(thread, "thread_create")
  end

  @impl true
  def handle_event({:THREAD_UPDATE, {_old_thread, %Channel{} = thread}, _ws_state}) do
    publish_thread_context_event(thread, "thread_update")
  end

  @impl true
  def handle_event({:THREAD_DELETE, %Channel{} = thread, _ws_state}) do
    publish_thread_context_event(thread, "thread_delete")
  end

  @impl true
  def handle_event({:THREAD_DELETE, :noop, _ws_state}) do
    :ok
  end

  @impl true
  def handle_event({:THREAD_MEMBER_UPDATE, %ThreadMember{} = member, _ws_state}) do
    publish_thread_member_context_event(member)
  end

  @impl true
  def handle_event({:THREAD_MEMBERS_UPDATE, %ThreadMembersUpdate{} = update, _ws_state}) do
    publish_thread_members_context_event(update)
  end

  @impl true
  def handle_event({:THREAD_LIST_SYNC, %ThreadListSync{} = sync, _ws_state}) do
    publish_thread_list_sync_context_event(sync)
  end

  @impl true
  def handle_event({:PRESENCE_UPDATE, {guild_id, _old_presence, new_presence}, _ws_state}) do
    publish_presence_context_event(guild_id, new_presence)
  end

  def handle_event(_event), do: :ok

  defp actor_handle(message) do
    Map.get(message.author, :global_name) || message.author.username
  end

  defp actor_handle_or_nil(message) do
    case Map.get(message, :author) do
      nil -> nil
      author -> Map.get(author, :global_name) || Map.get(author, :username)
    end
  end

  defp mention_handles(message) do
    message.mentions
    |> List.wrap()
    |> Enum.map(fn mention ->
      Map.get(mention, :global_name) || mention.username
    end)
    |> Ingest.normalize_mentions()
  end

  defp ignored_author?(message) do
    config = :persistent_term.get(@config_key, [])
    discord_config = Keyword.get(config, :discord, %{})
    allow_bot_messages = Map.get(discord_config, :allow_bot_messages, false)

    author_bot?(message) and not allow_bot_messages
  end

  defp message_metadata(message) do
    %{
      platform: "discord",
      channel_id: Integer.to_string(message.channel_id),
      guild_id: stringify(message.guild_id),
      author_bot: author_bot?(message),
      content_present: not blank?(message.content)
    }
  end

  defp author_bot?(message) do
    Map.get(message.author || %{}, :bot) == true
  end

  defp normalized_message_metadata(message) do
    %{
      "platform_message_id" => to_string(message.id),
      "platform_channel_id" => Integer.to_string(message.channel_id),
      "platform_guild_id" => stringify(message.guild_id),
      "platform_actor_id" => stringify(Map.get(message.author || %{}, :id)),
      "observed_handle" => Map.get(message.author || %{}, :username),
      "observed_display_name" => actor_handle_or_nil(message),
      "reply_to_external_id" => referenced_message_id(message),
      "thread_external_id" => thread_external_id(message),
      "conversation_external_id" => conversation_external_id(message),
      "mentioned_handles" => mention_handles(message),
      "mentioned_actor_ids" => mention_ids(message),
      "edited_at" => stringify_datetime(Map.get(message, :edited_timestamp))
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, [], ""] end)
    |> Map.new()
  end

  defp referenced_message_id(message) do
    case Map.get(message, :message_reference) do
      %{message_id: id} -> stringify(id)
      %{"message_id" => id} -> stringify(id)
      _ -> nil
    end
  end

  defp thread_external_id(message) do
    case Map.get(message, :thread) do
      %{id: id} -> stringify(id)
      %{"id" => id} -> stringify(id)
      _ -> nil
    end
  end

  defp conversation_external_id(message) do
    thread_external_id(message) || Integer.to_string(message.channel_id)
  end

  defp mention_ids(message) do
    message.mentions
    |> List.wrap()
    |> Enum.map(fn mention -> stringify(Map.get(mention, :id)) end)
    |> Enum.reject(&is_nil/1)
  end

  defp publish_reaction_context_event(reaction, event_type) do
    config = :persistent_term.get(@config_key, [])
    channel_id = stringify(Map.get(reaction, :channel_id))

    if Ingest.channel_allowed?(config[:channels], channel_id) do
      Ingest.publish_context_event(config, %{
        platform: "discord",
        event_type: event_type,
        channel: channel_id,
        actor: reaction_actor_handle(reaction),
        observed_at: DateTime.utc_now(),
        external_id:
          "#{stringify(Map.get(reaction, :message_id))}:#{event_type}:#{reaction_suffix(reaction)}",
        platform_channel_id: channel_id,
        platform_message_id: stringify(Map.get(reaction, :message_id)),
        metadata: %{
          "source_message_external_id" => stringify(Map.get(reaction, :message_id)),
          "platform_channel_id" => channel_id,
          "platform_guild_id" => stringify(Map.get(reaction, :guild_id)),
          "platform_actor_id" => stringify(Map.get(reaction, :user_id)),
          "observed_display_name" => reaction_actor_handle(reaction),
          "emoji" => emoji_metadata(Map.get(reaction, :emoji))
        },
        raw: %{
          "message_id" => stringify(Map.get(reaction, :message_id)),
          "channel_id" => channel_id,
          "guild_id" => stringify(Map.get(reaction, :guild_id)),
          "user_id" => stringify(Map.get(reaction, :user_id)),
          "emoji" => emoji_metadata(Map.get(reaction, :emoji))
        }
      })
    else
      :ok
    end
  end

  defp publish_thread_context_event(%Channel{} = thread, event_type) do
    config = :persistent_term.get(@config_key, [])
    thread_id = stringify(Map.get(thread, :id))

    if thread_context_allowed?(config, thread_id, stringify(Map.get(thread, :parent_id))) do
      Ingest.publish_context_event(config, %{
        platform: "discord",
        event_type: event_type,
        channel: thread_id,
        observed_at: DateTime.utc_now(),
        external_id: "#{thread_id}:#{event_type}",
        platform_channel_id: thread_id,
        metadata: %{
          "platform_channel_id" => thread_id,
          "platform_guild_id" => stringify(Map.get(thread, :guild_id)),
          "thread_external_id" => thread_id,
          "conversation_external_id" => thread_id,
          "parent_channel_external_id" => stringify(Map.get(thread, :parent_id)),
          "owner_external_id" => stringify(Map.get(thread, :owner_id)),
          "thread_name" => Map.get(thread, :name),
          "thread_type" => Map.get(thread, :type),
          "thread_state" => thread_state_metadata(Map.get(thread, :thread_metadata))
        },
        raw: %{
          "thread_id" => thread_id,
          "guild_id" => stringify(Map.get(thread, :guild_id)),
          "parent_id" => stringify(Map.get(thread, :parent_id)),
          "owner_id" => stringify(Map.get(thread, :owner_id)),
          "name" => Map.get(thread, :name),
          "type" => Map.get(thread, :type)
        }
      })
    else
      :ok
    end
  end

  defp publish_thread_member_context_event(%ThreadMember{} = member) do
    config = :persistent_term.get(@config_key, [])
    thread_id = stringify(Map.get(member, :id))

    if thread_context_allowed?(config, thread_id, nil) do
      Ingest.publish_context_event(config, %{
        platform: "discord",
        event_type: "thread_member_update",
        channel: thread_id,
        observed_at: Map.get(member, :join_timestamp) || DateTime.utc_now(),
        external_id:
          "#{thread_id}:thread_member_update:#{thread_update_suffix([Map.get(member, :user_id)])}",
        platform_channel_id: thread_id,
        metadata: thread_member_metadata(member),
        raw: thread_member_raw(member)
      })
    else
      :ok
    end
  end

  defp publish_thread_members_context_event(%ThreadMembersUpdate{} = update) do
    config = :persistent_term.get(@config_key, [])
    thread_id = stringify(Map.get(update, :id))

    if thread_context_allowed?(config, thread_id, nil) do
      added_members = List.wrap(Map.get(update, :added_members))
      removed_member_ids = stringify_ids(Map.get(update, :removed_member_ids))

      Ingest.publish_context_event(config, %{
        platform: "discord",
        event_type: "thread_members_update",
        channel: thread_id,
        observed_at: DateTime.utc_now(),
        external_id:
          "#{thread_id}:thread_members_update:#{thread_update_suffix(added_members ++ removed_member_ids)}",
        platform_channel_id: thread_id,
        metadata: thread_members_metadata(update),
        raw: thread_members_raw(update)
      })
    else
      :ok
    end
  end

  defp publish_thread_list_sync_context_event(%ThreadListSync{} = sync) do
    config = :persistent_term.get(@config_key, [])

    if thread_list_sync_allowed?(config, sync) do
      channel_id = thread_list_sync_channel(sync)
      thread_ids = thread_ids(Map.get(sync, :threads))
      member_thread_ids = thread_member_ids(Map.get(sync, :members))

      Ingest.publish_context_event(config, %{
        platform: "discord",
        event_type: "thread_list_sync",
        channel: channel_id,
        observed_at: DateTime.utc_now(),
        external_id:
          "#{stringify(Map.get(sync, :guild_id))}:thread_list_sync:#{thread_update_suffix(thread_ids ++ member_thread_ids)}",
        platform_channel_id: channel_id,
        metadata: thread_list_sync_metadata(sync),
        raw: thread_list_sync_raw(sync)
      })
    else
      :ok
    end
  end

  defp publish_presence_context_event(guild_id, new_presence) when is_map(new_presence) do
    config = :persistent_term.get(@config_key, [])
    user = Map.get(new_presence, :user) || %{}
    actor = Map.get(user, :global_name) || Map.get(user, :username)
    user_id = stringify(Map.get(user, :id))
    status = presence_status(Map.get(new_presence, :status))

    Ingest.publish_context_event(config, %{
      platform: "discord",
      event_type: "presence_snapshot",
      actor: actor,
      observed_at: DateTime.utc_now(),
      external_id: "#{stringify(guild_id)}:presence_snapshot:#{presence_suffix(user_id, status)}",
      metadata: presence_metadata(guild_id, new_presence),
      raw: presence_raw(guild_id, new_presence)
    })
  end

  defp thread_context_allowed?(config, thread_id, parent_channel_id) do
    configured_channels = List.wrap(config[:channels])

    Ingest.channel_allowed?(configured_channels, thread_id) or
      (not is_nil(parent_channel_id) and
         Ingest.channel_allowed?(configured_channels, parent_channel_id))
  end

  defp thread_list_sync_allowed?(config, %ThreadListSync{} = sync) do
    configured_channels = List.wrap(config[:channels])

    configured_channels == [] or
      Enum.any?(stringify_ids(Map.get(sync, :channel_ids)), fn channel_id ->
        Ingest.channel_allowed?(configured_channels, channel_id)
      end) or
      Enum.any?(List.wrap(Map.get(sync, :threads)), fn thread ->
        thread_context_allowed?(
          config,
          stringify(Map.get(thread, :id)),
          stringify(Map.get(thread, :parent_id))
        )
      end) or
      Enum.any?(thread_member_ids(Map.get(sync, :members)), fn thread_id ->
        Ingest.channel_allowed?(configured_channels, thread_id)
      end)
  end

  defp thread_member_metadata(%ThreadMember{} = member) do
    compact_map(%{
      "platform_channel_id" => stringify(Map.get(member, :id)),
      "platform_guild_id" => stringify(Map.get(member, :guild_id)),
      "thread_external_id" => stringify(Map.get(member, :id)),
      "conversation_external_id" => stringify(Map.get(member, :id)),
      "platform_actor_id" => stringify(Map.get(member, :user_id)),
      "member_joined_at" => stringify_datetime(Map.get(member, :join_timestamp)),
      "member_flags" => Map.get(member, :flags)
    })
  end

  defp thread_member_raw(%ThreadMember{} = member) do
    compact_map(%{
      "thread_id" => stringify(Map.get(member, :id)),
      "guild_id" => stringify(Map.get(member, :guild_id)),
      "user_id" => stringify(Map.get(member, :user_id)),
      "join_timestamp" => stringify_datetime(Map.get(member, :join_timestamp)),
      "flags" => Map.get(member, :flags)
    })
  end

  defp thread_members_metadata(%ThreadMembersUpdate{} = update) do
    compact_map(%{
      "platform_channel_id" => stringify(Map.get(update, :id)),
      "platform_guild_id" => stringify(Map.get(update, :guild_id)),
      "thread_external_id" => stringify(Map.get(update, :id)),
      "conversation_external_id" => stringify(Map.get(update, :id)),
      "member_count" => Map.get(update, :member_count),
      "added_member_ids" => added_member_ids(Map.get(update, :added_members)),
      "removed_member_ids" => stringify_ids(Map.get(update, :removed_member_ids)),
      "added_members" => added_members_metadata(Map.get(update, :added_members))
    })
  end

  defp thread_members_raw(%ThreadMembersUpdate{} = update) do
    compact_map(%{
      "thread_id" => stringify(Map.get(update, :id)),
      "guild_id" => stringify(Map.get(update, :guild_id)),
      "member_count" => Map.get(update, :member_count),
      "added_member_ids" => added_member_ids(Map.get(update, :added_members)),
      "removed_member_ids" => stringify_ids(Map.get(update, :removed_member_ids))
    })
  end

  defp thread_list_sync_metadata(%ThreadListSync{} = sync) do
    compact_map(%{
      "platform_channel_id" => thread_list_sync_channel(sync),
      "platform_guild_id" => stringify(Map.get(sync, :guild_id)),
      "thread_sync_channel_ids" => stringify_ids(Map.get(sync, :channel_ids)),
      "thread_ids" => thread_ids(Map.get(sync, :threads)),
      "member_thread_ids" => thread_member_ids(Map.get(sync, :members)),
      "member_user_ids" => thread_member_user_ids(Map.get(sync, :members)),
      "threads" => thread_list_sync_threads(Map.get(sync, :threads)),
      "members" => thread_list_sync_members(Map.get(sync, :members))
    })
  end

  defp thread_list_sync_raw(%ThreadListSync{} = sync) do
    compact_map(%{
      "guild_id" => stringify(Map.get(sync, :guild_id)),
      "channel_ids" => stringify_ids(Map.get(sync, :channel_ids)),
      "thread_ids" => thread_ids(Map.get(sync, :threads)),
      "member_thread_ids" => thread_member_ids(Map.get(sync, :members))
    })
  end

  defp thread_list_sync_channel(%ThreadListSync{} = sync) do
    case stringify_ids(Map.get(sync, :channel_ids)) do
      [channel_id] -> channel_id
      _ -> nil
    end
  end

  defp added_member_ids(members) do
    members
    |> List.wrap()
    |> Enum.map(fn member -> stringify(Map.get(member, :user_id)) end)
    |> Enum.reject(&is_nil/1)
  end

  defp added_members_metadata(members) do
    members
    |> List.wrap()
    |> Enum.map(fn member ->
      compact_map(%{
        "thread_external_id" => stringify(Map.get(member, :id)),
        "platform_actor_id" => stringify(Map.get(member, :user_id)),
        "member_joined_at" => stringify_datetime(Map.get(member, :join_timestamp)),
        "member_flags" => Map.get(member, :flags)
      })
    end)
  end

  defp thread_list_sync_threads(threads) do
    threads
    |> List.wrap()
    |> Enum.map(fn thread ->
      compact_map(%{
        "thread_external_id" => stringify(Map.get(thread, :id)),
        "parent_channel_external_id" => stringify(Map.get(thread, :parent_id)),
        "owner_external_id" => stringify(Map.get(thread, :owner_id)),
        "thread_name" => Map.get(thread, :name),
        "thread_type" => Map.get(thread, :type),
        "thread_state" => thread_state_metadata(Map.get(thread, :thread_metadata))
      })
    end)
  end

  defp thread_list_sync_members(members) do
    members
    |> List.wrap()
    |> Enum.map(fn member ->
      compact_map(%{
        "thread_external_id" => stringify(Map.get(member, :id)),
        "platform_actor_id" => stringify(Map.get(member, :user_id)),
        "member_joined_at" => stringify_datetime(Map.get(member, :join_timestamp)),
        "member_flags" => Map.get(member, :flags)
      })
    end)
  end

  defp thread_ids(threads) do
    threads
    |> List.wrap()
    |> Enum.map(fn thread -> stringify(Map.get(thread, :id)) end)
    |> Enum.reject(&is_nil/1)
  end

  defp thread_member_ids(members) do
    members
    |> List.wrap()
    |> Enum.map(fn member -> stringify(Map.get(member, :id)) end)
    |> Enum.reject(&is_nil/1)
  end

  defp thread_member_user_ids(members) do
    members
    |> List.wrap()
    |> Enum.map(fn member -> stringify(Map.get(member, :user_id)) end)
    |> Enum.reject(&is_nil/1)
  end

  defp stringify_ids(ids) do
    ids
    |> List.wrap()
    |> Enum.map(&stringify/1)
    |> Enum.reject(&is_nil/1)
  end

  defp thread_update_suffix(parts) do
    parts
    |> List.wrap()
    |> Enum.flat_map(fn
      %ThreadMember{} = member -> [stringify(Map.get(member, :user_id))]
      value -> [stringify(value)]
    end)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
    |> case do
      [] -> "event"
      values -> Integer.to_string(:erlang.phash2(values))
    end
  end

  defp presence_metadata(guild_id, new_presence) do
    user = Map.get(new_presence, :user) || %{}

    compact_map(%{
      "platform_guild_id" => stringify(guild_id),
      "platform_actor_id" => stringify(Map.get(user, :id)),
      "observed_handle" => Map.get(user, :username),
      "observed_display_name" => Map.get(user, :global_name) || Map.get(user, :username),
      "presence_state" => presence_state(new_presence)
    })
  end

  defp presence_raw(guild_id, new_presence) do
    compact_map(%{
      "guild_id" => stringify(guild_id),
      "user_id" => stringify(get_in(new_presence, [:user, :id])),
      "status" => presence_status(Map.get(new_presence, :status)),
      "activities" => presence_activities(Map.get(new_presence, :activities)),
      "client_status" => presence_client_status(Map.get(new_presence, :client_status))
    })
  end

  defp presence_state(new_presence) do
    compact_map(%{
      "status" => presence_status(Map.get(new_presence, :status)),
      "activities" => presence_activities(Map.get(new_presence, :activities)),
      "client_status" => presence_client_status(Map.get(new_presence, :client_status))
    })
  end

  defp presence_activities(activities) do
    activities
    |> List.wrap()
    |> Enum.map(fn activity ->
      compact_map(%{
        "name" => fetch_presence_value(activity, :name),
        "type" => fetch_presence_value(activity, :type),
        "state" => fetch_presence_value(activity, :state)
      })
    end)
  end

  defp presence_client_status(nil), do: nil

  defp presence_client_status(client_status) when is_map(client_status) do
    compact_map(%{
      "desktop" => fetch_presence_value(client_status, :desktop),
      "mobile" => fetch_presence_value(client_status, :mobile),
      "web" => fetch_presence_value(client_status, :web)
    })
  end

  defp presence_status(nil), do: nil
  defp presence_status(status) when is_atom(status), do: Atom.to_string(status)
  defp presence_status(status), do: status

  defp fetch_presence_value(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp presence_suffix(user_id, status) do
    [user_id, status]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> case do
      [] -> "event"
      parts -> Enum.join(parts, ":")
    end
  end

  defp reaction_actor_handle(%{member: %{nick: nick}}) when is_binary(nick) and nick != "",
    do: nick

  defp reaction_actor_handle(_reaction), do: nil

  defp reaction_suffix(reaction) do
    [stringify(Map.get(reaction, :user_id)), emoji_suffix(Map.get(reaction, :emoji))]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> case do
      [] -> "event"
      parts -> Enum.join(parts, ":")
    end
  end

  defp emoji_suffix(nil), do: nil
  defp emoji_suffix(%Emoji{} = emoji), do: Emoji.api_name(emoji)

  defp emoji_metadata(nil), do: nil

  defp emoji_metadata(%Emoji{} = emoji) do
    %{
      "id" => stringify(emoji.id),
      "name" => emoji.name,
      "api_name" => Emoji.api_name(emoji),
      "animated" => emoji.animated
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp thread_state_metadata(nil), do: nil

  defp thread_state_metadata(thread_metadata) when is_map(thread_metadata) do
    %{
      "archived" => fetch_thread_metadata(thread_metadata, :archived),
      "locked" => fetch_thread_metadata(thread_metadata, :locked),
      "auto_archive_duration" => fetch_thread_metadata(thread_metadata, :auto_archive_duration),
      "archive_timestamp" =>
        thread_metadata
        |> fetch_thread_metadata(:archive_timestamp)
        |> stringify_datetime()
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp fetch_thread_metadata(metadata, key) when is_atom(key) do
    case Map.fetch(metadata, key) do
      {:ok, value} -> value
      :error -> Map.get(metadata, Atom.to_string(key))
    end
  end

  defp compact_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, [], ""] end)
    |> Map.new()
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: true

  defp stringify(nil), do: nil
  defp stringify(value), do: to_string(value)

  defp stringify_datetime(nil), do: nil
  defp stringify_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
