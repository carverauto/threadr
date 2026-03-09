defmodule Threadr.TenantData.PendingItemTracking do
  @moduledoc """
  Opens and resolves pending conversational items from attached messages.
  """

  import Ash.Expr
  require Ash.Query

  alias Threadr.TenantData.{ConversationMembership, PendingItem}

  @open_kinds %{"question" => "question", "request" => "request"}
  @resolver_labels MapSet.new(["answer", "acknowledgement", "status_update"])
  @version "pending-item-rules-v1"

  def sync(conversation, message, winner, tenant_schema) do
    with {:ok, _opened_or_resolved} <-
           maybe_track_pending_item(conversation, message, winner, tenant_schema),
         {:ok, updated_conversation} <-
           refresh_open_pending_item_count(conversation, tenant_schema) do
      {:ok, updated_conversation}
    end
  end

  defp maybe_track_pending_item(conversation, message, winner, tenant_schema) do
    case open_item_kind(message) do
      nil ->
        maybe_resolve_pending_item(conversation, message, winner, tenant_schema)

      item_kind ->
        open_pending_item(conversation, message, item_kind, tenant_schema)
    end
  end

  defp open_pending_item(conversation, message, item_kind, tenant_schema) do
    query =
      PendingItem
      |> Ash.Query.filter(expr(opener_message_id == ^message.id))

    attrs = %{
      item_kind: item_kind,
      status: "open",
      owner_actor_ids: [message.actor_id],
      referenced_entity_ids: message.entity_names || [],
      opened_at: message.observed_at,
      summary_text: message.body,
      confidence: dialogue_confidence(message),
      supporting_evidence: membership_evidence(message, nil, "opened"),
      metadata: %{"tracking_version" => @version},
      conversation_id: conversation.id,
      opener_message_id: message.id
    }

    case Ash.read_one(query, tenant: tenant_schema) do
      {:ok, nil} ->
        with {:ok, pending_item} <-
               PendingItem
               |> Ash.Changeset.for_create(:create, attrs, tenant: tenant_schema)
               |> Ash.create(),
             {:ok, _membership} <-
               upsert_pending_item_membership(
                 conversation,
                 pending_item,
                 "observer",
                 "pending_item_opened",
                 attrs.confidence,
                 attrs.supporting_evidence,
                 message.observed_at,
                 tenant_schema
               ) do
          {:ok, pending_item}
        end

      {:ok, existing} ->
        {:ok, existing}

      error ->
        error
    end
  end

  defp maybe_resolve_pending_item(_conversation, _message, nil, _tenant_schema), do: {:ok, nil}

  defp maybe_resolve_pending_item(conversation, message, winner, tenant_schema) do
    if resolver_message?(message) do
      case fetch_open_pending_item_for_opener(winner.target_message_id, tenant_schema) do
        {:ok, nil} ->
          {:ok, nil}

        {:ok, pending_item} ->
          resolve_pending_item(conversation, pending_item, message, winner, tenant_schema)

        error ->
          error
      end
    else
      {:ok, nil}
    end
  end

  defp resolve_pending_item(conversation, pending_item, message, winner, tenant_schema) do
    status = resolved_status(pending_item.item_kind)

    with {:ok, updated} <-
           pending_item
           |> Ash.Changeset.for_update(
             :update,
             %{
               status: status,
               resolved_at: message.observed_at,
               resolver_message_id: message.id,
               confidence: max(pending_item.confidence, winner.score),
               supporting_evidence: membership_evidence(message, winner, "resolved"),
               metadata:
                 (pending_item.metadata || %{})
                 |> Map.put("tracking_version", @version)
                 |> Map.put("resolved_link_type", winner.link_type)
             },
             tenant: tenant_schema
           )
           |> Ash.update(),
         {:ok, _membership} <-
           upsert_pending_item_membership(
             conversation,
             updated,
             "resolver",
             winner.link_type,
             winner.score,
             membership_evidence(message, winner, "resolved"),
             message.observed_at,
             tenant_schema
           ) do
      {:ok, updated}
    end
  end

  defp refresh_open_pending_item_count(conversation, tenant_schema) do
    open_count =
      PendingItem
      |> Ash.Query.filter(expr(conversation_id == ^conversation.id and status == "open"))
      |> Ash.read!(tenant: tenant_schema)
      |> length()

    conversation
    |> Ash.Changeset.for_update(
      :update,
      %{open_pending_item_count: open_count},
      tenant: tenant_schema
    )
    |> Ash.update()
  end

  defp fetch_open_pending_item_for_opener(opener_message_id, tenant_schema) do
    PendingItem
    |> Ash.Query.filter(expr(opener_message_id == ^opener_message_id and status == "open"))
    |> Ash.read_one(tenant: tenant_schema)
  end

  defp upsert_pending_item_membership(
         conversation,
         pending_item,
         role,
         join_reason,
         score,
         evidence,
         attached_at,
         tenant_schema
       ) do
    query =
      ConversationMembership
      |> Ash.Query.filter(
        expr(
          conversation_id == ^conversation.id and
            member_kind == "pending_item" and
            member_id == ^pending_item.id
        )
      )

    attrs = %{
      member_kind: "pending_item",
      member_id: pending_item.id,
      role: role,
      score: score,
      join_reason: join_reason,
      evidence: evidence,
      attached_at: attached_at,
      metadata: %{"tracking_version" => @version},
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

  defp open_item_kind(message) do
    label = dialogue_act_value(message, :label)
    Map.get(@open_kinds, label)
  end

  defp resolver_message?(message) do
    MapSet.member?(@resolver_labels, dialogue_act_value(message, :label))
  end

  defp resolved_status("question"), do: "answered"
  defp resolved_status("request"), do: "completed"
  defp resolved_status(_item_kind), do: "completed"

  defp dialogue_confidence(message) do
    case dialogue_act_value(message, :confidence) do
      value when is_float(value) -> value
      value when is_integer(value) -> value / 1
      _ -> 0.5
    end
  end

  defp membership_evidence(message, nil, action) do
    [
      %{
        "kind" => "dialogue_act",
        "weight" => dialogue_confidence(message),
        "value" => dialogue_act_value(message, :label),
        "explanation" => "pending item #{action} from the focal message dialogue act",
        "message_id" => message.id
      }
    ]
  end

  defp membership_evidence(_message, winner, _action) do
    Enum.map(winner.evidence, fn item ->
      item
      |> Enum.map(fn {key, value} -> {to_string(key), value} end)
      |> Map.new()
    end)
  end

  defp dialogue_act_value(message, key) do
    dialogue_act = Map.get(message, :dialogue_act) || %{}
    Map.get(dialogue_act, key) || Map.get(dialogue_act, Atom.to_string(key))
  end
end
