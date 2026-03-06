defmodule Threadr.ControlPlane.BotConfigTest do
  use ExUnit.Case, async: true

  alias Threadr.ControlPlane.BotConfig

  test "normalizes legacy IRC settings into env variables" do
    assert {:ok,
            %{
              platform: "irc",
              channels: ["#threadr"],
              settings: %{
                "env" => %{
                  "THREADR_IRC_HOST" => "irc.example.com",
                  "THREADR_IRC_NICK" => "threadr-bot",
                  "THREADR_IRC_PASSWORD" => "super-secret"
                }
              }
            }} =
             BotConfig.normalize_and_validate("IRC", ["#threadr"], %{
               "server" => "irc.example.com",
               "nick" => "threadr-bot",
               "password" => "super-secret"
             })
  end

  test "redacts sensitive env values for API responses" do
    assert BotConfig.redact_settings(%{
             "env" => %{
               "THREADR_IRC_HOST" => "irc.example.com",
               "THREADR_IRC_PASSWORD" => "super-secret"
             }
           }) == %{
             "env" => %{
               "THREADR_IRC_HOST" => "irc.example.com",
               "THREADR_IRC_PASSWORD" => "[REDACTED]"
             }
           }
  end

  test "validates Discord bot settings and channels" do
    assert {:error, {:channels, _message}} =
             BotConfig.normalize_and_validate("discord", ["general"], %{
               "token" => "discord-token"
             })

    assert {:error, {:settings, _message}} =
             BotConfig.normalize_and_validate("discord", ["123456789"], %{})
  end
end
