defmodule Threadr.Ingest.Discord.Bot do
  @moduledoc """
  Starts the Discord ingestion runtime for a single bot pod.
  """

  use Supervisor

  def start_link(config) do
    Supervisor.start_link(__MODULE__, config, name: __MODULE__)
  end

  @impl true
  def init(config) do
    token =
      config
      |> Keyword.fetch!(:discord)
      |> Map.get(:token)

    if is_nil(token) or String.trim(token) == "" do
      raise "THREADR_DISCORD_TOKEN must be set for Discord ingestion"
    end

    Application.put_env(:nostrum, :token, token)
    Application.put_env(:nostrum, :ffmpeg, false)
    Application.put_env(:nostrum, :youtubedl, false)
    Application.put_env(:nostrum, :streamlink, false)
    Application.ensure_all_started(:nostrum)

    Threadr.Ingest.Discord.Consumer.put_config(config)

    children = [
      Threadr.Ingest.Discord.Consumer
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
