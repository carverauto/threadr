defmodule Threadr.Ingest.Discord.Consumer do
  @moduledoc """
  Nostrum consumer that normalizes Discord messages into Threadr chat events.
  """

  use Nostrum.Consumer

  alias Nostrum.Struct.Message
  alias Threadr.Ingest

  @config_key {__MODULE__, :config}

  def put_config(config) do
    :persistent_term.put(@config_key, config)
  end

  @impl true
  def handle_event({:READY, ready, _ws_state}) do
    config = :persistent_term.get(@config_key, [])

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
            raw: %{
              "message_id" => to_string(message.id),
              "channel_id" => Integer.to_string(message.channel_id),
              "guild_id" => stringify(message.guild_id)
            },
            external_id: to_string(message.id)
          })

        Ingest.emit_runtime_event(config, :message_published, metadata)
    end
  end

  def handle_event(_event), do: :ok

  defp actor_handle(message) do
    Map.get(message.author, :global_name) || message.author.username
  end

  defp mention_handles(message) do
    message.mentions
    |> Enum.map(fn mention ->
      Map.get(mention, :global_name) || mention.username
    end)
    |> Ingest.normalize_mentions()
  end

  defp ignored_author?(message) do
    config = :persistent_term.get(@config_key, [])
    discord_config = Keyword.get(config, :discord, %{})
    allow_bot_messages = Map.get(discord_config, :allow_bot_messages, false)

    Map.get(message.author, :bot, false) and not allow_bot_messages
  end

  defp message_metadata(message) do
    %{
      platform: "discord",
      channel_id: Integer.to_string(message.channel_id),
      guild_id: stringify(message.guild_id),
      author_bot: Map.get(message.author, :bot, false),
      content_present: not blank?(message.content)
    }
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: true

  defp stringify(nil), do: nil
  defp stringify(value), do: to_string(value)
end
