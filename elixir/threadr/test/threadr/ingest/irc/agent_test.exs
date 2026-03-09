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
    assert envelope.data.metadata["platform_channel_id"] == "#intel"
    assert envelope.data.metadata["observed_handle"] == "alice"
    assert envelope.data.metadata["observed_display_name"] == "alice"
    assert envelope.data.metadata["irc_user"] == "alice"
    assert envelope.data.metadata["irc_host"] == "workstation.example.org"
    assert envelope.data.metadata["conversation_external_id"] == "#intel"

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

  test "publishes channel messages delivered via ExIRC received events" do
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
        port: 6667,
        ssl: false,
        nick: "threadr"
      }
    ]

    {:ok, pid} = start_supervised({Threadr.Ingest.IRC.Agent, config})

    assert_receive {:irc_client_connect, :tcp, "irc.example.org", 6667}

    send(
      pid,
      {:received, "hello @bob", %{nick: "alice", user: "alice", host: "workstation.example.org"},
       "#intel"}
    )

    assert_receive {:published_envelope, envelope}
    assert envelope.data.actor == "alice"
    assert envelope.data.channel == "#intel"
    assert envelope.data.body == "hello @bob"
  end

  test "publishes IRC nick changes as context events" do
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
        cmd: "NICK",
        nick: "alice",
        user: "alice",
        host: "workstation.example.org",
        args: ["alice_"]
      }
    )

    assert_receive {:published_envelope, envelope}
    assert envelope.type == "chat.context"
    assert envelope.data.event_type == "nick_change"
    assert envelope.data.actor == "alice"
    assert envelope.data.channel == nil
    assert envelope.data.metadata["new_handle"] == "alice_"
    assert envelope.data.raw["new_nick"] == "alice_"
  end

  test "publishes IRC topic changes as context events" do
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
        cmd: "TOPIC",
        nick: "alice",
        user: "alice",
        host: "workstation.example.org",
        args: ["#intel", "incident bridge updates"]
      }
    )

    assert_receive {:published_envelope, envelope}
    assert envelope.type == "chat.context"
    assert envelope.data.event_type == "topic_change"
    assert envelope.data.actor == "alice"
    assert envelope.data.channel == "#intel"
    assert envelope.data.metadata["topic"] == "incident bridge updates"
    assert envelope.data.raw["topic"] == "incident bridge updates"
  end

  test "requests channel names on join and publishes roster presence context events" do
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

    send(pid, {:joined, "#intel"})

    assert_receive {:irc_client_channel_names, "#intel"}

    send(
      pid,
      %Message{
        cmd: "353",
        args: ["threadr", "=", "#intel", "@alice +bob carol @threadr"]
      }
    )

    assert_receive {:published_envelope, alice_envelope}
    assert_receive {:published_envelope, bob_envelope}
    assert_receive {:published_envelope, carol_envelope}
    refute_receive {:published_envelope, _envelope}, 100

    envelopes =
      [alice_envelope, bob_envelope, carol_envelope]
      |> Enum.sort_by(& &1.data.actor)

    assert Enum.map(envelopes, & &1.data.actor) == ["alice", "bob", "carol"]
    assert Enum.all?(envelopes, &(&1.type == "chat.context"))
    assert Enum.all?(envelopes, &(&1.data.event_type == "roster_presence"))
    assert Enum.all?(envelopes, &(&1.data.channel == "#intel"))

    [alice, bob, carol] = envelopes

    assert alice.data.metadata["irc_membership_prefixes"] == ["@"]
    assert alice.data.metadata["irc_membership_flags"] == ["op"]
    assert bob.data.metadata["irc_membership_prefixes"] == ["+"]
    assert bob.data.metadata["irc_membership_flags"] == ["voice"]
    assert carol.data.metadata["irc_membership_prefixes"] == []
    assert carol.data.metadata["irc_membership_flags"] == []
    assert alice.data.raw["names"] == "@alice +bob carol @threadr"
  end
end
