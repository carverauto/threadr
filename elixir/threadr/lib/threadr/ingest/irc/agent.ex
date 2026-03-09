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
  @membership_prefix_flags %{
    "~" => "owner",
    "&" => "admin",
    "@" => "op",
    "%" => "halfop",
    "+" => "voice"
  }

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
    request_channel_roster(state, channel)
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

  def handle_info(%Message{cmd: "353", args: args}, state) do
    case extract_names_reply(args) do
      {:ok, channel, names} ->
        publish_roster_presence_events(state, channel, names)

      :error ->
        :ok
    end

    {:noreply, state}
  end

  def handle_info(%Message{cmd: "366", args: [_nick, channel | _rest]}, state) do
    Logger.debug("IRC ingest finished roster sync for #{channel}")
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

  defp request_channel_roster(state, channel) do
    if Ingest.channel_allowed?(state.config[:channels], channel) do
      cond do
        function_exported?(state.client_module, :channel_names, 2) ->
          :ok = state.client_module.channel_names(state.client, channel)

        function_exported?(state.client_module, :names, 2) ->
          :ok = state.client_module.names(state.client, channel)

        function_exported?(state.client_module, :cmd, 2) ->
          :ok = state.client_module.cmd(state.client, "NAMES #{channel}")

        true ->
          :ok
      end
    else
      :ok
    end
  end

  defp extract_names_reply([_requester, _visibility, channel, names | _rest])
       when is_binary(channel) and is_binary(names) do
    {:ok, channel, names}
  end

  defp extract_names_reply(_args), do: :error

  defp publish_roster_presence_events(state, channel, names) do
    if Ingest.channel_allowed?(state.config[:channels], channel) do
      observed_at = DateTime.utc_now() |> DateTime.truncate(:second)
      roster_batch_id = roster_batch_id(channel, names)

      names
      |> parse_roster_names()
      |> Enum.reject(&bot_handle?(&1.handle, state))
      |> Enum.each(fn %{handle: handle, prefixes: prefixes, flags: flags} ->
        Ingest.publish_context_event(state.config, %{
          platform: "irc",
          event_type: "roster_presence",
          actor: handle,
          channel: channel,
          observed_at: observed_at,
          external_id: "irc:#{channel}:#{roster_batch_id}:#{handle}:roster",
          platform_channel_id: channel,
          metadata: %{
            "platform_channel_id" => channel,
            "conversation_external_id" => channel,
            "observed_handle" => handle,
            "observed_display_name" => handle,
            "irc_membership_prefixes" => prefixes,
            "irc_membership_flags" => flags,
            "presence_source" => "names_reply",
            "roster_batch_id" => roster_batch_id
          },
          raw: %{
            "channel" => channel,
            "nick" => handle,
            "prefixes" => prefixes,
            "flags" => flags,
            "names" => names
          }
        })
      end)
    end
  end

  defp parse_roster_names(names) when is_binary(names) do
    names
    |> String.trim_leading(":")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&parse_roster_name/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&String.downcase(&1.handle))
  end

  defp parse_roster_name(name) do
    {prefixes, handle} = split_membership_prefixes(String.trim(name))

    if blank?(handle) do
      nil
    else
      %{
        handle: handle,
        prefixes: prefixes,
        flags: Enum.map(prefixes, &Map.get(@membership_prefix_flags, &1))
      }
    end
  end

  defp split_membership_prefixes(name), do: split_membership_prefixes(name, [])

  defp split_membership_prefixes(<<prefix::utf8, rest::binary>>, prefixes) do
    prefix_string = <<prefix::utf8>>

    if Map.has_key?(@membership_prefix_flags, prefix_string) do
      split_membership_prefixes(rest, prefixes ++ [prefix_string])
    else
      {prefixes, <<prefix::utf8, rest::binary>>}
    end
  end

  defp split_membership_prefixes(name, prefixes), do: {prefixes, name}

  defp bot_handle?(handle, state) when is_binary(handle) do
    configured_nick =
      state.config
      |> Keyword.get(:irc, %{})
      |> Map.get(:nick)

    same_handle?(handle, configured_nick)
  end

  defp roster_batch_id(channel, names) do
    :sha256
    |> :crypto.hash("#{channel}\n#{names}")
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 12)
  end

  defp same_handle?(left, right) when is_binary(left) and is_binary(right) do
    String.downcase(String.trim(left)) == String.downcase(String.trim(right))
  end

  defp same_handle?(_left, _right), do: false

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_value), do: false
end
