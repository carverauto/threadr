defmodule Threadr.TenantData.Ingest do
  @moduledoc """
  Persists normalized tenant-scoped chat events into Ash resources.
  """

  import Ash.Expr
  require Ash.Query
  require Logger

  alias Threadr.Events.{ChatContextEvent, ChatMessage, Envelope}
  alias Threadr.Messaging.Topology
  alias Threadr.ML.Embeddings
  alias Threadr.ML.Embeddings.InlinePublisher

  alias Threadr.TenantData.{
    Alias,
    AliasObservation,
    Actor,
    Channel,
    ConversationAttachment,
    Extraction,
    Graph,
    LiveUpdates,
    ContextEvent,
    Message,
    MessageLinkInference,
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
           persist_chat_message(chat_message, envelope, tenant_subject_name, tenant.schema_name) do
      {:ok, persisted_message}
    end
  end

  def persist_envelope(
        %Envelope{type: "chat.context", data: %ChatContextEvent{} = context_event} = envelope
      ) do
    with {:ok, tenant_subject_name} <- Topology.tenant_subject_name_from_subject(envelope.subject),
         {:ok, tenant} <-
           Threadr.ControlPlane.get_tenant_by_subject_name(
             tenant_subject_name,
             context: %{system: true}
           ),
         {:ok, persisted_event} <-
           persist_chat_context_event(context_event, envelope, tenant.schema_name) do
      {:ok, persisted_event}
    end
  end

  def persist_envelope(%Envelope{type: type}) do
    {:error, {:unsupported_envelope_type, type}}
  end

  def persist_chat_message(
        %ChatMessage{} = chat_message,
        %Envelope{} = envelope,
        tenant_subject_name,
        tenant_schema
      ) do
    with {:ok, actor} <- upsert_actor(chat_message, tenant_schema),
         {:ok, channel} <-
           upsert_channel(chat_message.platform, chat_message.channel, tenant_schema),
         {:ok, message} <-
           upsert_message(chat_message, envelope, actor.id, channel.id, tenant_schema),
         {:ok, _alias_observations} <-
           persist_alias_observations(message, actor, channel, chat_message, tenant_schema),
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
           ),
         :ok <- maybe_embed_message(message, tenant_subject_name),
         :ok <-
           maybe_extract_message(
             message,
             tenant_subject_name,
             tenant_schema
           ),
         {:ok, inference_result} <-
           maybe_infer_message_links(message, tenant_schema, tenant_subject_name),
         :ok <-
           maybe_attach_message_to_conversation(
             message,
             inference_result,
             tenant_schema,
             tenant_subject_name
           ) do
      :ok =
        LiveUpdates.broadcast_message_persisted(tenant_subject_name, %{
          message_id: message.id,
          actor_id: actor.id,
          channel_id: channel.id,
          observed_at: chat_message.observed_at,
          actor_ids: [actor.id | Enum.map(mention_result.mentioned_actors, & &1.id)]
        })

      {:ok, message}
    end
  end

  defp upsert_actor(%ChatMessage{} = chat_message, tenant_schema) do
    platform = chat_message.platform
    handle = chat_message.actor
    display_name = Map.get(chat_message.metadata, "observed_display_name")
    external_id = Map.get(chat_message.metadata, "platform_actor_id")

    query =
      Actor
      |> Ash.Query.filter(expr(platform == ^platform and handle == ^handle))

    case Ash.read_one(query, tenant: tenant_schema) do
      {:ok, nil} ->
        Actor
        |> Ash.Changeset.for_create(
          :create,
          %{
            platform: platform,
            handle: handle,
            display_name: display_name,
            external_id: external_id,
            last_seen_at: chat_message.observed_at
          },
          tenant: tenant_schema
        )
        |> Ash.create()

      {:ok, actor} ->
        actor
        |> Ash.Changeset.for_update(
          :update,
          %{
            display_name: display_name || actor.display_name,
            external_id: external_id || actor.external_id,
            last_seen_at: chat_message.observed_at
          },
          tenant: tenant_schema
        )
        |> Ash.update()

      error ->
        error
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

  defp persist_chat_context_event(
         %ChatContextEvent{} = context_event,
         %Envelope{} = envelope,
         tenant_schema
       ) do
    with {:ok, actor} <- maybe_upsert_actor_for_context_event(context_event, tenant_schema),
         {:ok, channel} <- maybe_upsert_channel_for_context_event(context_event, tenant_schema),
         {:ok, source_message_id} <-
           source_message_id_for_context_event(context_event, tenant_schema),
         {:ok, persisted_event} <-
           upsert_context_event(
             context_event,
             envelope,
             actor && actor.id,
             channel && channel.id,
             source_message_id,
             tenant_schema
           ),
         {:ok, _alias_observations} <-
           persist_context_alias_observations(
             persisted_event,
             actor,
             channel,
             context_event,
             tenant_schema
           ) do
      {:ok, persisted_event}
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
          metadata:
            %{
              "subject" => envelope.subject,
              "source" => envelope.source,
              "correlation_id" => envelope.correlation_id
            }
            |> Map.merge(chat_message.metadata || %{}),
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

  defp maybe_upsert_actor_for_context_event(%ChatContextEvent{actor: nil}, _tenant_schema),
    do: {:ok, nil}

  defp maybe_upsert_actor_for_context_event(%ChatContextEvent{} = context_event, tenant_schema) do
    upsert_actor(
      %ChatMessage{
        platform: context_event.platform,
        channel: context_event.channel || "",
        actor: context_event.actor,
        body: "",
        observed_at: context_event.observed_at,
        mentions: [],
        metadata: context_event.metadata,
        raw: context_event.raw
      },
      tenant_schema
    )
  end

  defp maybe_upsert_channel_for_context_event(%ChatContextEvent{channel: nil}, _tenant_schema),
    do: {:ok, nil}

  defp maybe_upsert_channel_for_context_event(%ChatContextEvent{} = context_event, tenant_schema) do
    upsert_channel(context_event.platform, context_event.channel, tenant_schema)
  end

  defp source_message_id_for_context_event(%ChatContextEvent{} = context_event, tenant_schema) do
    case Map.get(context_event.metadata, "source_message_external_id") do
      nil ->
        {:ok, nil}

      external_id ->
        query =
          Message
          |> Ash.Query.filter(expr(external_id == ^external_id))

        case Ash.read_one(query, tenant: tenant_schema) do
          {:ok, nil} -> {:ok, nil}
          {:ok, message} -> {:ok, message.id}
          error -> error
        end
    end
  end

  defp upsert_context_event(
         %ChatContextEvent{} = context_event,
         %Envelope{} = envelope,
         actor_id,
         channel_id,
         source_message_id,
         tenant_schema
       ) do
    query =
      ContextEvent
      |> Ash.Query.filter(expr(external_id == ^envelope.id))

    case Ash.read_one(query, tenant: tenant_schema) do
      {:ok, nil} ->
        ContextEvent
        |> Ash.Changeset.for_create(
          :create,
          %{
            external_id: envelope.id,
            platform: context_event.platform,
            event_type: context_event.event_type,
            observed_at: context_event.observed_at,
            raw: context_event.raw,
            metadata:
              %{
                "subject" => envelope.subject,
                "source" => envelope.source,
                "correlation_id" => envelope.correlation_id
              }
              |> Map.merge(context_event.metadata || %{}),
            actor_id: actor_id,
            channel_id: channel_id,
            source_message_id: source_message_id
          },
          tenant: tenant_schema
        )
        |> Ash.create()

      result ->
        result
    end
  end

  defp persist_alias_observations(
         message,
         actor,
         channel,
         %ChatMessage{} = chat_message,
         tenant_schema
       ) do
    chat_message
    |> alias_candidates(actor)
    |> Enum.reduce_while({:ok, []}, fn alias_attrs, {:ok, observations} ->
      with {:ok, alias_record} <-
             upsert_alias(
               chat_message.platform,
               chat_message.observed_at,
               actor,
               alias_attrs,
               alias_metadata(chat_message.metadata),
               tenant_schema
             ),
           {:ok, observation} <-
             create_alias_observation(
               alias_record,
               actor,
               channel,
               message,
               chat_message,
               tenant_schema
             ) do
        {:cont, {:ok, [observation | observations]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, observations} -> {:ok, Enum.reverse(observations)}
      error -> error
    end
  end

  defp persist_context_alias_observations(
         _context_event_record,
         nil,
         _channel,
         %ChatContextEvent{},
         _tenant_schema
       ) do
    {:ok, []}
  end

  defp persist_context_alias_observations(
         context_event_record,
         actor,
         channel,
         %ChatContextEvent{} = context_event,
         tenant_schema
       ) do
    context_event
    |> context_alias_candidates(actor)
    |> Enum.reduce_while({:ok, []}, fn alias_attrs, {:ok, observations} ->
      with {:ok, alias_record} <-
             upsert_alias(
               context_event.platform,
               context_event.observed_at,
               actor,
               alias_attrs,
               alias_metadata(context_event.metadata),
               tenant_schema
             ),
           {:ok, observation} <-
             create_context_alias_observation(
               alias_record,
               actor,
               channel,
               context_event_record,
               context_event,
               tenant_schema
             ) do
        {:cont, {:ok, [observation | observations]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, observations} -> {:ok, Enum.reverse(observations)}
      error -> error
    end
  end

  defp alias_candidates(%ChatMessage{} = chat_message, actor) do
    [
      %{
        value: Map.get(chat_message.metadata, "observed_handle") || actor.handle,
        alias_kind: "handle"
      },
      %{
        value: Map.get(chat_message.metadata, "observed_display_name"),
        alias_kind: "display_name"
      }
    ]
    |> Enum.reject(fn %{value: value} -> blank?(value) end)
    |> Enum.uniq_by(fn %{value: value, alias_kind: alias_kind} ->
      {alias_kind, normalize_alias_value(value)}
    end)
  end

  defp context_alias_candidates(%ChatContextEvent{} = context_event, actor) do
    [
      %{
        value: Map.get(context_event.metadata, "observed_handle") || actor.handle,
        alias_kind: "handle"
      },
      %{
        value: Map.get(context_event.metadata, "observed_display_name"),
        alias_kind: "display_name"
      },
      %{
        value: Map.get(context_event.metadata, "new_handle"),
        alias_kind: "handle"
      }
    ]
    |> Enum.reject(fn %{value: value} -> blank?(value) end)
    |> Enum.uniq_by(fn %{value: value, alias_kind: alias_kind} ->
      {alias_kind, normalize_alias_value(value)}
    end)
  end

  defp upsert_alias(platform, observed_at, actor, alias_attrs, metadata, tenant_schema) do
    normalized_value = normalize_alias_value(alias_attrs.value)

    query =
      Alias
      |> Ash.Query.filter(
        expr(
          platform == ^platform and
            alias_kind == ^alias_attrs.alias_kind and
            normalized_value == ^normalized_value
        )
      )

    attrs = %{
      platform: platform,
      value: alias_attrs.value,
      normalized_value: normalized_value,
      alias_kind: alias_attrs.alias_kind,
      metadata: metadata,
      first_seen_at: observed_at,
      last_seen_at: observed_at,
      actor_id: actor.id
    }

    case Ash.read_one(query, tenant: tenant_schema) do
      {:ok, nil} ->
        Alias
        |> Ash.Changeset.for_create(:create, attrs, tenant: tenant_schema)
        |> Ash.create()

      {:ok, alias_record} ->
        alias_record
        |> Ash.Changeset.for_update(
          :update,
          %{metadata: attrs.metadata, last_seen_at: observed_at, actor_id: actor.id},
          tenant: tenant_schema
        )
        |> Ash.update()

      error ->
        error
    end
  end

  defp create_alias_observation(
         alias_record,
         actor,
         channel,
         message,
         %ChatMessage{} = chat_message,
         tenant_schema
       ) do
    query =
      AliasObservation
      |> Ash.Query.filter(expr(alias_id == ^alias_record.id and source_message_id == ^message.id))

    case Ash.read_one(query, tenant: tenant_schema) do
      {:ok, nil} ->
        AliasObservation
        |> Ash.Changeset.for_create(
          :create,
          %{
            observed_at: chat_message.observed_at,
            source_event_type: "message",
            platform_account_id: Map.get(chat_message.metadata, "platform_actor_id"),
            metadata:
              alias_metadata(chat_message.metadata)
              |> Map.put("source", "chat.message")
              |> Map.put(
                "platform_channel_id",
                Map.get(chat_message.metadata, "platform_channel_id")
              ),
            alias_id: alias_record.id,
            actor_id: actor.id,
            channel_id: channel.id,
            source_message_id: message.id
          },
          tenant: tenant_schema
        )
        |> Ash.create()

      result ->
        result
    end
  end

  defp create_context_alias_observation(
         alias_record,
         actor,
         channel,
         context_event_record,
         %ChatContextEvent{} = context_event,
         tenant_schema
       ) do
    query =
      AliasObservation
      |> Ash.Query.filter(
        expr(alias_id == ^alias_record.id and source_context_event_id == ^context_event_record.id)
      )

    case Ash.read_one(query, tenant: tenant_schema) do
      {:ok, nil} ->
        AliasObservation
        |> Ash.Changeset.for_create(
          :create,
          %{
            observed_at: context_event.observed_at,
            source_event_type: alias_source_event_type(context_event.event_type),
            platform_account_id: Map.get(context_event.metadata, "platform_actor_id"),
            metadata:
              alias_metadata(context_event.metadata)
              |> Map.put("source", "chat.context")
              |> Map.put("context_event_type", context_event.event_type)
              |> maybe_put(
                "platform_channel_id",
                Map.get(context_event.metadata, "platform_channel_id")
              ),
            alias_id: alias_record.id,
            actor_id: actor.id,
            channel_id: channel && channel.id,
            source_context_event_id: context_event_record.id
          },
          tenant: tenant_schema
        )
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

  defp alias_metadata(metadata) when is_map(metadata) do
    %{
      "observed_handle" => Map.get(metadata, "observed_handle"),
      "observed_display_name" => Map.get(metadata, "observed_display_name")
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp alias_source_event_type("presence_snapshot"), do: "presence"

  defp alias_source_event_type(event_type)
       when event_type in ["thread_create", "thread_update", "thread_delete"] do
    "thread_event"
  end

  defp alias_source_event_type(event_type), do: event_type

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_embed_message(message, tenant_subject_name) do
    case Embeddings.generate_for_message(message, tenant_subject_name, publisher: InlinePublisher) do
      {:ok, _envelope} ->
        :ok

      {:error, :embedding_provider_not_configured} ->
        :ok

      {:error, :blank_text} ->
        :ok

      {:error, reason} ->
        Logger.warning("message embedding failed for #{tenant_subject_name}: #{inspect(reason)}")
        :ok
    end
  end

  defp maybe_extract_message(message, tenant_subject_name, tenant_schema) do
    if Extraction.enabled?() do
      case Extraction.extract_and_persist_message(message, tenant_subject_name, tenant_schema) do
        {:ok, _result} ->
          :ok

        {:error, :generation_provider_not_configured} ->
          :ok

        {:error, :extraction_provider_not_configured} ->
          :ok

        {:error, reason} ->
          log_extraction_failure(tenant_subject_name, reason)
          :ok
      end
    else
      :ok
    end
  end

  defp maybe_infer_message_links(message, tenant_schema, tenant_subject_name) do
    case MessageLinkInference.infer_and_persist(message.id, tenant_schema) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        Logger.warning(
          "message link inference failed for #{tenant_subject_name}: #{inspect(reason)}"
        )

        {:ok, %{winner: nil, persisted: nil, candidates: []}}
    end
  end

  defp maybe_attach_message_to_conversation(
         message,
         inference_result,
         tenant_schema,
         tenant_subject_name
       ) do
    case ConversationAttachment.attach_message(message.id, tenant_schema,
           inference: inference_result
         ) do
      {:ok, _conversation} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "conversation attachment failed for #{tenant_subject_name}: #{inspect(reason)}"
        )

        :ok
    end
  end

  defp log_extraction_failure(tenant_subject_name, reason) do
    if extraction_timeout?(reason) do
      Logger.info(
        "message extraction timed out for #{tenant_subject_name}; continuing without extraction"
      )
    else
      Logger.warning("message extraction failed for #{tenant_subject_name}: #{inspect(reason)}")
    end
  end

  defp extraction_timeout?({:generation_request_failed, status, _body}) when status in [408, 504],
    do: true

  defp extraction_timeout?({:generation_failed, reason}), do: timeout_reason?(reason)
  defp extraction_timeout?(_reason), do: false

  defp timeout_reason?(reason) when is_atom(reason), do: reason == :timeout

  defp timeout_reason?(reason) when is_binary(reason) do
    String.contains?(String.downcase(reason), "timeout")
  end

  defp timeout_reason?({:timeout, _detail}), do: true
  defp timeout_reason?(_reason), do: false

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_value), do: false

  defp normalize_alias_value(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end
end
