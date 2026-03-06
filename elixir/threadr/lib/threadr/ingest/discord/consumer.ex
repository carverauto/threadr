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
  def handle_event({:MESSAGE_CREATE, %Message{} = message, _ws_state}) do
    config = :persistent_term.get(@config_key, [])

    cond do
      ignored_author?(message) ->
        :ok

      blank?(message.content) ->
        :ok

      not Ingest.channel_allowed?(config[:channels], Integer.to_string(message.channel_id)) ->
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
    Map.get(message.author, :bot, false)
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: true

  defp stringify(nil), do: nil
  defp stringify(value), do: to_string(value)
end
