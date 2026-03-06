defmodule Threadr.Ingest.Discord.BotTest do
  use ExUnit.Case, async: false

  alias Threadr.Ingest.Discord.Bot

  setup do
    original = [
      token: Application.get_env(:nostrum, :token),
      gateway_intents: Application.get_env(:nostrum, :gateway_intents),
      ffmpeg: Application.get_env(:nostrum, :ffmpeg),
      youtubedl: Application.get_env(:nostrum, :youtubedl),
      streamlink: Application.get_env(:nostrum, :streamlink)
    ]

    on_exit(fn ->
      Enum.each(original, fn {key, value} ->
        if is_nil(value) do
          Application.delete_env(:nostrum, key)
        else
          Application.put_env(:nostrum, key, value)
        end
      end)
    end)

    :ok
  end

  test "configures nostrum with message content intent enabled" do
    Bot.configure_nostrum("discord-test-token")

    assert Application.fetch_env!(:nostrum, :token) == "discord-test-token"

    assert Application.fetch_env!(:nostrum, :gateway_intents) == [
             :guilds,
             :guild_messages,
             :direct_messages,
             :message_content
           ]

    assert Application.fetch_env!(:nostrum, :ffmpeg) == false
    assert Application.fetch_env!(:nostrum, :youtubedl) == false
    assert Application.fetch_env!(:nostrum, :streamlink) == false
  end
end
