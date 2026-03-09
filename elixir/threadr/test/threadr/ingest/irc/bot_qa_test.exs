defmodule Threadr.Ingest.IRC.BotQATest do
  use Threadr.DataCase, async: false

  alias ExIRC.Message, as: IRCMessage
  alias Threadr.ControlPlane.Service
  alias Threadr.Ingest.IRC.Agent
  alias Threadr.TenantData.{Actor, Channel, MessageEmbedding}
  alias Threadr.TenantData.Message, as: TenantMessage

  setup do
    if pid = Process.whereis(Agent) do
      GenServer.stop(pid)
    end

    :ok
  end

  test "replies when an IRC message is addressed to the bot" do
    tenant = create_tenant!("IRC Bot QA")
    actor = create_actor!(tenant.schema_name, "alice")
    channel = create_channel!(tenant.schema_name, "intel")

    message =
      create_message!(
        tenant.schema_name,
        actor.id,
        channel.id,
        "Alice and Bob discussed endpoint isolation last week."
      )

    create_embedding!(tenant.schema_name, message.id, [0.4, 0.5, 0.6])

    config = [
      tenant_subject_name: tenant.subject_name,
      tenant_id: tenant.id,
      bot_id: "bot-123",
      channels: ["#intel"],
      publisher: {Threadr.TestPublisher, self()},
      irc_client: Threadr.TestIRCClient,
      irc_client_options: [test_pid: self()],
      embedding_provider: Threadr.TestEmbeddingProvider,
      embedding_model: "test-embedding-model",
      generation_provider: Threadr.TestGenerationProvider,
      generation_model: "test-chat",
      irc: %{
        host: "irc.example.org",
        port: 6667,
        ssl: false,
        nick: "threadr"
      }
    ]

    {:ok, pid} = start_supervised({Agent, config})

    assert_receive {:irc_client_connect, :tcp, "irc.example.org", 6667}
    assert_receive {:irc_client_join, "#intel", ""}

    send(
      pid,
      %IRCMessage{
        cmd: "PRIVMSG",
        nick: "alice",
        user: "alice",
        host: "workstation.example.org",
        args: ["#intel", "threadr: what did Alice and Bob talk about last week?"]
      }
    )

    assert_receive {:published_envelope, _envelope}, 1_000
    assert_receive {:irc_client_cmd, raw_cmd}, 1_000
    assert raw_cmd =~ "PRIVMSG #intel :alice:"
    assert raw_cmd =~ "what did Alice and Bob talk about last week?"
  end

  test "does not reply to IRC messages that are not addressed to the bot" do
    tenant = create_tenant!("IRC Bot QA Idle")

    config = [
      tenant_subject_name: tenant.subject_name,
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

    {:ok, pid} = start_supervised({Agent, config})

    assert_receive {:irc_client_connect, :tcp, "irc.example.org", 6667}

    send(
      pid,
      %IRCMessage{
        cmd: "PRIVMSG",
        nick: "alice",
        user: "alice",
        host: "workstation.example.org",
        args: ["#intel", "what did Alice and Bob talk about last week?"]
      }
    )

    assert_receive {:published_envelope, _envelope}, 1_000
    refute_receive {:irc_client_cmd, _raw_cmd}, 200
  end

  test "replies when an ExIRC received event is addressed to the bot" do
    tenant = create_tenant!("IRC Bot QA Received")
    actor = create_actor!(tenant.schema_name, "alice")
    channel = create_channel!(tenant.schema_name, "intel")

    message =
      create_message!(
        tenant.schema_name,
        actor.id,
        channel.id,
        "Alice and Bob discussed endpoint isolation last week."
      )

    create_embedding!(tenant.schema_name, message.id, [0.4, 0.5, 0.6])

    config = [
      tenant_subject_name: tenant.subject_name,
      tenant_id: tenant.id,
      bot_id: "bot-123",
      channels: ["#intel"],
      publisher: {Threadr.TestPublisher, self()},
      irc_client: Threadr.TestIRCClient,
      irc_client_options: [test_pid: self()],
      embedding_provider: Threadr.TestEmbeddingProvider,
      embedding_model: "test-embedding-model",
      generation_provider: Threadr.TestGenerationProvider,
      generation_model: "test-chat",
      irc: %{
        host: "irc.example.org",
        port: 6667,
        ssl: false,
        nick: "threadr"
      }
    ]

    {:ok, pid} = start_supervised({Agent, config})

    assert_receive {:irc_client_connect, :tcp, "irc.example.org", 6667}

    send(
      pid,
      {:received, "threadr: what did Alice and Bob talk about last week?",
       %{nick: "alice", user: "alice", host: "workstation.example.org"}, "#intel"}
    )

    assert_receive {:published_envelope, _envelope}, 1_000
    assert_receive {:irc_client_cmd, raw_cmd}, 1_000
    assert raw_cmd =~ "PRIVMSG #intel :alice:"
  end

  test "routes direct greetings through chat mode instead of retrieval QA" do
    tenant = create_tenant!("IRC Bot Chat")

    config = [
      tenant_subject_name: tenant.subject_name,
      tenant_id: tenant.id,
      bot_id: "bot-123",
      channels: ["#intel"],
      publisher: {Threadr.TestPublisher, self()},
      irc_client: Threadr.TestIRCClient,
      irc_client_options: [test_pid: self()],
      generation_provider: Threadr.TestGenerationProvider,
      generation_model: "test-chat",
      irc: %{
        host: "irc.example.org",
        port: 6667,
        ssl: false,
        nick: "threadr"
      }
    ]

    {:ok, pid} = start_supervised({Agent, config})

    assert_receive {:irc_client_connect, :tcp, "irc.example.org", 6667}

    send(
      pid,
      %IRCMessage{
        cmd: "PRIVMSG",
        nick: "alice",
        user: "alice",
        host: "workstation.example.org",
        args: ["#intel", "threadr: hello"]
      }
    )

    assert_receive {:published_envelope, _envelope}, 1_000
    assert_receive {:irc_client_cmd, raw_cmd}, 1_000
    assert raw_cmd =~ "PRIVMSG #intel :alice:"
    assert raw_cmd =~ "hello"
    refute raw_cmd =~ "Context:"
  end

  test "splits long IRC replies across multiple PRIVMSG lines" do
    tenant = create_tenant!("IRC Bot QA Split Reply")

    config = [
      tenant_subject_name: tenant.subject_name,
      tenant_id: tenant.id,
      bot_id: "bot-123",
      channels: ["#!chases"],
      publisher: {Threadr.TestPublisher, self()},
      irc_client: Threadr.TestIRCClient,
      irc_client_options: [test_pid: self()],
      generation_provider: Threadr.TestLongGenerationProvider,
      generation_model: "test-chat",
      irc: %{
        host: "irc.example.org",
        port: 6667,
        ssl: false,
        nick: "threadr"
      }
    ]

    {:ok, pid} = start_supervised({Agent, config})

    assert_receive {:irc_client_connect, :tcp, "irc.example.org", 6667}

    send(
      pid,
      %IRCMessage{
        cmd: "PRIVMSG",
        nick: "leku",
        user: "leku",
        host: "workstation.example.org",
        args: ["#!chases", "threadr: hello"]
      }
    )

    assert_receive {:published_envelope, _envelope}, 1_000
    raw_cmd_1 = assert_receive_irc_cmd()
    raw_cmd_2 = assert_receive_irc_cmd()
    raw_cmd_3 = maybe_receive_irc_cmd()

    refute raw_cmd_1 =~ "..."
    refute raw_cmd_2 =~ "..."
    assert raw_cmd_1 =~ "PRIVMSG #!chases :leku:"
    assert raw_cmd_2 =~ "PRIVMSG #!chases :leku:"
    assert byte_size(raw_cmd_1) < 400
    assert byte_size(raw_cmd_2) < 400

    combined_reply =
      [raw_cmd_1, raw_cmd_2, raw_cmd_3]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn raw_cmd ->
        raw_cmd
        |> String.split("PRIVMSG #!chases :leku: ", parts: 2)
        |> List.last()
      end)
      |> Enum.join(" ")

    assert combined_reply =~ "terrace planters"
    assert combined_reply =~ "cigarette butts"
    assert combined_reply =~ "soil depth"
  end

  test "answers actor topical questions constrained to today in IRC" do
    tenant = create_tenant!("IRC Bot QA Today")
    actor = create_actor!(tenant.schema_name, "farmr")
    channel = create_channel!(tenant.schema_name, "#!chases")

    create_message!(
      tenant.schema_name,
      actor.id,
      channel.id,
      "farmr talked about terrace produce, planters, and garden ideas today."
    )

    config = [
      tenant_subject_name: tenant.subject_name,
      tenant_id: tenant.id,
      bot_id: "bot-123",
      channels: ["#!chases"],
      publisher: {Threadr.TestPublisher, self()},
      irc_client: Threadr.TestIRCClient,
      irc_client_options: [test_pid: self()],
      generation_provider: Threadr.TestConstraintGenerationProvider,
      generation_model: "test-chat",
      irc: %{
        host: "irc.example.org",
        port: 6667,
        ssl: false,
        nick: "threadr"
      }
    ]

    {:ok, pid} = start_supervised({Agent, config})

    assert_receive {:irc_client_connect, :tcp, "irc.example.org", 6667}

    send(
      pid,
      %IRCMessage{
        cmd: "PRIVMSG",
        nick: "leku",
        user: "leku",
        host: "workstation.example.org",
        args: ["#!chases", "threadr: what did farmr talk about today?"]
      }
    )

    assert_receive {:published_envelope, _envelope}, 1_000
    assert_receive {:irc_client_cmd, raw_cmd}, 1_000
    assert raw_cmd =~ "PRIVMSG #!chases :leku:"
    assert raw_cmd =~ "what did farmr talk about today?"
  end

  test "resolves self references for addressed IRC questions" do
    tenant = create_tenant!("IRC Bot QA Self Reference")
    actor = create_actor!(tenant.schema_name, "leku")
    other_actor = create_actor!(tenant.schema_name, "sig")
    channel = create_channel!(tenant.schema_name, "intel")

    create_message!(
      tenant.schema_name,
      actor.id,
      channel.id,
      "leku keeps talking about IRC bots and deploy drift."
    )

    create_message!(
      tenant.schema_name,
      actor.id,
      channel.id,
      "leku asked whether the rollout recovered."
    )

    mention_message =
      create_message!(
        tenant.schema_name,
        other_actor.id,
        channel.id,
        "sig said leku keeps talking about bot deploys and rollout status."
      )

    create_message_mention!(tenant.schema_name, mention_message.id, actor.id)

    config = [
      tenant_subject_name: tenant.subject_name,
      tenant_id: tenant.id,
      bot_id: "bot-123",
      channels: ["#intel"],
      publisher: {Threadr.TestPublisher, self()},
      irc_client: Threadr.TestIRCClient,
      irc_client_options: [test_pid: self()],
      generation_provider: Threadr.TestGenerationProvider,
      generation_model: "test-chat",
      irc: %{
        host: "irc.example.org",
        port: 6667,
        ssl: false,
        nick: "threadr"
      }
    ]

    {:ok, pid} = start_supervised({Agent, config})

    assert_receive {:irc_client_connect, :tcp, "irc.example.org", 6667}

    send(
      pid,
      %IRCMessage{
        cmd: "PRIVMSG",
        nick: "leku",
        user: "leku",
        host: "workstation.example.org",
        args: ["#intel", "threadr: what do you know about me?"]
      }
    )

    assert_receive {:published_envelope, _envelope}, 1_000
    assert_receive {:irc_client_cmd, raw_cmd}, 1_000
    assert raw_cmd =~ "PRIVMSG #intel :leku:"
    refute raw_cmd =~ "can't find actor \"me\""
    assert raw_cmd =~ "what do you know about me?"
  end

  defp create_tenant!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(%{
        name: "#{prefix} #{suffix}",
        subject_name: "irc-bot-qa-#{suffix}"
      })

    tenant
  end

  defp create_actor!(tenant_schema, handle) do
    Actor
    |> Ash.Changeset.for_create(
      :create,
      %{platform: "irc", handle: handle, display_name: String.capitalize(handle)},
      tenant: tenant_schema
    )
    |> Ash.create!()
  end

  defp create_channel!(tenant_schema, name) do
    Channel
    |> Ash.Changeset.for_create(
      :create,
      %{platform: "irc", name: name},
      tenant: tenant_schema
    )
    |> Ash.create!()
  end

  defp create_message!(tenant_schema, actor_id, channel_id, body) do
    TenantMessage
    |> Ash.Changeset.for_create(
      :create,
      %{
        external_id: Ecto.UUID.generate(),
        body: body,
        observed_at: DateTime.utc_now(),
        raw: %{"body" => body},
        metadata: %{},
        actor_id: actor_id,
        channel_id: channel_id
      },
      tenant: tenant_schema
    )
    |> Ash.create!()
  end

  defp create_embedding!(tenant_schema, message_id, embedding) do
    MessageEmbedding
    |> Ash.Changeset.for_create(
      :create,
      %{
        model: "test-embedding-model",
        dimensions: length(embedding),
        embedding: embedding,
        metadata: %{},
        message_id: message_id
      },
      tenant: tenant_schema
    )
    |> Ash.create!()
  end

  defp create_message_mention!(tenant_schema, message_id, actor_id) do
    Threadr.TenantData.MessageMention
    |> Ash.Changeset.for_create(
      :create,
      %{message_id: message_id, actor_id: actor_id},
      tenant: tenant_schema
    )
    |> Ash.create!()
  end

  defp assert_receive_irc_cmd do
    assert_receive {:irc_client_cmd, raw_cmd}, 1_000
    raw_cmd
  end

  defp maybe_receive_irc_cmd do
    receive do
      {:irc_client_cmd, raw_cmd} -> raw_cmd
    after
      200 -> nil
    end
  end
end
