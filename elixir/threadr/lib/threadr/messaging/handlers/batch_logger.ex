defmodule Threadr.Messaging.Handlers.BatchLogger do
  @moduledoc """
  Placeholder batch handler for the initial rewrite scaffold.
  """

  require Logger

  def handle(batcher, messages) do
    ids = Enum.map(messages, & &1.data.id)

    Logger.info(
      "processed #{length(messages)} #{batcher} event(s) from JetStream: #{Enum.join(ids, ", ")}"
    )

    messages
  end
end
