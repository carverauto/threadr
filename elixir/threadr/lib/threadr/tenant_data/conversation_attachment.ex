defmodule Threadr.TenantData.ConversationAttachment do
  @moduledoc """
  Attaches messages to persisted conversation state using message-link inference.
  """

  import Ash.Expr
  import Ecto.Query
  require Ash.Query

  alias Threadr.Repo

  alias Threadr.TenantData.{
    Actor,
    Conversation,
    ConversationMembership,
    Message,
    PendingItemTracking
  }

  @reconstruction_version "conversation-attachment-v1"
  @dormancy_gap_hours 6
  @active_gap_minutes 20

  def attach_message(message_id, tenant_schema, opts \\ [])
      when is_binary(message_id) and is_binary(tenant_schema) do
    with {:ok, message} <- fetch_message(message_id, tenant_schema),
         :ok <- mark_dormant_conversations(message, tenant_schema),
         {:ok, conversation} <- select_or_create_conversation(message, tenant_schema, opts) do
      if conversation do
        attach_message_to_conversation(conversation, message, tenant_schema, opts)
      else
        {:ok, nil}
      end
    end
  end

  def reconstruction_version, do: @reconstruction_version

  defp select_or_create_conversation(message, tenant_schema, opts) do
    inference = Keyword.get(opts, :inference)
    winner = inference && inference[:winner]

    linked_conversation =
      if winner, do: conversation_for_message(winner.target_message_id, tenant_schema), else: nil

    cond do
      leave_unattached?(message, inference) ->
        {:ok, nil}

      linked_conversation ->
        {:ok, linked_conversation}

      winner ->
        with {:ok, target_message} <- fetch_message(winner.target_message_id, tenant_schema),
             {:ok, conversation} <-
               create_conversation(target_message, tenant_schema, seed: :linked) do
          {:ok, conversation}
        end

      conversation = recent_active_conversation(message, tenant_schema) ->
        {:ok, conversation}

      true ->
        create_conversation(message, tenant_schema, seed: :starter)
    end
  end

  defp leave_unattached?(message, inference) when is_map(inference) do
    winner = inference[:winner]
    candidates = inference[:candidates] || []

    body_word_count =
      message.body
      |> to_string()
      |> String.split(~r/\s+/, trim: true)
      |> length()

    dialogue_act = get_in(message.metadata || %{}, ["dialogue_act", "label"])
    entity_names = Map.get(message, :entity_names, [])
    fact_types = Map.get(message, :fact_types, [])
    top_score = candidates |> List.first() |> then(fn row -> if row, do: row.score, else: 0.0 end)
    next_score = candidates |> Enum.at(1) |> then(fn row -> if row, do: row.score, else: 0.0 end)
    margin = max(top_score - next_score, 0.0)

    is_nil(winner) and
      length(candidates) >= 2 and
      top_score >= 0.2 and
      margin <= 0.05 and
      body_word_count <= 3 and
      is_nil(dialogue_act) and
      entity_names == [] and
      fact_types == []
  end

  defp leave_unattached?(_message, _inference), do: false

  defp attach_message_to_conversation(conversation, message, tenant_schema, opts) do
    inference = Keyword.get(opts, :inference)
    winner = inference && inference[:winner]
    attached_at = message.observed_at

    with {:ok, refreshed} <-
           maybe_refresh_conversation_state(conversation, message, tenant_schema),
         {:ok, conversation_membership} <-
           upsert_membership(
             refreshed,
             "message",
             message.id,
             message_membership_role(refreshed, message),
             (winner && winner.score) || 1.0,
             message_join_reason(winner, refreshed, message),
             membership_evidence(winner, message, "message"),
             attached_at,
             tenant_schema
           ),
         {:ok, _actor_membership} <-
           upsert_membership(
             refreshed,
             "actor",
             message.actor_id,
             actor_membership_role(refreshed, message),
             (winner && winner.score) || 1.0,
             message_join_reason(winner, refreshed, message),
             membership_evidence(winner, message, "actor"),
             attached_at,
             tenant_schema
           ),
         {:ok, updated} <-
           update_conversation_summary(refreshed, message, conversation_membership, tenant_schema),
         {:ok, tracked} <- PendingItemTracking.sync(updated, message, winner, tenant_schema) do
      {:ok, tracked}
    end
  end

  defp create_conversation(message, tenant_schema, opts) do
    seed = Keyword.get(opts, :seed, :starter)

    with {:ok, conversation} <-
           Conversation
           |> Ash.Changeset.for_create(
             :create,
             %{
               platform: message.platform,
               lifecycle_state: "active",
               opened_at: message.observed_at,
               last_message_at: message.observed_at,
               participant_summary: participant_summary([message]),
               entity_summary: entity_summary([message]),
               topic_summary: topic_summary([message]),
               confidence_summary: %{
                 "latest_link_score" => if(seed == :linked, do: 0.5, else: 1.0)
               },
               reconstruction_version: @reconstruction_version,
               metadata:
                 summary_refresh_metadata(%{
                   "seed" => Atom.to_string(seed),
                   "conversation_external_id" => conversation_external_id(message)
                 }),
               channel_id: message.channel_id,
               starter_message_id: message.id,
               most_recent_message_id: message.id
             },
             tenant: tenant_schema
           )
           |> Ash.create(),
         {:ok, _membership} <-
           upsert_membership(
             conversation,
             "message",
             message.id,
             "starter",
             1.0,
             "starter_message",
             membership_evidence(nil, message, "message"),
             message.observed_at,
             tenant_schema
           ),
         {:ok, _actor_membership} <-
           upsert_membership(
             conversation,
             "actor",
             message.actor_id,
             "starter",
             1.0,
             "starter_message",
             membership_evidence(nil, message, "actor"),
             message.observed_at,
             tenant_schema
           ) do
      {:ok, conversation}
    end
  end

  defp maybe_refresh_conversation_state(conversation, message, tenant_schema) do
    if dormant_for?(conversation, message.observed_at) do
      update_conversation(
        conversation,
        %{
          lifecycle_state: "revived",
          dormant_at: nil,
          metadata:
            Map.put(
              conversation.metadata || %{},
              "revived_at",
              encode_datetime(message.observed_at)
            )
        },
        tenant_schema
      )
    else
      {:ok, conversation}
    end
  end

  defp update_conversation_summary(conversation, message, membership, tenant_schema) do
    messages = conversation_messages(conversation.id, tenant_schema)

    updated_messages =
      if Enum.any?(messages, &(&1.id == message.id)), do: messages, else: messages ++ [message]

    update_conversation(
      conversation,
      %{
        lifecycle_state:
          if(conversation.lifecycle_state == "revived", do: "revived", else: "active"),
        last_message_at: message.observed_at,
        most_recent_message_id: message.id,
        participant_summary: participant_summary(updated_messages),
        entity_summary: entity_summary(updated_messages),
        topic_summary: topic_summary(updated_messages),
        confidence_summary: %{
          "latest_link_score" => membership.score,
          "message_count" => length(updated_messages)
        },
        reconstruction_version: @reconstruction_version,
        metadata:
          (conversation.metadata || %{})
          |> Map.put("conversation_external_id", conversation_external_id(message))
          |> summary_refresh_metadata()
      },
      tenant_schema
    )
  end

  defp update_conversation(conversation, attrs, tenant_schema) do
    conversation
    |> Ash.Changeset.for_update(:update, attrs, tenant: tenant_schema)
    |> Ash.update()
  end

  defp upsert_membership(
         conversation,
         member_kind,
         member_id,
         role,
         score,
         join_reason,
         evidence,
         attached_at,
         tenant_schema
       ) do
    query =
      ConversationMembership
      |> Ash.Query.filter(
        expr(
          conversation_id == ^conversation.id and
            member_kind == ^member_kind and
            member_id == ^member_id
        )
      )

    attrs = %{
      member_kind: member_kind,
      member_id: member_id,
      role: role,
      score: score,
      join_reason: join_reason,
      evidence: evidence,
      attached_at: attached_at,
      metadata: %{"reconstruction_version" => @reconstruction_version},
      conversation_id: conversation.id
    }

    case Ash.read_one(query, tenant: tenant_schema) do
      {:ok, nil} ->
        ConversationMembership
        |> Ash.Changeset.for_create(:create, attrs, tenant: tenant_schema)
        |> Ash.create()

      {:ok, membership} ->
        membership
        |> Ash.Changeset.for_update(
          :update,
          Map.take(attrs, [:role, :score, :join_reason, :evidence, :metadata]),
          tenant: tenant_schema
        )
        |> Ash.update()

      error ->
        error
    end
  end

  defp mark_dormant_conversations(message, tenant_schema) do
    stale_before = shift_datetime(message.observed_at, -@dormancy_gap_hours, :hour)

    Conversation
    |> Ash.Query.filter(
      expr(
        channel_id == ^message.channel_id and
          lifecycle_state in ["active", "revived"] and
          last_message_at < ^stale_before
      )
    )
    |> Ash.read!(tenant: tenant_schema)
    |> Enum.reduce_while(:ok, fn conversation, :ok ->
      case update_conversation(
             conversation,
             %{lifecycle_state: "dormant", dormant_at: message.observed_at},
             tenant_schema
           ) do
        {:ok, _updated} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
    |> case do
      :ok -> :ok
      error -> error
    end
  end

  defp recent_active_conversation(message, tenant_schema) do
    active_after = shift_datetime(message.observed_at, -@active_gap_minutes, :minute)

    Conversation
    |> Ash.Query.filter(
      expr(
        channel_id == ^message.channel_id and
          lifecycle_state in ["active", "revived"] and
          last_message_at >= ^active_after and
          last_message_at <= ^message.observed_at
      )
    )
    |> Ash.Query.sort(last_message_at: :desc)
    |> Ash.read!(tenant: tenant_schema)
    |> Enum.find(fn conversation ->
      (conversation.metadata || %{})["conversation_external_id"] ==
        conversation_external_id(message)
    end)
  end

  defp conversation_for_message(message_id, tenant_schema) do
    query =
      ConversationMembership
      |> Ash.Query.filter(expr(member_kind == "message" and member_id == ^message_id))

    case Ash.read_one(query, tenant: tenant_schema) do
      {:ok, nil} ->
        nil

      {:ok, membership} ->
        Conversation
        |> Ash.Query.filter(expr(id == ^membership.conversation_id))
        |> Ash.read_one!(tenant: tenant_schema)

      _ ->
        nil
    end
  end

  defp fetch_message(message_id, tenant_schema) do
    case Message
         |> Ash.Query.filter(expr(id == ^message_id))
         |> Ash.read_one(tenant: tenant_schema) do
      {:ok, nil} ->
        {:error, {:message_not_found, message_id}}

      {:ok, message} ->
        {:ok, enrich_message(message, tenant_schema)}

      error ->
        error
    end
  end

  defp enrich_message(message, tenant_schema) do
    actor =
      Actor
      |> Ash.Query.filter(expr(id == ^message.actor_id))
      |> Ash.read_one!(tenant: tenant_schema)

    entities =
      Repo.all(
        from(e in "extracted_entities",
          prefix: ^tenant_schema,
          where: e.source_message_id == ^dump_uuid!(message.id),
          order_by: [desc: e.confidence, asc: e.name],
          select: %{name: e.name, canonical_name: e.canonical_name, confidence: e.confidence}
        )
      )

    %{
      id: message.id,
      external_id: message.external_id,
      body: message.body,
      observed_at: message.observed_at,
      metadata: message.metadata || %{},
      actor_id: message.actor_id,
      actor_handle: actor.handle,
      actor_display_name: actor.display_name,
      channel_id: message.channel_id,
      platform: actor.platform,
      dialogue_act: (message.metadata || %{})["dialogue_act"] || %{},
      entity_names:
        entities
        |> Enum.map(&(&1.canonical_name || &1.name))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
    }
  end

  defp conversation_messages(conversation_id, tenant_schema) do
    message_ids =
      ConversationMembership
      |> Ash.Query.filter(expr(conversation_id == ^conversation_id and member_kind == "message"))
      |> Ash.read!(tenant: tenant_schema)
      |> Enum.map(& &1.member_id)

    Enum.map(message_ids, &fetch_message!(&1, tenant_schema))
  end

  defp fetch_message!(message_id, tenant_schema) do
    {:ok, message} = fetch_message(message_id, tenant_schema)
    message
  end

  defp participant_summary(messages) do
    actor_ids = Enum.map(messages, & &1.actor_id) |> Enum.uniq() |> Enum.sort()
    actor_handles = Enum.map(messages, & &1.actor_handle) |> Enum.uniq() |> Enum.sort()

    %{
      "actor_ids" => actor_ids,
      "actor_handles" => actor_handles,
      "actor_count" => length(actor_ids)
    }
  end

  defp entity_summary(messages) do
    names =
      messages
      |> Enum.flat_map(&(&1.entity_names || []))
      |> Enum.frequencies()

    %{"names" => Map.keys(names) |> Enum.sort(), "counts" => names}
  end

  defp topic_summary(messages) do
    messages
    |> Enum.flat_map(&(&1.entity_names || []))
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_name, count} -> -count end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.take(3)
    |> case do
      [] -> nil
      names -> Enum.join(names, ", ")
    end
  end

  defp message_membership_role(conversation, message) do
    if conversation.starter_message_id == message.id, do: "starter", else: "participant"
  end

  defp actor_membership_role(conversation, message) do
    if conversation.starter_message_id == message.id, do: "starter", else: "participant"
  end

  defp message_join_reason(nil, conversation, message) do
    if conversation.starter_message_id == message.id,
      do: "starter_message",
      else: "channel_continuity"
  end

  defp message_join_reason(winner, _conversation, _message), do: winner.link_type

  defp membership_evidence(nil, message, member_kind) do
    [
      %{
        "kind" => "seed",
        "weight" => 1.0,
        "value" => member_kind,
        "explanation" => "conversation membership created without an inferred parent link",
        "message_id" => message.id
      }
    ]
  end

  defp membership_evidence(winner, _message, _member_kind),
    do: normalize_evidence(winner.evidence)

  defp summary_refresh_metadata(metadata) do
    metadata
    |> Kernel.||(%{})
    |> Map.put("summary_needs_refresh", true)
    |> Map.put("summary_refresh_reason", "conversation_updated")
    |> Map.put("cluster_review_needs_refresh", true)
    |> Map.put("cluster_review_refresh_reason", "conversation_updated")
    |> Map.put("relationship_recompute_needs_refresh", true)
    |> Map.put("relationship_recompute_refresh_reason", "conversation_updated")
  end

  defp normalize_evidence(evidence) do
    Enum.map(evidence, fn item ->
      item
      |> Enum.map(fn {key, value} -> {to_string(key), value} end)
      |> Map.new()
    end)
  end

  defp conversation_external_id(message) do
    message.metadata["conversation_external_id"] || message.channel_id
  end

  defp dormant_for?(conversation, observed_at) do
    previous = conversation.last_message_at
    stale_before = shift_datetime(observed_at, -@dormancy_gap_hours, :hour)
    compare_datetimes(previous, stale_before) == :lt
  end

  defp encode_datetime(nil), do: nil
  defp encode_datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp encode_datetime(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)

  defp shift_datetime(%DateTime{} = value, amount, unit), do: DateTime.add(value, amount, unit)

  defp shift_datetime(%NaiveDateTime{} = value, amount, unit),
    do: NaiveDateTime.add(value, amount, unit)

  defp dump_uuid!(value), do: Ecto.UUID.dump!(value)

  defp compare_datetimes(nil, _other), do: :eq

  defp compare_datetimes(%DateTime{} = left, %DateTime{} = right),
    do: DateTime.compare(left, right)

  defp compare_datetimes(%NaiveDateTime{} = left, %NaiveDateTime{} = right),
    do: NaiveDateTime.compare(left, right)

  defp compare_datetimes(_left, _right), do: :eq
end
