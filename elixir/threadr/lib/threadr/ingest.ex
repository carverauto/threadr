defmodule Threadr.Ingest do
  @moduledoc """
  Shared helpers for platform ingestion runtimes that publish normalized chat
  events into JetStream.
  """

  alias Threadr.Events.{ChatMessage, Envelope}
  alias Threadr.Messaging.Topology

  @mention_regex ~r/(?:^|\s)@([a-zA-Z0-9_.-]+)/

  def config do
    Application.fetch_env!(:threadr, Threadr.Ingest)
  end

  def enabled?(config \\ config()) do
    Keyword.get(config, :enabled, false)
  end

  def platform(config \\ config()) do
    Keyword.get(config, :platform)
  end

  def child_specs(config \\ config())

  def child_specs(config) do
    if enabled?(config) do
      validate_common_config!(config)

      case platform(config) do
        "irc" ->
          [{Threadr.Ingest.IRC.Agent, config}]

        "discord" ->
          [{Threadr.Ingest.Discord.Bot, config}]

        other ->
          raise "unsupported ingest platform #{inspect(other)}"
      end
    else
      []
    end
  end

  def publish_chat_message(config, attrs) do
    platform = fetch!(attrs, :platform)
    body = fetch!(attrs, :body)
    tenant_subject_name = Keyword.fetch!(config, :tenant_subject_name)
    mentions = normalize_mentions(fetch(attrs, :mentions, []) ++ extract_mentions(body))

    chat_message =
      ChatMessage.from_map(%{
        platform: platform,
        channel: fetch!(attrs, :channel),
        actor: fetch!(attrs, :actor),
        body: body,
        observed_at: fetch(attrs, :observed_at, DateTime.utc_now() |> DateTime.truncate(:second)),
        mentions: mentions,
        raw: fetch(attrs, :raw, %{})
      })

    envelope =
      Envelope.new(
        chat_message,
        "chat.message",
        Topology.subject_for(:chat_messages, tenant_subject_name),
        %{
          id: fetch(attrs, :external_id, Ecto.UUID.generate()),
          source: "threadr.ingest.#{platform}",
          metadata: message_metadata(config, attrs)
        }
      )

    publish_with(config, envelope)
  end

  def channel_allowed?(configured_channels, channel) when is_list(configured_channels) do
    configured_channels == [] or
      Enum.any?(configured_channels, fn configured ->
        normalize_channel(configured) == normalize_channel(channel)
      end)
  end

  def extract_mentions(body) when is_binary(body) do
    @mention_regex
    |> Regex.scan(body, capture: :all_but_first)
    |> List.flatten()
    |> normalize_mentions()
  end

  def normalize_mentions(handles) when is_list(handles) do
    handles
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  def validate_common_config!(config) do
    tenant_subject_name = Keyword.get(config, :tenant_subject_name)
    platform = platform(config)

    if is_nil(platform) or platform == "" do
      raise "THREADR_PLATFORM must be set when ingestion is enabled"
    end

    if is_nil(tenant_subject_name) or tenant_subject_name == "" do
      raise "THREADR_TENANT_SUBJECT must be set when ingestion is enabled"
    end

    :ok
  end

  def publish_with(config, envelope) do
    case publisher(config) do
      {module, arg} -> module.publish(envelope, arg)
      module -> module.publish(envelope)
    end
  end

  defp publisher(config) do
    Keyword.get(config, :publisher, Threadr.Messaging.Publisher)
  end

  defp message_metadata(config, attrs) do
    %{
      "bot_id" => Keyword.get(config, :bot_id),
      "tenant_id" => Keyword.get(config, :tenant_id),
      "platform_message_id" => fetch(attrs, :platform_message_id),
      "platform_channel_id" => fetch(attrs, :platform_channel_id)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_channel(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_channel(value), do: value |> to_string() |> normalize_channel()

  defp fetch!(attrs, key) do
    fetch(attrs, key) || raise ArgumentError, "missing required key #{inspect(key)}"
  end

  defp fetch(attrs, key, default \\ nil)

  defp fetch(attrs, key, default) when is_list(attrs) do
    Keyword.get(attrs, key, default)
  end

  defp fetch(attrs, key, default) when is_map(attrs) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key)) || default
  end
end
