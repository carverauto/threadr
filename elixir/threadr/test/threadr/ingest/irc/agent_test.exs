defmodule Threadr.Ingest.IRC.AgentTest do
  use ExUnit.Case, async: false

  alias ExIRC.Message

  setup do
    if pid = Process.whereis(Threadr.Ingest.IRC.Agent) do
      GenServer.stop(pid)
    end

    :ok
  end

  test "connects with ExIRC, joins configured channels, and publishes channel messages" do
    config = [
      tenant_subject_name: "acme-threat-intel",
      tenant_id: "tenant-123",
      bot_id: "bot-123",
      channels: ["#intel"],
      publisher: {Threadr.TestPublisher, self()},
      irc_client: Threadr.TestIRCClient,
      irc_client_options: [test_pid: self()],
      irc: %{
        host: "irc.example.org",
        port: 6697,
        ssl: true,
        nick: "threadr",
        user: "threadr",
        realname: "Threadr Bot",
        password: "sekret"
      }
    ]

    {:ok, pid} = start_supervised({Threadr.Ingest.IRC.Agent, config})

    assert_receive {:irc_client_add_handler, _client_pid, ^pid}
    assert_receive {:irc_client_connect, :ssl, "irc.example.org", 6697}
    assert_receive {:irc_client_logon, "sekret", "threadr", "threadr", "Threadr Bot"}
    assert_receive {:irc_client_join, "#intel", ""}

    send(
      pid,
      %Message{
        cmd: "PRIVMSG",
        nick: "alice",
        user: "alice",
        host: "workstation.example.org",
        args: ["#intel", "hello @bob"]
      }
    )

    assert_receive {:published_envelope, envelope}
    assert envelope.source == "threadr.ingest.irc"
    assert envelope.subject == "threadr.tenants.acme-threat-intel.chat.message"
    assert envelope.metadata["platform_channel_id"] == "#intel"
    assert envelope.data.actor == "alice"
    assert envelope.data.channel == "#intel"
    assert envelope.data.body == "hello @bob"
    assert envelope.data.mentions == ["bob"]

    assert envelope.data.raw == %{
             "host" => "workstation.example.org",
             "user" => "alice",
             "nick" => "alice"
           }
  end

  test "ignores messages outside the configured IRC channels" do
    config = [
      tenant_subject_name: "acme-threat-intel",
      channels: ["#intel"],
      publisher: {Threadr.TestPublisher, self()},
      irc_client: Threadr.TestIRCClient,
      irc_client_options: [test_pid: self()],
      irc: %{
        host: "irc.example.org",
        port: 6667,
        ssl: false,
        nick: "threadr"
      }
    ]

    {:ok, pid} = start_supervised({Threadr.Ingest.IRC.Agent, config})

    assert_receive {:irc_client_connect, :tcp, "irc.example.org", 6667}

    send(
      pid,
      %Message{
        cmd: "PRIVMSG",
        nick: "alice",
        user: "alice",
        host: "workstation.example.org",
        args: ["#random", "hello"]
      }
    )

    refute_receive {:published_envelope, _envelope}, 200
  end
end
