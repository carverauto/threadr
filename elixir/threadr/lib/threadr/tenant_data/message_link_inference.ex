defmodule Threadr.TenantData.MessageLinkInference do
  @moduledoc """
  Confidence-scored message-link inference over bounded reconstruction candidates.
  """

  import Ash.Expr
  require Ash.Query

  alias Threadr.TenantData.{MessageLink, ReconstructionCandidates}

  @decision_version "message-link-rules-v1"
  @inferred_by "threadr.reconstruction.rules"
  @persist_threshold 0.35

  def infer_and_persist(message_id, tenant_schema, opts \\ [])
      when is_binary(message_id) and is_binary(tenant_schema) do
    with {:ok, result} <- infer(message_id, tenant_schema, opts) do
      case result do
        %{winner: nil} ->
          {:ok, %{winner: nil, persisted: nil, candidates: result.candidates}}

        %{winner: winner} ->
          with {:ok, link} <- upsert_link(message_id, winner, tenant_schema) do
            {:ok, %{winner: winner, persisted: link, candidates: result.candidates}}
          end
      end
    end
  end

  def infer(message_id, tenant_schema, opts \\ [])
      when is_binary(message_id) and is_binary(tenant_schema) do
    with {:ok, candidates} <-
           ReconstructionCandidates.for_message(message_id, tenant_schema, opts) do
      ranked =
        candidates.recent_messages
        |> Enum.map(&score_candidate(candidates.focal_message, &1))
        |> Enum.sort_by(& &1.score, :desc)

      {:ok, %{winner: winning_candidate(ranked), candidates: ranked}}
    end
  end

  def decision_version, do: @decision_version

  defp score_candidate(focal_message, candidate) do
    evidence =
      [
        explicit_reply_evidence(focal_message, candidate),
        same_conversation_evidence(focal_message, candidate),
        actor_continuity_evidence(focal_message, candidate),
        dialogue_act_evidence(focal_message, candidate),
        entity_overlap_evidence(focal_message, candidate),
        time_decay_evidence(focal_message, candidate)
      ]
      |> Enum.reject(&is_nil/1)

    score =
      evidence
      |> Enum.reduce(0.0, fn item, acc -> acc + item.weight end)
      |> clamp()

    %{
      target_message_id: candidate.id,
      target_external_id: candidate.external_id,
      link_type: infer_link_type(focal_message, candidate),
      score: score,
      confidence_band: confidence_band(score),
      competing_candidate_margin: 0.0,
      evidence: evidence,
      inferred_at: DateTime.utc_now() |> DateTime.truncate(:second),
      inferred_by: @inferred_by,
      winning_decision_version: @decision_version,
      metadata: %{
        "source_message_external_id" => focal_message.external_id,
        "target_message_external_id" => candidate.external_id,
        "source_dialogue_act" => get_in(focal_message, [:dialogue_act, :label]),
        "target_dialogue_act" => get_in(candidate, [:dialogue_act, :label])
      }
    }
  end

  defp winning_candidate([]), do: nil

  defp winning_candidate([winner | rest]) do
    next_score = rest |> List.first() |> then(fn row -> if row, do: row.score, else: 0.0 end)
    margin = max(winner.score - next_score, 0.0)
    winner = %{winner | competing_candidate_margin: margin}

    if winner.score >= @persist_threshold, do: winner, else: nil
  end

  defp explicit_reply_evidence(focal_message, candidate) do
    if focal_message.reply_to_external_id == candidate.external_id do
      %{
        kind: "explicit_reply",
        weight: 0.7,
        value: candidate.external_id,
        explanation: "focal message explicitly references the candidate message",
        referenced_message_ids: [candidate.id]
      }
    end
  end

  defp same_conversation_evidence(focal_message, candidate) do
    if focal_message.conversation_external_id == candidate.conversation_external_id do
      %{
        kind: "conversation_external_id",
        weight: 0.12,
        value: candidate.conversation_external_id,
        explanation: "messages share the same normalized conversation identifier"
      }
    end
  end

  defp actor_continuity_evidence(focal_message, candidate) do
    if focal_message.actor_id != candidate.actor_id do
      %{
        kind: "turn_taking",
        weight: 0.08,
        value: "#{candidate.actor_handle}->#{focal_message.actor_handle}",
        explanation: "candidate comes from a different actor, which supports turn-taking"
      }
    end
  end

  defp dialogue_act_evidence(focal_message, candidate) do
    source = get_in(focal_message, [:dialogue_act, :label])
    target = get_in(candidate, [:dialogue_act, :label])

    case {source, target} do
      {"answer", "question"} ->
        %{
          kind: "dialogue_act_match",
          weight: 0.28,
          value: "answer->question",
          explanation: "an answer following a question is a strong reply pattern"
        }

      {"acknowledgement", "request"} ->
        %{
          kind: "dialogue_act_match",
          weight: 0.16,
          value: "acknowledgement->request",
          explanation: "an acknowledgment following a request supports a conversational link"
        }

      {"status_update", "request"} ->
        %{
          kind: "dialogue_act_match",
          weight: 0.14,
          value: "status_update->request",
          explanation: "a status update can resolve or continue a request"
        }

      _ ->
        nil
    end
  end

  defp entity_overlap_evidence(focal_message, candidate) do
    overlap =
      MapSet.intersection(
        MapSet.new(focal_message.entity_names || []),
        MapSet.new(candidate.entity_names || [])
      )
      |> MapSet.to_list()
      |> Enum.sort()

    case overlap do
      [] ->
        nil

      names ->
        %{
          kind: "entity_overlap",
          weight: min(0.18, 0.08 + length(names) * 0.05),
          value: names,
          explanation: "messages share extracted entities that suggest topical continuity"
        }
    end
  end

  defp time_decay_evidence(focal_message, candidate) do
    minutes = observed_diff_minutes(focal_message.observed_at, candidate.observed_at)

    cond do
      is_nil(minutes) ->
        nil

      minutes <= 5 ->
        %{
          kind: "time_decay",
          weight: 0.14,
          value: minutes,
          explanation: "candidate is very recent relative to the focal message"
        }

      minutes <= 20 ->
        %{
          kind: "time_decay",
          weight: 0.08,
          value: minutes,
          explanation: "candidate falls inside the short conversational window"
        }

      minutes <= 120 ->
        %{
          kind: "time_decay",
          weight: 0.03,
          value: minutes,
          explanation: "candidate is older but still within the bounded retrieval window"
        }

      true ->
        nil
    end
  end

  defp infer_link_type(focal_message, candidate) do
    cond do
      focal_message.reply_to_external_id == candidate.external_id ->
        "replies_to"

      get_in(focal_message, [:dialogue_act, :label]) == "answer" and
          get_in(candidate, [:dialogue_act, :label]) == "question" ->
        "answers"

      focal_message.conversation_external_id == candidate.conversation_external_id ->
        "continues"

      true ->
        "same_topic_as"
    end
  end

  defp confidence_band(score) when score >= 0.75, do: "high"
  defp confidence_band(score) when score >= 0.5, do: "medium"
  defp confidence_band(_score), do: "low"

  defp clamp(score), do: score |> min(1.0) |> max(0.0)

  defp observed_diff_minutes(%DateTime{} = source, %DateTime{} = target),
    do: abs(DateTime.diff(source, target, :minute))

  defp observed_diff_minutes(%NaiveDateTime{} = source, %NaiveDateTime{} = target),
    do: abs(NaiveDateTime.diff(source, target, :minute))

  defp observed_diff_minutes(_source, _target), do: nil

  defp upsert_link(source_message_id, winner, tenant_schema) do
    query =
      MessageLink
      |> Ash.Query.filter(
        expr(
          source_message_id == ^source_message_id and
            target_message_id == ^winner.target_message_id and
            link_type == ^winner.link_type
        )
      )

    attrs = %{
      link_type: winner.link_type,
      score: winner.score,
      confidence_band: winner.confidence_band,
      winning_decision_version: winner.winning_decision_version,
      competing_candidate_margin: winner.competing_candidate_margin,
      evidence: winner.evidence,
      inferred_at: winner.inferred_at,
      inferred_by: winner.inferred_by,
      metadata: winner.metadata,
      source_message_id: source_message_id,
      target_message_id: winner.target_message_id
    }

    case Ash.read_one(query, tenant: tenant_schema) do
      {:ok, nil} ->
        MessageLink
        |> Ash.Changeset.for_create(:create, attrs, tenant: tenant_schema)
        |> Ash.create()

      {:ok, existing} ->
        existing
        |> Ash.Changeset.for_update(
          :update,
          Map.take(attrs, [
            :score,
            :confidence_band,
            :winning_decision_version,
            :competing_candidate_margin,
            :evidence,
            :inferred_at,
            :inferred_by,
            :metadata
          ]),
          tenant: tenant_schema
        )
        |> Ash.update()

      error ->
        error
    end
  end
end
