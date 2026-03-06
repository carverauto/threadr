defmodule Threadr.Messaging.Pipeline do
  @moduledoc """
  Broadway pipeline for JetStream-backed Threadr events.
  """

  use Broadway

  require Logger

  alias Broadway.Message
  alias Threadr.Messaging.Handlers.{BatchLogger, Commands}
  alias Threadr.Messaging.Topology

  def start_link(_opts \\ []) do
    broadway = Topology.broadway_config()
    producer_options = jetstream_producer_options(broadway)

    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module:
          {OffBroadway.Jetstream.Producer,
           [
             connection_name: Topology.connection_name(),
             stream_name: Topology.stream_name(),
             consumer_name: Topology.consumer_name()
           ] ++ producer_options},
        concurrency: Keyword.fetch!(broadway, :producer_concurrency)
      ],
      processors: [
        default: [concurrency: Keyword.fetch!(broadway, :processor_concurrency)]
      ],
      batchers: [
        embeddings: batch_options(broadway),
        graph: batch_options(broadway),
        commands: batch_options(broadway),
        default: batch_options(broadway)
      ]
    )
  end

  @impl true
  def handle_message(_processor, %Message{} = message, _context) do
    case Threadr.Events.decode_envelope(message.data) do
      {:ok, event} ->
        message
        |> Message.update_data(fn _ -> event end)
        |> Message.put_batcher(batcher_for(event.type))

      {:error, reason} ->
        Logger.warning("dropping malformed JetStream payload: #{inspect(reason)}")
        Message.failed(message, reason)
    end
  end

  @impl true
  def handle_batch(:graph, messages, _batch_info, _context) do
    Enum.map(messages, fn message ->
      case Threadr.TenantData.Ingest.persist_envelope(message.data) do
        {:ok, _persisted} ->
          message

        {:error, reason} ->
          Logger.error("failed to persist tenant event: #{inspect(reason)}")
          Message.failed(message, reason)
      end
    end)
  end

  @impl true
  def handle_batch(:embeddings, messages, _batch_info, _context) do
    Enum.map(messages, fn message ->
      case Threadr.TenantData.Processing.persist_envelope(message.data) do
        {:ok, _persisted} ->
          message

        {:error, reason} ->
          Logger.error("failed to persist processing result: #{inspect(reason)}")
          Message.failed(message, reason)
      end
    end)
  end

  @impl true
  def handle_batch(:commands, messages, _batch_info, _context) do
    Enum.map(messages, fn message ->
      case Commands.handle_envelope(message.data) do
        {:ok, _handled} ->
          message

        {:error, reason} ->
          Logger.error("failed to handle ingest command: #{inspect(reason)}")
          Message.failed(message, reason)
      end
    end)
  end

  @impl true
  def handle_batch(batcher, messages, _batch_info, _context) do
    BatchLogger.handle(batcher, messages)
  end

  @impl true
  def handle_failed(messages, _context) do
    Enum.each(messages, fn message ->
      Logger.warning("message failed in Broadway pipeline: #{inspect(message.status)}")
    end)

    messages
  end

  defp batcher_for("chat.message"), do: :graph
  defp batcher_for("ingest.command"), do: :commands
  defp batcher_for("processing.result"), do: :embeddings
  defp batcher_for(_type), do: :default

  defp batch_options(broadway) do
    [
      concurrency: 1,
      batch_size: Keyword.fetch!(broadway, :batch_size),
      batch_timeout: Keyword.fetch!(broadway, :batch_timeout)
    ]
  end

  defp jetstream_producer_options(broadway) do
    Keyword.take(broadway, [:receive_interval, :receive_timeout, :on_success, :on_failure])
  end
end
