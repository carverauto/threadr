defmodule Threadr.TenantData.Ingest do
  @moduledoc """
  Persists normalized tenant-scoped chat events into Ash resources.
  """

  import Ash.Expr
  require Ash.Query

  alias Threadr.Events.{ChatMessage, Envelope}
  alias Threadr.Messaging.Topology

  alias Threadr.TenantData.{
    Actor,
    Channel,
    Graph,
    Message,
    MessageMention,
    Relationship,
    RelationshipObservation
  }

  @co_mentioned_relationship_type "CO_MENTIONED"
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
         {:ok, mention_result} <- persist_mentions(message, actor, chat_message, tenant_schema),
         :ok <-
           Graph.sync_message(
             message,
             actor,
             channel,
             mention_result.mentioned_actors,
             tenant_schema
           ),
         {:ok, inferred_relationships} <-
           persist_graph_inferences(message, chat_message.observed_at, tenant_schema),
         :ok <-
           Graph.sync_relationships(
             mention_result.relationships ++ inferred_relationships,
             tenant_schema
           ) do
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
    |> Enum.reduce_while({:ok, %{mentioned_actors: [], relationships: []}}, fn mention_handle,
                                                                               {:ok, acc} ->
      with {:ok, mentioned_actor} <-
             upsert_actor(chat_message.platform, mention_handle, tenant_schema),
           {:ok, _mention} <-
             create_message_mention(message.id, mentioned_actor.id, tenant_schema),
           {:ok, _observation, observation_status} <-
             create_relationship_observation(
               @relationship_type,
               actor.id,
               mentioned_actor.id,
               message.id,
               chat_message.observed_at,
               %{"source" => "chat.message"},
               tenant_schema
             ),
           {:ok, relationship} <-
             maybe_upsert_relationship(
               observation_status,
               @relationship_type,
               actor.id,
               mentioned_actor.id,
               message.id,
               chat_message.observed_at,
               %{"source" => "chat.message"},
               tenant_schema
             ) do
        {:cont,
         {:ok,
          %{
            mentioned_actors: [mentioned_actor | acc.mentioned_actors],
            relationships: maybe_prepend_relationship(acc.relationships, relationship)
          }}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, result} ->
        {:ok,
         %{
           mentioned_actors: Enum.reverse(result.mentioned_actors),
           relationships: Enum.reverse(result.relationships)
         }}

      error ->
        error
    end
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

      result ->
        result
    end
  end

  defp maybe_upsert_relationship(
         :created,
         relationship_type,
         from_actor_id,
         to_actor_id,
         source_message_id,
         observed_at,
         metadata,
         tenant_schema
       ) do
    upsert_relationship(
      relationship_type,
      from_actor_id,
      to_actor_id,
      source_message_id,
      observed_at,
      metadata,
      tenant_schema
    )
  end

  defp maybe_upsert_relationship(
         :existing,
         _relationship_type,
         _from_actor_id,
         _to_actor_id,
         _source_message_id,
         _observed_at,
         _metadata,
         _tenant_schema
       ) do
    {:ok, nil}
  end

  defp upsert_relationship(
         relationship_type,
         from_actor_id,
         to_actor_id,
         source_message_id,
         observed_at,
         metadata,
         tenant_schema
       ) do
    query =
      Relationship
      |> Ash.Query.filter(
        expr(
          from_actor_id == ^from_actor_id and
            to_actor_id == ^to_actor_id and
            relationship_type == ^relationship_type
        )
      )

    case Ash.read_one(query, tenant: tenant_schema) do
      {:ok, nil} ->
        Relationship
        |> Ash.Changeset.for_create(
          :create,
          %{
            relationship_type: relationship_type,
            weight: 1,
            first_seen_at: observed_at,
            last_seen_at: observed_at,
            metadata: metadata,
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
            metadata: metadata,
            source_message_id: source_message_id
          },
          tenant: tenant_schema
        )
        |> Ash.update()

      error ->
        error
    end
  end

  defp create_relationship_observation(
         relationship_type,
         from_actor_id,
         to_actor_id,
         source_message_id,
         observed_at,
         metadata,
         tenant_schema
       ) do
    query =
      RelationshipObservation
      |> Ash.Query.filter(
        expr(
          relationship_type == ^relationship_type and
            source_message_id == ^source_message_id and
            from_actor_id == ^from_actor_id and
            to_actor_id == ^to_actor_id
        )
      )

    case Ash.read_one(query, tenant: tenant_schema) do
      {:ok, nil} ->
        RelationshipObservation
        |> Ash.Changeset.for_create(
          :create,
          %{
            relationship_type: relationship_type,
            observed_at: observed_at,
            metadata: metadata,
            from_actor_id: from_actor_id,
            to_actor_id: to_actor_id,
            source_message_id: source_message_id
          },
          tenant: tenant_schema
        )
        |> Ash.create()
        |> case do
          {:ok, observation} -> {:ok, observation, :created}
          error -> error
        end

      {:ok, observation} ->
        {:ok, observation, :existing}

      error ->
        error
    end
  end

  defp persist_graph_inferences(message, observed_at, tenant_schema) do
    with {:ok, pairs} <- Graph.infer_co_mentions(message.id, tenant_schema) do
      Enum.reduce_while(pairs, {:ok, []}, fn {from_actor_id, to_actor_id}, {:ok, relationships} ->
        with {:ok, from_actor_uuid} <- Ecto.UUID.cast(from_actor_id),
             {:ok, to_actor_uuid} <- Ecto.UUID.cast(to_actor_id),
             {:ok, _observation, observation_status} <-
               create_relationship_observation(
                 @co_mentioned_relationship_type,
                 from_actor_uuid,
                 to_actor_uuid,
                 message.id,
                 observed_at,
                 %{"source" => "age.co_mentions"},
                 tenant_schema
               ),
             {:ok, relationship} <-
               maybe_upsert_relationship(
                 observation_status,
                 @co_mentioned_relationship_type,
                 from_actor_uuid,
                 to_actor_uuid,
                 message.id,
                 observed_at,
                 %{"source" => "age.co_mentions"},
                 tenant_schema
               ) do
          {:cont, {:ok, maybe_prepend_relationship(relationships, relationship)}}
        else
          error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, relationships} -> {:ok, Enum.reverse(relationships)}
        error -> error
      end
    end
  end

  defp maybe_prepend_relationship(relationships, nil), do: relationships
  defp maybe_prepend_relationship(relationships, relationship), do: [relationship | relationships]
end
