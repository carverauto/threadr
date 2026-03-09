defmodule Threadr.TenantData.ConversationClusterReview do
  @moduledoc """
  Batch review pass for ambiguous local conversation clusters.
  """

  import Ash.Expr
  import Ecto.Query
  require Ash.Query

  alias Threadr.Repo

  alias Threadr.TenantData.{
    Conversation,
    ConversationMembership
  }

  @review_version "conversation-cluster-review-v1"
  @nearby_gap_minutes 15
  @merge_threshold 0.55
  @low_margin_threshold 0.15

  def review_conversation(conversation_id, tenant_schema)
      when is_binary(conversation_id) and is_binary(tenant_schema) do
    with {:ok, conversation} <- fetch_conversation(conversation_id, tenant_schema),
         merge_candidates = merge_candidates(conversation, tenant_schema),
         split_signals = split_signals(conversation, tenant_schema),
         {:ok, updated} <-
           persist_review(conversation, merge_candidates, split_signals, tenant_schema) do
      {:ok, updated}
    end
  end

  def pending_conversation_ids(tenant_schema, limit \\ 10)
      when is_binary(tenant_schema) and is_integer(limit) and limit > 0 do
    from(c in "conversations",
      where:
        fragment(
          "coalesce((?->>?)::boolean, false)",
          c.metadata,
          "cluster_review_needs_refresh"
        ),
      order_by: [asc: c.last_message_at, asc: c.inserted_at],
      limit: ^limit,
      select: c.id
    )
    |> Repo.all(prefix: tenant_schema)
    |> Enum.map(&Ecto.UUID.cast!/1)
  end

  def review_version, do: @review_version

  defp fetch_conversation(conversation_id, tenant_schema) do
    case Conversation
         |> Ash.Query.filter(expr(id == ^conversation_id))
         |> Ash.read_one(tenant: tenant_schema) do
      {:ok, nil} -> {:error, {:conversation_not_found, conversation_id}}
      {:ok, conversation} -> {:ok, conversation}
      error -> error
    end
  end

  defp merge_candidates(conversation, tenant_schema) do
    conversation
    |> nearby_conversations(tenant_schema)
    |> Enum.map(&merge_candidate(conversation, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&{-&1["score"], &1["conversation_id"]})
  end

  defp nearby_conversations(conversation, tenant_schema) do
    earliest = shift_minutes(conversation.opened_at, -@nearby_gap_minutes)
    latest = shift_minutes(conversation.last_message_at, @nearby_gap_minutes)

    Conversation
    |> Ash.Query.filter(
      expr(
        id != ^conversation.id and channel_id == ^conversation.channel_id and opened_at <= ^latest and
          last_message_at >= ^earliest
      )
    )
    |> Ash.read!(tenant: tenant_schema)
  end

  defp merge_candidate(conversation, candidate) do
    actor_overlap =
      jaccard(
        summary_list(conversation.participant_summary, "actor_ids"),
        summary_list(candidate.participant_summary, "actor_ids")
      )

    entity_overlap =
      jaccard(
        summary_list(conversation.entity_summary, "names"),
        summary_list(candidate.entity_summary, "names")
      )

    time_score = time_proximity_score(conversation, candidate)

    score =
      (actor_overlap * 0.45)
      |> Kernel.+(entity_overlap * 0.4)
      |> Kernel.+(time_score * 0.15)
      |> Float.round(3)

    if score >= @merge_threshold do
      %{
        "conversation_id" => candidate.id,
        "score" => score,
        "reason_codes" => merge_reason_codes(actor_overlap, entity_overlap, time_score),
        "opened_at" => encode_datetime(candidate.opened_at),
        "last_message_at" => encode_datetime(candidate.last_message_at),
        "topic_summary" => candidate.topic_summary
      }
    end
  end

  defp split_signals(conversation, tenant_schema) do
    message_ids =
      ConversationMembership
      |> Ash.Query.filter(expr(conversation_id == ^conversation.id and member_kind == "message"))
      |> Ash.read!(tenant: tenant_schema)
      |> Enum.map(&dump_uuid!(&1.member_id))

    if message_ids == [] do
      []
    else
      from(ml in "message_links",
        where:
          (ml.source_message_id in ^message_ids or ml.target_message_id in ^message_ids) and
            (ml.confidence_band == "low" or
               ml.competing_candidate_margin <= ^@low_margin_threshold),
        order_by: [asc: ml.competing_candidate_margin, desc: ml.score],
        select: %{
          source_message_id: ml.source_message_id,
          target_message_id: ml.target_message_id,
          link_type: ml.link_type,
          score: ml.score,
          confidence_band: ml.confidence_band,
          competing_candidate_margin: ml.competing_candidate_margin
        }
      )
      |> Repo.all(prefix: tenant_schema)
      |> Enum.map(fn signal ->
        %{
          "source_message_id" => Ecto.UUID.cast!(signal.source_message_id),
          "target_message_id" => Ecto.UUID.cast!(signal.target_message_id),
          "link_type" => signal.link_type,
          "score" => signal.score,
          "confidence_band" => signal.confidence_band,
          "competing_candidate_margin" => signal.competing_candidate_margin,
          "reason_code" => "low_margin_link"
        }
      end)
    end
  end

  defp persist_review(conversation, merge_candidates, split_signals, tenant_schema) do
    generated_at = DateTime.utc_now() |> DateTime.truncate(:second)
    status = review_status(merge_candidates, split_signals)

    attrs = %{
      confidence_summary:
        (conversation.confidence_summary || %{})
        |> Map.put("cluster_review_merge_candidates", length(merge_candidates))
        |> Map.put("cluster_review_split_signals", length(split_signals))
        |> Map.put("cluster_review_generated_at", encode_datetime(generated_at)),
      metadata:
        (conversation.metadata || %{})
        |> Map.put("cluster_review", %{
          "status" => status,
          "generated_at" => encode_datetime(generated_at),
          "version" => @review_version,
          "merge_candidates" => merge_candidates,
          "split_signals" => split_signals
        })
        |> Map.put("cluster_review_needs_refresh", false)
        |> Map.put("cluster_review_refresh_reason", "up_to_date")
    }

    conversation
    |> Ash.Changeset.for_update(:update, attrs, tenant: tenant_schema)
    |> Ash.update()
  end

  defp review_status([], []), do: "clear"
  defp review_status(_merge_candidates, _split_signals), do: "review_recommended"

  defp merge_reason_codes(actor_overlap, entity_overlap, time_score) do
    []
    |> maybe_append_reason("shared_participants", actor_overlap >= 0.5)
    |> maybe_append_reason("shared_entities", entity_overlap >= 0.5)
    |> maybe_append_reason("close_in_time", time_score >= 0.7)
  end

  defp maybe_append_reason(reasons, _reason, false), do: reasons
  defp maybe_append_reason(reasons, reason, true), do: reasons ++ [reason]

  defp summary_list(summary, key) when is_map(summary) do
    summary
    |> Map.get(key, [])
    |> List.wrap()
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
  end

  defp summary_list(_summary, _key), do: []

  defp jaccard([], []), do: 0.0

  defp jaccard(left, right) do
    left_set = MapSet.new(left)
    right_set = MapSet.new(right)

    intersection = MapSet.intersection(left_set, right_set) |> MapSet.size()
    union = MapSet.union(left_set, right_set) |> MapSet.size()

    if union == 0, do: 0.0, else: Float.round(intersection / union, 3)
  end

  defp time_proximity_score(left, right) do
    gap_minutes =
      left
      |> conversation_gap_minutes(right)
      |> min(@nearby_gap_minutes)

    Float.round(1.0 - gap_minutes / @nearby_gap_minutes, 3)
  end

  defp conversation_gap_minutes(left, right) do
    left_end = normalize_datetime(left.last_message_at)
    right_start = normalize_datetime(right.opened_at)
    right_end = normalize_datetime(right.last_message_at)
    left_start = normalize_datetime(left.opened_at)

    cond do
      NaiveDateTime.compare(left_end, right_start) in [:gt, :eq] and
          NaiveDateTime.compare(right_end, left_start) in [:gt, :eq] ->
        0

      NaiveDateTime.compare(left_end, right_start) == :lt ->
        NaiveDateTime.diff(right_start, left_end, :second) / 60

      true ->
        NaiveDateTime.diff(left_start, right_end, :second) / 60
    end
  end

  defp shift_minutes(%NaiveDateTime{} = datetime, amount) do
    NaiveDateTime.add(datetime, amount * 60, :second)
  end

  defp shift_minutes(%DateTime{} = datetime, amount) do
    DateTime.add(datetime, amount * 60, :second)
  end

  defp normalize_datetime(%NaiveDateTime{} = datetime), do: datetime
  defp normalize_datetime(%DateTime{} = datetime), do: DateTime.to_naive(datetime)

  defp encode_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp encode_datetime(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime)
  defp encode_datetime(nil), do: nil

  defp dump_uuid!(id) when is_binary(id) do
    case Ecto.UUID.dump(id) do
      {:ok, dumped} -> dumped
      :error -> raise ArgumentError, "invalid UUID #{inspect(id)}"
    end
  end
end
