defmodule Threadr.TenantData.ConversationClusterReviewTest do
  use Threadr.DataCase, async: false

  import Ash.Expr
  require Ash.Query

  alias Threadr.ControlPlane.Service

  alias Threadr.TenantData.{
    Actor,
    Channel,
    Conversation,
    ConversationAttachment,
    ConversationClusterReview,
    ConversationClusterReviewDispatcher,
    ExtractedEntity,
    Message,
    MessageLink,
    MessageLinkInference
  }

  test "review_conversation stores merge candidates and split signals for ambiguous clusters" do
    tenant = create_tenant!("Conversation Cluster Review")
    channel = create_channel!(tenant.schema_name, "ops-review")
    alice = create_actor!(tenant.schema_name, "alice-review")
    bob = create_actor!(tenant.schema_name, "bob-review")

    first =
      create_reconstructed_conversation!(
        tenant.schema_name,
        bob,
        alice,
        channel,
        "ops-a",
        "Can you validate web-4?",
        "I validated web-4 successfully.",
        ~U[2026-03-08 10:00:00Z]
      )

    second =
      create_reconstructed_conversation!(
        tenant.schema_name,
        alice,
        bob,
        channel,
        "ops-b",
        "Should we recheck web-4 before deploy?",
        "Yes, let's recheck web-4 before deploy.",
        ~U[2026-03-08 10:06:00Z]
      )

    create_low_margin_link!(
      tenant.schema_name,
      first.most_recent_message_id,
      first.starter_message_id,
      ~U[2026-03-08 10:05:30Z]
    )

    assert {:ok, reviewed} =
             ConversationClusterReview.review_conversation(first.id, tenant.schema_name)

    assert reviewed.metadata["cluster_review_needs_refresh"] == false
    assert reviewed.metadata["cluster_review"]["status"] == "review_recommended"

    assert Enum.any?(
             reviewed.metadata["cluster_review"]["merge_candidates"],
             &(&1["conversation_id"] == second.id)
           )

    assert Enum.any?(
             reviewed.metadata["cluster_review"]["split_signals"],
             &(&1["reason_code"] == "low_margin_link")
           )
  end

  test "dispatcher drains pending conversation cluster reviews" do
    tenant = create_tenant!("Conversation Cluster Dispatcher")
    channel = create_channel!(tenant.schema_name, "ops-dispatch")
    alice = create_actor!(tenant.schema_name, "alice-dispatch")
    bob = create_actor!(tenant.schema_name, "bob-dispatch")

    conversation =
      create_reconstructed_conversation!(
        tenant.schema_name,
        bob,
        alice,
        channel,
        "ops-dispatch-a",
        "Can you validate web-7?",
        "I validated web-7 successfully.",
        ~U[2026-03-08 11:00:00Z],
        "web-7"
      )

    assert :ok = ConversationClusterReviewDispatcher.process_pending_once()

    assert {:ok, reviewed} =
             Conversation
             |> Ash.Query.filter(expr(id == ^conversation.id))
             |> Ash.read_one(tenant: tenant.schema_name)

    assert reviewed.metadata["cluster_review_needs_refresh"] == false
    assert reviewed.metadata["cluster_review"]["status"] in ["clear", "review_recommended"]
  end

  defp create_reconstructed_conversation!(
         tenant_schema,
         starter_actor,
         reply_actor,
         channel,
         conversation_external_id,
         question_body,
         answer_body,
         observed_at,
         entity_name \\ "web-4"
       ) do
    question =
      create_message!(
        tenant_schema,
        starter_actor,
        channel,
        question_body,
        "msg-question-#{conversation_external_id}",
        observed_at,
        %{
          "dialogue_act" => %{"label" => "request", "confidence" => 0.92},
          "conversation_external_id" => conversation_external_id
        }
      )

    answer =
      create_message!(
        tenant_schema,
        reply_actor,
        channel,
        answer_body,
        "msg-answer-#{conversation_external_id}",
        DateTime.add(observed_at, 300, :second),
        %{
          "dialogue_act" => %{"label" => "status_update", "confidence" => 0.86},
          "reply_to_external_id" => question.external_id,
          "conversation_external_id" => conversation_external_id
        }
      )

    create_entity!(tenant_schema, question.id, "artifact", entity_name)
    create_entity!(tenant_schema, answer.id, "artifact", entity_name)

    {:ok, inference} = MessageLinkInference.infer_and_persist(answer.id, tenant_schema)

    {:ok, conversation} =
      ConversationAttachment.attach_message(
        answer.id,
        tenant_schema,
        inference: inference
      )

    conversation
  end

  defp create_low_margin_link!(tenant_schema, source_message_id, target_message_id, inferred_at) do
    MessageLink
    |> Ash.Changeset.for_create(
      :create,
      %{
        link_type: "same_topic_as",
        score: 0.41,
        confidence_band: "low",
        winning_decision_version: "test-low-margin-v1",
        competing_candidate_margin: 0.05,
        evidence: [
          %{
            "kind" => "cluster_review_test",
            "weight" => 0.05,
            "value" => "low_margin",
            "explanation" => "test-only low margin signal"
          }
        ],
        inferred_at: inferred_at,
        inferred_by: "test-suite",
        metadata: %{},
        source_message_id: source_message_id,
        target_message_id: target_message_id
      },
      tenant: tenant_schema
    )
    |> Ash.create!()
  end

  defp create_tenant!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(%{
        name: "#{prefix} #{suffix}",
        subject_name: "conversation-cluster-review-#{suffix}"
      })

    tenant
  end

  defp create_actor!(tenant_schema, handle) do
    Actor
    |> Ash.Changeset.for_create(
      :create,
      %{platform: "discord", handle: handle, display_name: String.capitalize(handle)},
      tenant: tenant_schema
    )
    |> Ash.create!()
  end

  defp create_channel!(tenant_schema, name) do
    Channel
    |> Ash.Changeset.for_create(:create, %{platform: "discord", name: name},
      tenant: tenant_schema
    )
    |> Ash.create!()
  end

  defp create_message!(tenant_schema, actor, channel, body, external_id, observed_at, metadata) do
    Message
    |> Ash.Changeset.for_create(
      :create,
      %{
        external_id: external_id,
        body: body,
        observed_at: observed_at,
        metadata: metadata,
        raw: %{},
        actor_id: actor.id,
        channel_id: channel.id
      },
      tenant: tenant_schema
    )
    |> Ash.create!()
  end

  defp create_entity!(tenant_schema, message_id, entity_type, name) do
    ExtractedEntity
    |> Ash.Changeset.for_create(
      :create,
      %{
        entity_type: entity_type,
        name: name,
        canonical_name: name,
        confidence: 0.9,
        metadata: %{},
        source_message_id: message_id
      },
      tenant: tenant_schema
    )
    |> Ash.create!()
  end
end
