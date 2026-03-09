defmodule Threadr.TenantData.ConversationRelationshipRecompute do
  @moduledoc """
  Recomputes actor relationship weights from reconstructed conversation evidence.
  """

  import Ash.Expr
  import Ecto.Query
  require Ash.Query

  alias Threadr.Repo

  alias Threadr.TenantData.{
    Conversation,
    ConversationMembership,
    Graph,
    PendingItem,
    Relationship
  }

  @review_version "conversation-relationship-v1"
  @interaction_type "INTERACTED_WITH"
  @answered_type "ANSWERED"
  @decay_half_life_days 14.0

  def recompute_conversation_relationships(conversation_id, tenant_schema)
      when is_binary(conversation_id) and is_binary(tenant_schema) do
    with {:ok, conversation} <- fetch_conversation(conversation_id, tenant_schema),
         actor_ids when length(actor_ids) >= 2 <-
           conversation_actor_ids(conversation.id, tenant_schema),
         {:ok, relationships} <- recompute_actor_pairs(actor_ids, tenant_schema),
         :ok <- Graph.sync_relationships(relationships, tenant_schema),
         {:ok, updated_conversation} <- mark_conversation_recomputed(conversation, tenant_schema) do
      {:ok, %{conversation: updated_conversation, relationships: relationships}}
    else
      [] ->
        with {:ok, conversation} <- fetch_conversation(conversation_id, tenant_schema),
             {:ok, updated_conversation} <-
               mark_conversation_recomputed(conversation, tenant_schema) do
          {:ok, %{conversation: updated_conversation, relationships: []}}
        end

      [_single_actor] ->
        with {:ok, conversation} <- fetch_conversation(conversation_id, tenant_schema),
             {:ok, updated_conversation} <-
               mark_conversation_recomputed(conversation, tenant_schema) do
          {:ok, %{conversation: updated_conversation, relationships: []}}
        end

      error ->
        error
    end
  end

  def pending_conversation_ids(tenant_schema, limit \\ 10)
      when is_binary(tenant_schema) and is_integer(limit) and limit > 0 do
    from(c in "conversations",
      where:
        fragment(
          "coalesce((?->>?)::boolean, false)",
          c.metadata,
          "relationship_recompute_needs_refresh"
        ),
      order_by: [asc: c.last_message_at, asc: c.inserted_at],
      limit: ^limit,
      select: c.id
    )
    |> Repo.all(prefix: tenant_schema)
    |> Enum.map(&Ecto.UUID.cast!/1)
  end

  def relationship_types, do: [@interaction_type, @answered_type]
  def recompute_version, do: @review_version

  defp fetch_conversation(conversation_id, tenant_schema) do
    case Conversation
         |> Ash.Query.filter(expr(id == ^conversation_id))
         |> Ash.read_one(tenant: tenant_schema) do
      {:ok, nil} -> {:error, {:conversation_not_found, conversation_id}}
      {:ok, conversation} -> {:ok, conversation}
      error -> error
    end
  end

  defp conversation_actor_ids(conversation_id, tenant_schema) do
    ConversationMembership
    |> Ash.Query.filter(expr(conversation_id == ^conversation_id and member_kind == "actor"))
    |> Ash.read!(tenant: tenant_schema)
    |> Enum.map(& &1.member_id)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp recompute_actor_pairs(actor_ids, tenant_schema) do
    ordered_pairs = ordered_pairs(actor_ids)

    relationships =
      Enum.flat_map(ordered_pairs, fn {from_actor_id, to_actor_id} ->
        shared_conversations = shared_conversations(from_actor_id, to_actor_id, tenant_schema)

        interacted =
          case build_interaction_relationship(
                 from_actor_id,
                 to_actor_id,
                 shared_conversations
               ) do
            nil -> []
            relationship -> [relationship]
          end

        answered =
          case build_answered_relationship(
                 from_actor_id,
                 to_actor_id,
                 shared_conversations
               ) do
            nil -> []
            relationship -> [relationship]
          end

        interacted ++ answered
      end)

    persisted =
      Enum.reduce_while(relationships, {:ok, []}, fn attrs, {:ok, acc} ->
        case upsert_relationship(attrs, tenant_schema) do
          {:ok, relationship} -> {:cont, {:ok, [relationship | acc]}}
          error -> {:halt, error}
        end
      end)

    case persisted do
      {:ok, relationships} -> {:ok, Enum.reverse(relationships)}
      error -> error
    end
  end

  defp shared_conversations(from_actor_id, to_actor_id, tenant_schema) do
    query =
      from(c in "conversations",
        join: cm1 in "conversation_memberships",
        on: cm1.conversation_id == c.id and cm1.member_kind == "actor",
        join: cm2 in "conversation_memberships",
        on: cm2.conversation_id == c.id and cm2.member_kind == "actor",
        where: cm1.member_id == ^from_actor_id and cm2.member_id == ^to_actor_id,
        order_by: [desc: c.last_message_at],
        select: %{
          id: c.id,
          opened_at: c.opened_at,
          last_message_at: c.last_message_at,
          most_recent_message_id: c.most_recent_message_id,
          participant_summary: c.participant_summary,
          entity_summary: c.entity_summary,
          topic_summary: c.topic_summary,
          metadata: c.metadata
        }
      )

    conversations =
      query
      |> Repo.all(prefix: tenant_schema)
      |> Enum.map(fn conversation ->
        conversation_id = Ecto.UUID.cast!(conversation.id)

        stats =
          conversation_stats(
            conversation_id,
            Ecto.UUID.cast!(from_actor_id),
            Ecto.UUID.cast!(to_actor_id),
            tenant_schema
          )

        %{
          id: conversation_id,
          opened_at: conversation.opened_at,
          last_message_at: conversation.last_message_at,
          most_recent_message_id:
            conversation.most_recent_message_id &&
              Ecto.UUID.cast!(conversation.most_recent_message_id),
          participant_summary: conversation.participant_summary || %{},
          entity_summary: conversation.entity_summary || %{},
          topic_summary: conversation.topic_summary,
          metadata: conversation.metadata || %{},
          stats: stats
        }
      end)

    Enum.uniq_by(conversations, & &1.id)
  end

  defp conversation_stats(conversation_id, from_actor_id, to_actor_id, tenant_schema) do
    message_ids =
      from(cm in "conversation_memberships",
        where: cm.conversation_id == ^dump_uuid!(conversation_id) and cm.member_kind == "message",
        select: cm.member_id
      )
      |> Repo.all(prefix: tenant_schema)

    dumped_message_ids = Enum.map(message_ids, &dump_uuid!/1)

    counts =
      from(m in "messages",
        where:
          m.id in ^dumped_message_ids and
            m.actor_id in ^[dump_uuid!(from_actor_id), dump_uuid!(to_actor_id)],
        group_by: m.actor_id,
        select: {m.actor_id, count("*")}
      )
      |> Repo.all(prefix: tenant_schema)
      |> Map.new(fn {actor_id, count} -> {Ecto.UUID.cast!(actor_id), count} end)

    directional_reply_count =
      from(ml in "message_links",
        join: source in "messages",
        on: source.id == ml.source_message_id,
        join: target in "messages",
        on: target.id == ml.target_message_id,
        where:
          ml.source_message_id in ^dumped_message_ids and
            ml.target_message_id in ^dumped_message_ids and
            source.actor_id == ^dump_uuid!(from_actor_id) and
            target.actor_id == ^dump_uuid!(to_actor_id) and
            ml.link_type in ["replies_to", "answers", "clarifies", "continues"],
        select: count("*")
      )
      |> Repo.one(prefix: tenant_schema)

    answered_items =
      PendingItem
      |> Ash.Query.filter(
        expr(conversation_id == ^conversation_id and status in ["answered", "completed"])
      )
      |> Ash.read!(tenant: tenant_schema)
      |> Enum.count(fn item ->
        opener_actor_id(item.opener_message_id, tenant_schema) == to_actor_id and
          resolver_actor_id(item.resolver_message_id, tenant_schema) == from_actor_id
      end)

    %{
      from_message_count: Map.get(counts, from_actor_id, 0),
      to_message_count: Map.get(counts, to_actor_id, 0),
      directional_reply_count: directional_reply_count || 0,
      answered_item_count: answered_items
    }
  end

  defp build_interaction_relationship(_from_actor_id, _to_actor_id, []), do: nil

  defp build_interaction_relationship(from_actor_id, to_actor_id, shared_conversations) do
    aggregate =
      Enum.reduce(shared_conversations, new_aggregate(), fn conversation, acc ->
        stats = conversation.stats

        raw =
          1.0 +
            min(stats.from_message_count, stats.to_message_count) * 0.6 +
            stats.directional_reply_count * 1.2 +
            stats.answered_item_count * 1.5

        apply_score(acc, raw, conversation)
      end)

    relationship_attrs(
      aggregate,
      @interaction_type,
      from_actor_id,
      to_actor_id,
      "conversation_interaction"
    )
  end

  defp build_answered_relationship(_from_actor_id, _to_actor_id, []), do: nil

  defp build_answered_relationship(from_actor_id, to_actor_id, shared_conversations) do
    aggregate =
      Enum.reduce(shared_conversations, new_aggregate(), fn conversation, acc ->
        answered_count = conversation.stats.answered_item_count

        if answered_count > 0 do
          raw = answered_count * 2.0
          apply_score(acc, raw, conversation, answered_count: answered_count)
        else
          acc
        end
      end)

    relationship_attrs(
      aggregate,
      @answered_type,
      from_actor_id,
      to_actor_id,
      "pending_item_resolution"
    )
  end

  defp relationship_attrs(%{decayed_score: score}, _type, _from_actor_id, _to_actor_id, _source)
       when score <= 0.0,
       do: nil

  defp relationship_attrs(aggregate, relationship_type, from_actor_id, to_actor_id, source) do
    %{
      relationship_type: relationship_type,
      weight: max(1, round(aggregate.decayed_score)),
      first_seen_at: aggregate.first_seen_at,
      last_seen_at: aggregate.last_seen_at,
      metadata: %{
        "source" => source,
        "recompute_version" => @review_version,
        "conversation_ids" => Enum.map(aggregate.conversation_ids, &to_string/1),
        "shared_conversation_count" => length(aggregate.conversation_ids),
        "raw_score" => Float.round(aggregate.raw_score, 3),
        "decayed_score" => Float.round(aggregate.decayed_score, 3),
        "decay_half_life_days" => @decay_half_life_days,
        "directional_reply_count" => aggregate.directional_reply_count,
        "answered_pending_item_count" => aggregate.answered_pending_item_count
      },
      from_actor_id: from_actor_id,
      to_actor_id: to_actor_id,
      source_message_id: aggregate.source_message_id
    }
  end

  defp new_aggregate do
    %{
      raw_score: 0.0,
      decayed_score: 0.0,
      first_seen_at: nil,
      last_seen_at: nil,
      source_message_id: nil,
      conversation_ids: [],
      directional_reply_count: 0,
      answered_pending_item_count: 0
    }
  end

  defp apply_score(acc, raw, conversation, extra \\ []) do
    decay = decay_factor(conversation.last_message_at)
    decayed = raw * decay

    %{
      raw_score: acc.raw_score + raw,
      decayed_score: acc.decayed_score + decayed,
      first_seen_at: min_datetime(acc.first_seen_at, conversation.opened_at),
      last_seen_at: max_datetime(acc.last_seen_at, conversation.last_message_at),
      source_message_id: latest_source_message_id(acc, conversation),
      conversation_ids: Enum.uniq(acc.conversation_ids ++ [conversation.id]),
      directional_reply_count:
        acc.directional_reply_count + conversation.stats.directional_reply_count,
      answered_pending_item_count:
        acc.answered_pending_item_count + Keyword.get(extra, :answered_count, 0)
    }
  end

  defp latest_source_message_id(acc, conversation) do
    if max_datetime(acc.last_seen_at, conversation.last_message_at) ==
         conversation.last_message_at do
      conversation.most_recent_message_id || acc.source_message_id
    else
      acc.source_message_id
    end
  end

  defp decay_factor(nil), do: 1.0

  defp decay_factor(datetime) do
    days =
      datetime
      |> normalize_datetime()
      |> NaiveDateTime.diff(DateTime.utc_now() |> DateTime.to_naive(), :second)
      |> Kernel./(-86_400)
      |> max(0.0)

    :math.pow(0.5, days / @decay_half_life_days)
  end

  defp upsert_relationship(attrs, tenant_schema) do
    query =
      Relationship
      |> Ash.Query.filter(
        expr(
          from_actor_id == ^attrs.from_actor_id and to_actor_id == ^attrs.to_actor_id and
            relationship_type == ^attrs.relationship_type
        )
      )

    case Ash.read_one(query, tenant: tenant_schema) do
      {:ok, nil} ->
        Relationship
        |> Ash.Changeset.for_create(:create, attrs, tenant: tenant_schema)
        |> Ash.create()

      {:ok, relationship} ->
        relationship
        |> Ash.Changeset.for_update(
          :update,
          Map.take(attrs, [:weight, :last_seen_at, :metadata, :source_message_id]),
          tenant: tenant_schema
        )
        |> Ash.update()

      error ->
        error
    end
  end

  defp mark_conversation_recomputed(conversation, tenant_schema) do
    conversation
    |> Ash.Changeset.for_update(
      :update,
      %{
        confidence_summary:
          (conversation.confidence_summary || %{})
          |> Map.put("relationship_recompute_generated_at", encode_datetime(DateTime.utc_now())),
        metadata:
          (conversation.metadata || %{})
          |> Map.put("relationship_recompute_needs_refresh", false)
          |> Map.put("relationship_recompute_refresh_reason", "up_to_date")
          |> Map.put("relationship_recompute_generated_at", encode_datetime(DateTime.utc_now()))
      },
      tenant: tenant_schema
    )
    |> Ash.update()
  end

  defp opener_actor_id(message_id, tenant_schema) when is_binary(message_id) do
    actor_id_for_message(message_id, tenant_schema)
  end

  defp opener_actor_id(_message_id, _tenant_schema), do: nil

  defp resolver_actor_id(message_id, tenant_schema) when is_binary(message_id) do
    actor_id_for_message(message_id, tenant_schema)
  end

  defp resolver_actor_id(_message_id, _tenant_schema), do: nil

  defp actor_id_for_message(message_id, tenant_schema) do
    from(m in "messages",
      where: m.id == ^dump_uuid!(message_id),
      select: m.actor_id,
      limit: 1
    )
    |> Repo.one(prefix: tenant_schema)
    |> case do
      nil -> nil
      actor_id -> Ecto.UUID.cast!(actor_id)
    end
  end

  defp ordered_pairs(actor_ids) do
    for from_actor_id <- actor_ids,
        to_actor_id <- actor_ids,
        from_actor_id != to_actor_id do
      {from_actor_id, to_actor_id}
    end
  end

  defp min_datetime(nil, other), do: other
  defp min_datetime(other, nil), do: other

  defp min_datetime(left, right) do
    case NaiveDateTime.compare(normalize_datetime(left), normalize_datetime(right)) do
      :gt -> right
      _ -> left
    end
  end

  defp max_datetime(nil, other), do: other
  defp max_datetime(other, nil), do: other

  defp max_datetime(left, right) do
    case NaiveDateTime.compare(normalize_datetime(left), normalize_datetime(right)) do
      :lt -> right
      _ -> left
    end
  end

  defp normalize_datetime(%NaiveDateTime{} = datetime), do: datetime
  defp normalize_datetime(%DateTime{} = datetime), do: DateTime.to_naive(datetime)

  defp encode_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp dump_uuid!(id) when is_binary(id) do
    case Ecto.UUID.dump(id) do
      {:ok, dumped} -> dumped
      :error -> raise ArgumentError, "invalid UUID #{inspect(id)}"
    end
  end
end
