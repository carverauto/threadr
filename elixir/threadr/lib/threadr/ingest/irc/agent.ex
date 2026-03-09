defmodule Threadr.Ingest.IRC.Agent do
  @moduledoc """
  Single-bot IRC runtime backed by ExIRC.
  """

  use GenServer

  require Logger

  alias ExIRC.Client
  alias ExIRC.Message
  alias Threadr.Ingest
  alias Threadr.Ingest.BotQA

  @reconnect_backoff_ms 5_000

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @impl true
  def init(config) do
    irc = Keyword.get(config, :irc, %{})

    if blank?(irc[:host]) do
      raise "THREADR_IRC_HOST must be set for IRC ingestion"
    end

    if blank?(irc[:nick]) do
      raise "THREADR_IRC_NICK must be set for IRC ingestion"
    end

    client_module = Keyword.get(config, :irc_client, Client)
    client_options = Keyword.get(config, :irc_client_options, [])
    {:ok, client} = client_module.start_link(Keyword.put(client_options, :owner, self()))
    :ok = client_module.add_handler(client, self())
    Ingest.emit_runtime_event(config, :starting)
    send(self(), :connect)

    {:ok,
     %{
       client: client,
       client_module: client_module,
       config: config
     }}
  end

  @impl true
  def handle_info(:connect, state) do
    irc = Keyword.fetch!(state.config, :irc)

    result =
      if irc[:ssl] do
        state.client_module.connect_ssl!(state.client, irc.host, irc.port, [])
      else
        state.client_module.connect!(state.client, irc.host, irc.port, [])
      end

    case result do
      :ok ->
        Ingest.emit_runtime_event(state.config, :connecting, %{host: irc.host, port: irc.port})
        {:noreply, state}

      {:ok, _socket} ->
        Ingest.emit_runtime_event(state.config, :connecting, %{host: irc.host, port: irc.port})
        {:noreply, state}

      {:error, reason} ->
        Logger.error("failed to connect IRC ingest runtime: #{inspect(reason)}")

        Ingest.emit_runtime_event(state.config, :error, %{
          reason: inspect(reason),
          stage: "connect"
        })

        schedule_reconnect()
        {:noreply, state}
    end
  end

  def handle_info({:connected, server, port}, state) do
    Logger.info("connected IRC ingest runtime to #{server}:#{port}")
    Ingest.emit_runtime_event(state.config, :connected, %{host: server, port: port})

    irc = Keyword.fetch!(state.config, :irc)

    case state.client_module.logon(
           state.client,
           irc[:password] || "",
           irc.nick,
           irc[:user] || irc.nick,
           irc[:realname] || "Threadr Bot"
         ) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("failed to log on IRC ingest runtime: #{inspect(reason)}")

        Ingest.emit_runtime_event(state.config, :error, %{reason: inspect(reason), stage: "logon"})

        schedule_reconnect()
    end

    {:noreply, state}
  end

  def handle_info(:logged_in, state) do
    state.config
    |> Keyword.get(:channels, [])
    |> Enum.each(fn channel ->
      :ok = state.client_module.join(state.client, channel)
    end)

    Ingest.emit_runtime_event(state.config, :ready, %{channels: state.config[:channels] || []})

    {:noreply, state}
  end

  def handle_info({:login_failed, reason}, state) do
    Logger.error("IRC ingest login failed: #{inspect(reason)}")
    Ingest.emit_runtime_event(state.config, :error, %{reason: inspect(reason), stage: "login"})
    schedule_reconnect()
    {:noreply, state}
  end

  def handle_info(:disconnected, state) do
    Logger.warning("IRC ingest connection closed, reconnecting")
    Ingest.emit_runtime_event(state.config, :disconnected)
    schedule_reconnect()
    {:noreply, state}
  end

  def handle_info(
        %Message{cmd: "PRIVMSG", nick: nick, user: user, host: host, args: [channel, body]},
        state
      ) do
    handle_channel_message(state, nick, user, host, channel, body)

    {:noreply, state}
  end

  def handle_info({:received, body, %{nick: nick, user: user, host: host}, channel}, state)
      when is_binary(channel) do
    handle_channel_message(state, nick, user, host, channel, body)

    {:noreply, state}
  end

  def handle_info({:joined, channel}, state) do
    Logger.info("IRC ingest joined #{channel}")
    {:noreply, state}
  end

  def handle_info(
        %Message{cmd: "NICK", nick: nick, user: user, host: host, args: [new_nick]},
        state
      ) do
    publish_context_event(
      state,
      "nick_change",
      nick,
      nil,
      %{
        "observed_handle" => nick,
        "observed_display_name" => nick,
        "new_handle" => new_nick,
        "irc_user" => user,
        "irc_host" => host
      },
      %{
        "nick" => nick,
        "new_nick" => new_nick,
        "user" => user,
        "host" => host
      },
      "#{nick}:#{new_nick}:nick"
    )

    {:noreply, state}
  end

  def handle_info(
        %Message{cmd: "JOIN", nick: nick, user: user, host: host, args: [channel | _]},
        state
      ) do
    publish_channel_context_event(
      state,
      "join",
      nick,
      user,
      host,
      channel,
      "#{nick}:#{channel}:join"
    )

    {:noreply, state}
  end

  def handle_info(
        %Message{cmd: "PART", nick: nick, user: user, host: host, args: [channel | _]},
        state
      ) do
    publish_channel_context_event(
      state,
      "part",
      nick,
      user,
      host,
      channel,
      "#{nick}:#{channel}:part"
    )

    {:noreply, state}
  end

  def handle_info(%Message{cmd: "QUIT", nick: nick, user: user, host: host, args: args}, state) do
    publish_context_event(
      state,
      "quit",
      nick,
      nil,
      %{
        "observed_handle" => nick,
        "observed_display_name" => nick,
        "irc_user" => user,
        "irc_host" => host,
        "reason" => List.first(args)
      },
      %{
        "nick" => nick,
        "user" => user,
        "host" => host,
        "reason" => List.first(args)
      },
      "#{nick}:quit"
    )

    {:noreply, state}
  end

  def handle_info(
        %Message{cmd: "TOPIC", nick: nick, user: user, host: host, args: [channel, topic | _]},
        state
      ) do
    if Ingest.channel_allowed?(state.config[:channels], channel) do
      publish_context_event(
        state,
        "topic_change",
        nick,
        channel,
        %{
          "platform_channel_id" => channel,
          "conversation_external_id" => channel,
          "observed_handle" => nick,
          "observed_display_name" => nick,
          "irc_user" => user,
          "irc_host" => host,
          "topic" => topic
        },
        %{
          "nick" => nick,
          "user" => user,
          "host" => host,
          "channel" => channel,
          "topic" => topic
        },
        "#{nick}:#{channel}:topic"
      )
    end

    {:noreply, state}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp schedule_reconnect do
    Process.send_after(self(), :connect, @reconnect_backoff_ms)
  end

  defp handle_channel_message(state, nick, user, host, channel, body) do
    cond do
      blank?(body) ->
        :ok

      not Ingest.channel_allowed?(state.config[:channels], channel) ->
        :ok

      true ->
        :ok =
          Ingest.publish_chat_message(state.config, %{
            platform: "irc",
            actor: nick,
            body: body,
            channel: channel,
            platform_channel_id: channel,
            metadata: %{
              "platform_channel_id" => channel,
              "observed_handle" => nick,
              "observed_display_name" => nick,
              "irc_user" => user,
              "irc_host" => host,
              "conversation_external_id" => channel
            },
            raw: %{
              "host" => host,
              "user" => user,
              "nick" => nick
            }
          })

        :ok =
          BotQA.maybe_answer_irc(state.config, state.client, state.client_module, %{
            actor: nick,
            body: body,
            channel: channel
          })
    end
  end

  defp publish_channel_context_event(state, event_type, nick, user, host, channel, external_id) do
    if Ingest.channel_allowed?(state.config[:channels], channel) do
      publish_context_event(
        state,
        event_type,
        nick,
        channel,
        %{
          "platform_channel_id" => channel,
          "conversation_external_id" => channel,
          "observed_handle" => nick,
          "observed_display_name" => nick,
          "irc_user" => user,
          "irc_host" => host
        },
        %{
          "nick" => nick,
          "user" => user,
          "host" => host,
          "channel" => channel
        },
        external_id
      )
    else
      :ok
    end
  end

  defp publish_context_event(state, event_type, actor, channel, metadata, raw, external_suffix) do
    Ingest.publish_context_event(state.config, %{
      platform: "irc",
      event_type: event_type,
      actor: actor,
      channel: channel,
      observed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      external_id: "irc:#{external_suffix}",
      platform_channel_id: channel,
      metadata: metadata,
      raw: raw
    })
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_value), do: false
end
