defmodule Threadr.TenantData.Ingest do
  @moduledoc """
  Persists normalized tenant-scoped chat events into Ash resources.
  """

  import Ash.Expr
  require Ash.Query

  alias Threadr.Events.{ChatMessage, Envelope}
  alias Threadr.Messaging.Topology
  alias Threadr.TenantData.{Actor, Channel, Message, MessageMention, Relationship}

  @relationship_type "MENTIONED"

  def persist_envelope(
        %Envelope{type: "chat.message", data: %ChatMessage{} = chat_message} = envelope
      ) do
    with {:ok, tenant_subject_name} <- Topology.tenant_subject_name_from_subject(envelope.subject),
         {:ok, tenant} <-
           Threadr.ControlPlane.get_tenant_by_subject_name(
             tenant_subject_name,
             context: %{system: true}
           ),
         {:ok, persisted_message} <-
           persist_chat_message(chat_message, envelope, tenant.schema_name) do
      {:ok, persisted_message}
    end
  end

  def persist_envelope(%Envelope{type: type}) do
    {:error, {:unsupported_envelope_type, type}}
  end

  def persist_chat_message(%ChatMessage{} = chat_message, %Envelope{} = envelope, tenant_schema) do
    with {:ok, actor} <- upsert_actor(chat_message.platform, chat_message.actor, tenant_schema),
         {:ok, channel} <-
           upsert_channel(chat_message.platform, chat_message.channel, tenant_schema),
         {:ok, message} <-
           upsert_message(chat_message, envelope, actor.id, channel.id, tenant_schema),
         {:ok, _mentions} <- persist_mentions(message, actor, chat_message, tenant_schema) do
      {:ok, message}
    end
  end

  defp upsert_actor(platform, handle, tenant_schema) do
    query =
      Actor
      |> Ash.Query.filter(expr(platform == ^platform and handle == ^handle))

    case Ash.read_one(query, tenant: tenant_schema) do
      {:ok, nil} ->
        Actor
        |> Ash.Changeset.for_create(:create, %{platform: platform, handle: handle},
          tenant: tenant_schema
        )
        |> Ash.create()

      result ->
        result
    end
  end

  defp upsert_channel(platform, name, tenant_schema) do
    query =
      Channel
      |> Ash.Query.filter(expr(platform == ^platform and name == ^name))

    case Ash.read_one(query, tenant: tenant_schema) do
      {:ok, nil} ->
        Channel
        |> Ash.Changeset.for_create(:create, %{platform: platform, name: name},
          tenant: tenant_schema
        )
        |> Ash.create()

      result ->
        result
    end
  end

  defp upsert_message(chat_message, envelope, actor_id, channel_id, tenant_schema) do
    query =
      Message
      |> Ash.Query.filter(expr(channel_id == ^channel_id and external_id == ^envelope.id))

    case Ash.read_one(query, tenant: tenant_schema) do
      {:ok, nil} ->
        attrs = %{
          external_id: envelope.id,
          body: chat_message.body,
          observed_at: chat_message.observed_at,
          raw: chat_message.raw,
          metadata: %{
            "subject" => envelope.subject,
            "source" => envelope.source,
            "correlation_id" => envelope.correlation_id
          },
          actor_id: actor_id,
          channel_id: channel_id
        }

        Message
        |> Ash.Changeset.for_create(:create, attrs, tenant: tenant_schema)
        |> Ash.create()

      result ->
        result
    end
  end

  defp persist_mentions(message, actor, chat_message, tenant_schema) do
    chat_message.mentions
    |> Enum.reject(&(&1 == actor.handle))
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn mention_handle, {:ok, acc} ->
      with {:ok, mentioned_actor} <-
             upsert_actor(chat_message.platform, mention_handle, tenant_schema),
           {:ok, _mention, mention_status} <-
             create_message_mention(message.id, mentioned_actor.id, tenant_schema),
           {:ok, _relationship} <-
             maybe_upsert_relationship(
               mention_status,
               actor.id,
               mentioned_actor.id,
               message.id,
               chat_message.observed_at,
               tenant_schema
             ) do
        {:cont, {:ok, [mentioned_actor | acc]}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp create_message_mention(message_id, actor_id, tenant_schema) do
    query =
      MessageMention
      |> Ash.Query.filter(expr(message_id == ^message_id and actor_id == ^actor_id))

    case Ash.read_one(query, tenant: tenant_schema) do
      {:ok, nil} ->
        MessageMention
        |> Ash.Changeset.for_create(:create, %{message_id: message_id, actor_id: actor_id},
          tenant: tenant_schema
        )
        |> Ash.create()
        |> case do
          {:ok, mention} -> {:ok, mention, :created}
          error -> error
        end

      result ->
        case result do
          {:ok, mention} -> {:ok, mention, :existing}
          error -> error
        end
    end
  end

  defp maybe_upsert_relationship(
         :created,
         from_actor_id,
         to_actor_id,
         source_message_id,
         observed_at,
         tenant_schema
       ) do
    upsert_relationship(
      from_actor_id,
      to_actor_id,
      source_message_id,
      observed_at,
      tenant_schema
    )
  end

  defp maybe_upsert_relationship(
         :existing,
         _from_actor_id,
         _to_actor_id,
         _source_message_id,
         _observed_at,
         _tenant_schema
       ) do
    {:ok, :duplicate_message_mention}
  end

  defp upsert_relationship(
         from_actor_id,
         to_actor_id,
         source_message_id,
         observed_at,
         tenant_schema
       ) do
    query =
      Relationship
      |> Ash.Query.filter(
        expr(
          from_actor_id == ^from_actor_id and
            to_actor_id == ^to_actor_id and
            relationship_type == ^@relationship_type
        )
      )

    case Ash.read_one(query, tenant: tenant_schema) do
      {:ok, nil} ->
        Relationship
        |> Ash.Changeset.for_create(
          :create,
          %{
            relationship_type: @relationship_type,
            weight: 1,
            first_seen_at: observed_at,
            last_seen_at: observed_at,
            metadata: %{"source" => "chat.message"},
            from_actor_id: from_actor_id,
            to_actor_id: to_actor_id,
            source_message_id: source_message_id
          },
          tenant: tenant_schema
        )
        |> Ash.create()

      {:ok, relationship} ->
        relationship
        |> Ash.Changeset.for_update(
          :update,
          %{
            weight: relationship.weight + 1,
            last_seen_at: observed_at,
            source_message_id: source_message_id
          },
          tenant: tenant_schema
        )
        |> Ash.update()

      error ->
        error
    end
  end
end
