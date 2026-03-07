defmodule Threadr.Messaging.Publisher do
  @moduledoc """
  Publishes normalized events to Threadr's JetStream subjects.
  """

  alias Threadr.Events.Envelope
  alias Threadr.Messaging.Topology

  def publish(%Envelope{} = envelope) do
    body = Threadr.Events.encode!(envelope)
    Gnat.pub(Topology.connection_name(), envelope.subject, body)
  end
end
