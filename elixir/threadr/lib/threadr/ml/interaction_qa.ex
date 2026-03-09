defmodule Threadr.ML.InteractionQA do
  @moduledoc """
  Answers actor interaction-partner questions from reconstructed conversation evidence.
  """

  import Ecto.Query

  alias Threadr.ControlPlane

  alias Threadr.ML.{
    ActorReference,
    ConversationQA,
    Generation,
    GenerationProviderOpts,
    InteractionQAIntent
  }

  alias Threadr.Repo

  @relationship_types ["INTERACTED_WITH", "ANSWERED"]
  @default_partner_limit 5
  @default_conversation_limit 6

  def answer_question(tenant_subject_name, question, opts \\ [])
      when is_binary(tenant_subject_name) and is_binary(question) do
    with {:ok, tenant} <-
           ControlPlane.get_tenant_by_subject_name(tenant_subject_name, context: %{system: true}),
         {:ok, intent} <- InteractionQAIntent.classify(question),
         {:ok, actor} <- ActorReference.resolve(tenant.schema_name, intent.actor_ref, opts),
         partners when partners != [] <- fetch_partners(tenant.schema_name, actor, opts) do
      build_answer(tenant, question, actor, partners, opts)
    else
      [] -> {:error, :not_interaction_question}
      {:error, {:actor_not_found, _actor_ref}} -> {:error, :not_interaction_question}
      {:error, {:ambiguous_actor, _actor_ref, _matches}} -> {:error, :not_interaction_question}
      {:error, :not_interaction_question} = error -> error
    end
  end

  defp build_answer(tenant, question, actor, partners, opts) do
    citations =
      tenant.schema_name
      |> build_partner_citations(partners)
      |> Enum.with_index(1)
      |> Enum.map(fn {citation, index} -> Map.put(citation, :label, "C#{index}") end)

    context = build_context(question, actor, partners, citations)

    with {:ok, answer} <- Generation.answer_question(question, context, generation_opts(opts)) do
      {:ok,
       %{
         tenant_subject_name: tenant.subject_name,
         tenant_schema: tenant.schema_name,
         question: question,
         query: %{
           mode: "interaction_qa",
           kind: :interaction_partners,
           actor_handle: actor.handle,
           retrieval: "conversation_relationships",
           partner_count: length(partners),
           evidence_count: length(citations)
         },
         partners: partners,
         citations: citations,
         facts_over_time: [],
         context: context,
         answer: answer
       }}
    end
  end

  defp fetch_partners(tenant_schema, actor, opts) do
    relationship_rows =
      from(r in "relationships",
        join: partner in "actors",
        on:
          (r.from_actor_id == ^dump_uuid!(actor.id) and partner.id == r.to_actor_id) or
            (r.to_actor_id == ^dump_uuid!(actor.id) and partner.id == r.from_actor_id),
        where: r.relationship_type in ^@relationship_types,
        select: %{
          relationship_type: r.relationship_type,
          weight: r.weight,
          metadata: r.metadata,
          first_seen_at: r.first_seen_at,
          last_seen_at: r.last_seen_at,
          partner_id: partner.id,
          partner_handle: partner.handle,
          partner_display_name: partner.display_name,
          partner_external_id: partner.external_id
        }
      )
      |> Repo.all(prefix: tenant_schema)

    aggregated =
      relationship_rows
      |> Enum.reduce(%{}, fn row, acc ->
        Map.update(
          acc,
          normalize_identifier(row.partner_id),
          new_partner_aggregate(row),
          fn existing ->
            merge_partner_aggregate(existing, row)
          end
        )
      end)
      |> Map.values()

    case aggregated do
      [] -> fallback_partners_from_conversations(tenant_schema, actor, opts)
      values -> values
    end
    |> Enum.sort_by(
      &{-&1.score, -shared_conversation_count(&1), -sort_timestamp(&1.last_seen_at)}
    )
    |> Enum.take(partner_limit(opts))
  end

  defp fallback_partners_from_conversations(tenant_schema, actor, opts) do
    dumped_actor_id = dump_uuid!(actor.id)

    from(c in "conversations",
      join: cm_self in "conversation_memberships",
      on: cm_self.conversation_id == c.id and cm_self.member_kind == "actor",
      join: cm_other in "conversation_memberships",
      on: cm_other.conversation_id == c.id and cm_other.member_kind == "actor",
      join: other in "actors",
      on: other.id == cm_other.member_id,
      where: cm_self.member_id == ^dumped_actor_id and cm_other.member_id != ^dumped_actor_id,
      select: %{
        conversation_id: c.id,
        last_message_at: c.last_message_at,
        partner_id: other.id,
        partner_handle: other.handle,
        partner_display_name: other.display_name,
        partner_external_id: other.external_id
      }
    )
    |> apply_conversation_time_bounds(opts)
    |> Repo.all(prefix: tenant_schema)
    |> Enum.reduce(%{}, fn row, acc ->
      partner_id = normalize_identifier(row.partner_id)

      Map.update(
        acc,
        partner_id,
        %{
          partner_id: partner_id,
          partner_handle: row.partner_handle,
          partner_display_name: row.partner_display_name,
          partner_external_id: row.partner_external_id,
          interacted_weight: 0,
          answered_weight: 0,
          score: 1.0,
          first_seen_at: nil,
          last_seen_at: row.last_message_at,
          conversation_ids: [normalize_identifier(row.conversation_id)]
        },
        fn existing ->
          %{
            existing
            | score: existing.score + 1.0,
              last_seen_at: max_datetime(existing.last_seen_at, row.last_message_at),
              conversation_ids:
                Enum.uniq(
                  existing.conversation_ids ++ [normalize_identifier(row.conversation_id)]
                )
          }
        end
      )
    end)
    |> Map.values()
  end

  defp build_partner_citations(tenant_schema, partners) do
    conversation_ids =
      partners
      |> Enum.flat_map(& &1.conversation_ids)
      |> Enum.uniq()
      |> Enum.take(@default_conversation_limit)

    conversations = Enum.map(conversation_ids, &%{conversation_id: &1})

    ConversationQA.build_citations(tenant_schema, conversations)
  end

  defp build_context(question, actor, partners, citations) do
    partner_lines =
      partners
      |> Enum.with_index(1)
      |> Enum.map(fn {partner, index} ->
        [
          "[Partner #{index}] #{partner_display(partner)}",
          "Score: #{Float.round(partner.score, 2)}",
          "Shared conversations: #{shared_conversation_count(partner)}",
          "Interaction weight: #{partner.interacted_weight}",
          if(partner.answered_weight > 0,
            do: "Answered weight: #{partner.answered_weight}",
            else: nil
          ),
          if(partner.last_seen_at,
            do: "Most recent interaction: #{partner.last_seen_at}",
            else: nil
          )
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" | ")
      end)

    evidence =
      case citations do
        [] -> ""
        rows -> Threadr.ML.SemanticQA.build_context(rows)
      end

    [
      "Interaction-focused QA for who #{actor.handle} mostly talks with.",
      "Question: #{question}",
      "Top interaction partners:",
      Enum.join(partner_lines, "\n"),
      if(evidence == "", do: nil, else: "Supporting messages:\n" <> evidence)
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n\n")
  end

  defp new_partner_aggregate(row) do
    conversation_ids = Map.get(row.metadata || %{}, "conversation_ids", []) |> List.wrap()

    %{
      partner_id: normalize_identifier(row.partner_id),
      partner_handle: row.partner_handle,
      partner_display_name: row.partner_display_name,
      partner_external_id: row.partner_external_id,
      interacted_weight: interaction_weight(row),
      answered_weight: answered_weight(row),
      score: row_score(row),
      first_seen_at: row.first_seen_at,
      last_seen_at: row.last_seen_at,
      conversation_ids: conversation_ids
    }
  end

  defp merge_partner_aggregate(existing, row) do
    conversation_ids =
      existing.conversation_ids ++ Map.get(row.metadata || %{}, "conversation_ids", [])

    %{
      existing
      | interacted_weight: existing.interacted_weight + interaction_weight(row),
        answered_weight: existing.answered_weight + answered_weight(row),
        score: existing.score + row_score(row),
        first_seen_at: min_datetime(existing.first_seen_at, row.first_seen_at),
        last_seen_at: max_datetime(existing.last_seen_at, row.last_seen_at),
        conversation_ids: Enum.uniq(conversation_ids)
    }
  end

  defp interaction_weight(%{relationship_type: "INTERACTED_WITH", weight: weight}), do: weight
  defp interaction_weight(_row), do: 0

  defp answered_weight(%{relationship_type: "ANSWERED", weight: weight}), do: weight
  defp answered_weight(_row), do: 0

  defp row_score(%{relationship_type: "INTERACTED_WITH", weight: weight}), do: weight * 1.0
  defp row_score(%{relationship_type: "ANSWERED", weight: weight}), do: weight * 0.6
  defp row_score(%{weight: weight}), do: weight * 1.0

  defp apply_conversation_time_bounds(query, opts) do
    query
    |> maybe_filter_since(Keyword.get(opts, :since))
    |> maybe_filter_until(Keyword.get(opts, :until))
  end

  defp maybe_filter_since(query, nil), do: query

  defp maybe_filter_since(query, %NaiveDateTime{} = since) do
    maybe_filter_since(query, DateTime.from_naive!(since, "Etc/UTC"))
  end

  defp maybe_filter_since(query, %DateTime{} = since) do
    where(query, [c, _cm_self, _cm_other, _other], c.last_message_at >= ^since)
  end

  defp maybe_filter_until(query, nil), do: query

  defp maybe_filter_until(query, %NaiveDateTime{} = until) do
    maybe_filter_until(query, DateTime.from_naive!(until, "Etc/UTC"))
  end

  defp maybe_filter_until(query, %DateTime{} = until) do
    where(query, [c, _cm_self, _cm_other, _other], c.opened_at <= ^until)
  end

  defp generation_opts(opts), do: GenerationProviderOpts.from_prefixed(opts)

  defp partner_limit(opts) do
    opts |> Keyword.get(:limit, @default_partner_limit) |> min(@default_partner_limit) |> max(1)
  end

  defp shared_conversation_count(partner), do: partner.conversation_ids |> List.wrap() |> length()

  defp partner_display(partner), do: partner.partner_display_name || partner.partner_handle

  defp blank?(value), do: value in [nil, ""]

  defp min_datetime(nil, other), do: other
  defp min_datetime(other, nil), do: other

  defp min_datetime(left, right),
    do: if(compare_datetimes(left, right) == :gt, do: right, else: left)

  defp max_datetime(nil, other), do: other
  defp max_datetime(other, nil), do: other

  defp max_datetime(left, right),
    do: if(compare_datetimes(left, right) == :lt, do: right, else: left)

  defp compare_datetimes(%DateTime{} = left, %DateTime{} = right),
    do: DateTime.compare(left, right)

  defp compare_datetimes(%NaiveDateTime{} = left, %NaiveDateTime{} = right) do
    NaiveDateTime.compare(left, right)
  end

  defp compare_datetimes(%DateTime{} = left, %NaiveDateTime{} = right) do
    DateTime.compare(left, DateTime.from_naive!(right, "Etc/UTC"))
  end

  defp compare_datetimes(%NaiveDateTime{} = left, %DateTime{} = right) do
    DateTime.compare(DateTime.from_naive!(left, "Etc/UTC"), right)
  end

  defp sort_timestamp(nil), do: 0
  defp sort_timestamp(%DateTime{} = timestamp), do: DateTime.to_unix(timestamp)

  defp sort_timestamp(%NaiveDateTime{} = timestamp),
    do: DateTime.from_naive!(timestamp, "Etc/UTC") |> DateTime.to_unix()

  defp dump_uuid!(value) do
    value |> Ecto.UUID.cast!() |> Ecto.UUID.dump!()
  end

  defp normalize_identifier(nil), do: nil

  defp normalize_identifier(value) when is_binary(value) do
    if String.valid?(value) do
      value
    else
      case Ecto.UUID.load(value) do
        {:ok, uuid} -> uuid
        :error -> Base.encode16(value, case: :lower)
      end
    end
  end

  defp normalize_identifier(value), do: to_string(value)
end
