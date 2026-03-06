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

    assert {:ok,
            %{
              settings: %{
                "env" => %{
                  "THREADR_DISCORD_APPLICATION_ID" => "1227806998788051027",
                  "THREADR_DISCORD_PUBLIC_KEY" =>
                    "8bb798d162e922cfa9e1fed25808b1d4fb474355d094e89bfaa13cd9e0fe2163",
                  "THREADR_DISCORD_TOKEN" => "discord-token"
                }
              }
            }} =
             BotConfig.normalize_and_validate("discord", ["123456789"], %{
               "application_id" => "1227806998788051027",
               "public_key" => "8bb798d162e922cfa9e1fed25808b1d4fb474355d094e89bfaa13cd9e0fe2163",
               "token" => "discord-token"
             })

    assert {:error, {:settings, _message}} =
             BotConfig.normalize_and_validate("discord", ["123456789"], %{})
  end
end
