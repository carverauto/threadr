defmodule Threadr.Ingest.BotQA do
  @moduledoc """
  Direct-address detection plus tenant-scoped answer generation for bot runtimes.
  """

  require Logger

  alias Threadr.ControlPlane.Analysis
  alias Threadr.ML.{BotIntent, Generation, GenerationProviderOpts, QARequest}
  alias ExIRC.Commands

  @irc_reply_limit 350
  @discord_reply_limit 1_800
  @qa_option_keys [
    :embedding_provider,
    :embedding_model,
    :embedding_endpoint,
    :embedding_api_key,
    :embedding_provider_name,
    :generation_provider,
    :generation_model,
    :generation_endpoint,
    :generation_api_key,
    :generation_provider_name,
    :generation_temperature,
    :generation_max_tokens,
    :generation_system_prompt,
    :since,
    :until,
    :limit
  ]

  def maybe_answer_irc(config, client, client_module, attrs)
      when is_list(config) and is_map(attrs) do
    attrs
    |> build_irc_request(config)
    |> maybe_answer(config, fn request, content ->
      send_irc_reply(client, client_module, request.channel, format_reply(request, content))
    end)
  end

  def maybe_answer_discord(config, attrs) when is_list(config) and is_map(attrs) do
    attrs
    |> build_discord_request(config)
    |> maybe_answer(config, fn request, content ->
      send_discord_reply(
        discord_api(config),
        request.channel_id,
        format_reply(request, content)
      )
    end)
  end

  def with_discord_identity(config, nil) when is_list(config), do: config

  def with_discord_identity(config, user) when is_list(config) do
    discord = Keyword.get(config, :discord, %{})

    identity = %{
      user_id: stringify(Map.get(user, :id)),
      username: Map.get(user, :username),
      global_name: Map.get(user, :global_name)
    }

    Keyword.put(config, :discord, Map.put(discord, :identity, identity))
  end

  defp maybe_answer(:ignore, _config, _reply_fun), do: :ok

  defp maybe_answer({:ok, request}, config, reply_fun) do
    emit_question_detected(config, request)
    reply = answer_request(config, request)

    case reply_fun.(request, reply.content) do
      :ok ->
        emit_reply_published(config, request, reply)
        :ok

      {:ok, _result} ->
        emit_reply_published(config, request, reply)
        :ok

      {:error, reason} ->
        emit_reply_failed(config, request, reply, reason)
        :ok
    end
  end

  defp build_irc_request(
         %{
           actor: actor,
           body: body,
           channel: channel
         },
         config
       ) do
    nick =
      config
      |> Keyword.get(:irc, %{})
      |> Map.get(:nick)

    case strip_prefixed_question(body, irc_bot_handles(nick)) do
      {:ok, question, trigger} ->
        {:ok,
         %{
           platform: "irc",
           actor: actor,
           reply_prefix: "#{actor}:",
           question: question,
           trigger: trigger,
           channel: channel,
           question_length: String.length(question)
         }}

      :ignore ->
        :ignore
    end
  end

  defp build_irc_request(_attrs, _config), do: :ignore

  defp build_discord_request(
         %{
           actor: actor,
           actor_id: actor_id,
           body: body,
           channel_id: channel_id
         } = attrs,
         config
       ) do
    identity =
      config
      |> Keyword.get(:discord, %{})
      |> Map.get(:identity, %{})

    case strip_discord_question(body, identity) do
      {:ok, question, trigger} ->
        {:ok,
         %{
           platform: "discord",
           actor: actor,
           reply_prefix: "<@#{actor_id}>",
           question: question,
           trigger: trigger,
           channel_id: channel_id,
           platform_message_id: Map.get(attrs, :platform_message_id),
           question_length: String.length(question)
         }}

      :ignore ->
        :ignore
    end
  end

  defp build_discord_request(_attrs, _config), do: :ignore

  defp answer_request(config, request) do
    case BotIntent.classify(request.question) do
      :chat -> answer_chat_request(config, request)
      :qa -> answer_qa_request(config, request)
    end
  end

  defp answer_chat_request(config, request) do
    prompt = chat_prompt(config, request)

    case Generation.complete(prompt, chat_generation_opts(config, request)) do
      {:ok, result} ->
        %{
          status: :answered,
          content:
            result.content
            |> normalize_reply_content()
            |> blank_to_default("Hello. What do you want to know?"),
          mode: :chat
        }

      {:error, :generation_provider_not_configured} ->
        %{
          status: :failed,
          content: "I can't answer yet because no LLM is configured for this tenant.",
          mode: :chat
        }

      {:error, reason} ->
        Logger.error("bot chat failed: #{inspect(reason)}")

        %{
          status: :failed,
          content: "I couldn't answer that right now.",
          mode: :chat
        }
    end
  end

  defp answer_qa_request(config, request) do
    subject_name = Keyword.fetch!(config, :tenant_subject_name)

    qa_request =
      request.question
      |> QARequest.new(
        :bot,
        Keyword.merge(qa_runtime_opts(config), requester_runtime_opts(request))
      )

    case Analysis.answer_tenant_question_for_bot(subject_name, qa_request) do
      {:ok, result} ->
        %{
          status: :answered,
          content: answer_content(result),
          mode: Map.get(result, :mode, :unknown)
        }

      {:error, :no_message_embeddings} ->
        %{
          status: :insufficient_context,
          content: "I don't have enough tenant message history yet to answer that.",
          mode: :none
        }

      {:error, :generation_provider_not_configured} ->
        %{
          status: :failed,
          content: "I can't answer yet because no LLM is configured for this tenant.",
          mode: :none
        }

      {:error, reason} ->
        Logger.error("bot QA failed: #{inspect(reason)}")

        %{
          status: :failed,
          content: "I couldn't answer that right now.",
          mode: :none
        }
    end
  end

  defp answer_content(result) do
    answer =
      case Map.get(result, :answer) do
        %{content: content} -> content
        _ -> ""
      end

    answer
    |> normalize_reply_content()
    |> blank_to_default("I couldn't find a clear answer in the tenant context.")
  end

  defp send_irc_reply(client, client_module, channel, content) do
    content
    |> List.wrap()
    |> Enum.reduce_while(:ok, fn line, _acc ->
      result =
        channel
        |> Commands.privmsg!(line)
        |> IO.iodata_to_binary()
        |> then(&client_module.cmd(client, &1))

      case result do
        :ok -> {:cont, :ok}
        {:ok, _value} -> {:cont, result}
        {:error, _reason} = error -> {:halt, error}
        _other -> {:cont, result}
      end
    end)
  end

  defp send_discord_reply(api, channel_id, content) do
    call_adapter(api, :create_message, [parse_discord_channel_id(channel_id), %{content: content}])
  end

  defp format_reply(%{platform: "irc", reply_prefix: prefix}, content) do
    split_irc_reply_lines("#{prefix} ", content, @irc_reply_limit)
  end

  defp format_reply(%{platform: "discord", reply_prefix: prefix}, content) do
    truncate("#{prefix} #{content}", @discord_reply_limit)
  end

  defp strip_discord_question(body, identity) when is_binary(body) and is_map(identity) do
    mention_prefixes =
      identity
      |> Map.get(:user_id)
      |> mention_tokens()

    handle_prefixes =
      [
        Map.get(identity, :global_name),
        Map.get(identity, :username)
      ]
      |> Enum.reject(&blank?/1)

    case strip_mention_question(body, mention_prefixes) do
      {:ok, _question, _trigger} = result ->
        result

      :ignore ->
        strip_prefixed_question(body, handle_prefixes)
    end
  end

  defp strip_discord_question(_body, _identity), do: :ignore

  defp strip_mention_question(body, prefixes) do
    Enum.find_value(prefixes, :ignore, fn prefix ->
      pattern = ~r/^\s*#{Regex.escape(prefix)}\s*[:,]?\s+(.+?)\s*$/u

      case Regex.run(pattern, body, capture: :all_but_first) do
        [question] -> {:ok, String.trim(question), :mention}
        _ -> nil
      end
    end)
  end

  defp strip_prefixed_question(body, handles) when is_binary(body) and is_list(handles) do
    Enum.find_value(handles, :ignore, fn handle ->
      pattern = ~r/^\s*#{Regex.escape(handle)}(?:\s*[:,]\s*|\s+)(.+?)\s*$/iu

      case Regex.run(pattern, body, capture: :all_but_first) do
        [question] ->
          question = String.trim(question)

          if question == "" do
            nil
          else
            {:ok, question, :prefix}
          end

        _ ->
          nil
      end
    end)
  end

  defp irc_bot_handles(nick) do
    [nick]
    |> Enum.reject(&blank?/1)
  end

  defp mention_tokens(nil), do: []
  defp mention_tokens(user_id), do: ["<@#{user_id}>", "<@!#{user_id}>"]

  defp qa_runtime_opts(config) do
    Keyword.take(config, @qa_option_keys)
  end

  defp chat_generation_opts(config, request) do
    qa_runtime_opts(config)
    |> Keyword.merge(requester_runtime_opts(request))
    |> GenerationProviderOpts.from_prefixed(
      mode: :chat,
      system_prompt:
        "You are Threadr, a concise assistant in a shared chat channel. Reply conversationally. Do not pretend tenant retrieval evidence was used unless the user explicitly asked for analysis."
    )
  end

  defp chat_prompt(config, request) do
    tenant = Keyword.fetch!(config, :tenant_subject_name)

    """
    Tenant: #{tenant}
    Platform: #{request.platform}
    Speaker: #{request.actor}
    Channel: #{Map.get(request, :channel, Map.get(request, :channel_id, "unknown"))}

    The user directly addressed Threadr with this conversational turn:
    #{request.question}

    Reply briefly and naturally as a chatbot.
    """
  end

  defp requester_runtime_opts(request) do
    []
    |> put_request_opt(:requester_actor_handle, Map.get(request, :actor))
    |> put_request_opt(:requester_external_id, stringify(Map.get(request, :actor_id)))
    |> put_request_opt(:requester_channel_name, Map.get(request, :channel))
  end

  defp discord_api(config) do
    Keyword.get(config, :discord_api, Nostrum.Api)
  end

  defp parse_discord_channel_id(channel_id) when is_integer(channel_id), do: channel_id

  defp parse_discord_channel_id(channel_id) when is_binary(channel_id) do
    case Integer.parse(channel_id) do
      {parsed, ""} -> parsed
      _ -> channel_id
    end
  end

  defp parse_discord_channel_id(channel_id), do: channel_id

  defp emit_question_detected(config, request) do
    Threadr.Ingest.emit_runtime_event(config, :question_detected, %{
      platform: request.platform,
      actor: request.actor,
      trigger: request.trigger,
      question_length: request.question_length,
      platform_message_id: Map.get(request, :platform_message_id),
      channel: Map.get(request, :channel, Map.get(request, :channel_id))
    })
  end

  defp emit_reply_published(config, request, reply) do
    Threadr.Ingest.emit_runtime_event(config, :reply_published, %{
      platform: request.platform,
      actor: request.actor,
      status: reply.status,
      mode: reply.mode,
      reply_length: String.length(reply.content),
      platform_message_id: Map.get(request, :platform_message_id),
      channel: Map.get(request, :channel, Map.get(request, :channel_id))
    })
  end

  defp emit_reply_failed(config, request, reply, reason) do
    Threadr.Ingest.emit_runtime_event(config, :reply_failed, %{
      platform: request.platform,
      actor: request.actor,
      status: reply.status,
      mode: reply.mode,
      reason: inspect(reason),
      platform_message_id: Map.get(request, :platform_message_id),
      channel: Map.get(request, :channel, Map.get(request, :channel_id))
    })
  end

  defp call_adapter({module, arg}, function, args), do: apply(module, function, args ++ [arg])
  defp call_adapter(module, function, args), do: apply(module, function, args)

  defp truncate(content, max_length) when byte_size(content) <= max_length, do: content

  defp truncate(content, max_length) do
    binary_part(content, 0, max_length - 3) <> "..."
  end

  defp split_irc_reply_lines(prefix, content, max_length) do
    available_bytes = max(max_length - byte_size(prefix), 1)

    content
    |> split_content_lines(available_bytes)
    |> Enum.map(&(prefix <> &1))
  end

  defp split_content_lines(content, max_bytes) do
    content
    |> String.trim()
    |> do_split_content_lines(max_bytes, [])
  end

  defp do_split_content_lines("", _max_bytes, acc), do: Enum.reverse(acc)

  defp do_split_content_lines(content, max_bytes, acc) when byte_size(content) <= max_bytes do
    Enum.reverse([content | acc])
  end

  defp do_split_content_lines(content, max_bytes, acc) do
    {line, rest} = take_content_line(content, max_bytes)
    do_split_content_lines(String.trim_leading(rest), max_bytes, [line | acc])
  end

  defp take_content_line(content, max_bytes) do
    graphemes = String.graphemes(content)

    {taken, rest, _bytes} =
      Enum.reduce_while(graphemes, {[], graphemes, 0}, fn grapheme, {taken, remaining, bytes} ->
        next_bytes = bytes + byte_size(grapheme)

        if next_bytes <= max_bytes do
          [_current | rest] = remaining
          {:cont, {[grapheme | taken], rest, next_bytes}}
        else
          {:halt, {Enum.reverse(taken), remaining, bytes}}
        end
      end)

    case taken do
      [] ->
        {hard_chunk, hard_rest} = split_long_graphemes(graphemes, max_bytes)
        {hard_chunk, hard_rest}

      _ ->
        maybe_split_at_word_boundary(taken, rest)
    end
  end

  defp maybe_split_at_word_boundary(taken, rest) do
    case last_whitespace_index(taken) do
      nil ->
        {IO.iodata_to_binary(taken), IO.iodata_to_binary(rest)}

      split_index when split_index == length(taken) - 1 ->
        {IO.iodata_to_binary(taken) |> String.trim_trailing(), IO.iodata_to_binary(rest)}

      split_index ->
        {line, overflow} = Enum.split(taken, split_index + 1)

        {
          IO.iodata_to_binary(line) |> String.trim_trailing(),
          IO.iodata_to_binary(overflow ++ rest)
        }
    end
  end

  defp split_long_graphemes(graphemes, max_bytes) do
    {line, rest, _bytes} =
      Enum.reduce_while(graphemes, {[], graphemes, 0}, fn grapheme, {taken, remaining, bytes} ->
        next_bytes = bytes + byte_size(grapheme)

        if next_bytes <= max_bytes do
          [_current | tail] = remaining
          {:cont, {[grapheme | taken], tail, next_bytes}}
        else
          {:halt, {Enum.reverse(taken), remaining, bytes}}
        end
      end)

    {IO.iodata_to_binary(line), IO.iodata_to_binary(rest)}
  end

  defp last_whitespace_index(graphemes) do
    graphemes
    |> Enum.with_index()
    |> Enum.reduce(nil, fn {grapheme, index}, acc ->
      if String.trim(grapheme) == "" do
        index
      else
        acc
      end
    end)
  end

  defp normalize_reply_content(content) when is_binary(content) do
    content
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp normalize_reply_content(_content), do: ""

  defp blank_to_default("", default), do: default
  defp blank_to_default(content, _default), do: content

  defp put_request_opt(opts, _key, nil), do: opts
  defp put_request_opt(opts, _key, ""), do: opts
  defp put_request_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp stringify(nil), do: nil
  defp stringify(value), do: to_string(value)

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_value), do: false
end
