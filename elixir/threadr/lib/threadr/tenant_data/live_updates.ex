defmodule Threadr.TenantData.LiveUpdates do
  @moduledoc """
  Tenant-scoped PubSub notifications for analyst-facing LiveView updates.
  """

  alias Phoenix.PubSub

  @type persisted_message_event :: %{
          required(:event) => :message_persisted,
          required(:tenant_subject_name) => String.t(),
          required(:message_id) => String.t(),
          required(:actor_id) => String.t(),
          required(:channel_id) => String.t(),
          required(:actor_ids) => [String.t()]
        }

  def subscribe(tenant_subject_name) when is_binary(tenant_subject_name) do
    PubSub.subscribe(Threadr.PubSub, topic(tenant_subject_name))
  end

  def broadcast_message_persisted(tenant_subject_name, attrs)
      when is_binary(tenant_subject_name) and is_map(attrs) do
    actor_ids =
      attrs
      |> Map.get(:actor_ids, [])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    payload = %{
      event: :message_persisted,
      tenant_subject_name: tenant_subject_name,
      message_id: Map.fetch!(attrs, :message_id),
      actor_id: Map.fetch!(attrs, :actor_id),
      channel_id: Map.fetch!(attrs, :channel_id),
      actor_ids: actor_ids
    }

    PubSub.broadcast(Threadr.PubSub, topic(tenant_subject_name), {:tenant_ingest, payload})
  end

  def relevant_to_dossier?(%{type: "message", focal: focal}, %{message_id: message_id}) do
    normalize_id(focal["id"] || focal[:id]) == normalize_id(message_id)
  end

  def relevant_to_dossier?(%{type: "channel", focal: focal}, %{channel_id: channel_id}) do
    normalize_id(focal["id"] || focal[:id]) == normalize_id(channel_id)
  end

  def relevant_to_dossier?(%{type: "actor", focal: focal}, %{actor_ids: actor_ids}) do
    normalize_id(focal["id"] || focal[:id]) in Enum.map(actor_ids, &normalize_id/1)
  end

  def relevant_to_dossier?(_dossier, _payload), do: false

  defp topic(tenant_subject_name), do: "tenant:" <> tenant_subject_name <> ":ingest"

  defp normalize_id(value) when is_binary(value), do: value
  defp normalize_id(value), do: to_string(value)
end
