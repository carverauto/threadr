defmodule Threadr.TenantData.MessageLinkInferenceTest do
  use Threadr.DataCase, async: false

  import Ash.Expr
  require Ash.Query

  alias Threadr.ControlPlane.Service

  alias Threadr.TenantData.{
    Actor,
    Channel,
    ExtractedEntity,
    Message,
    MessageLink,
    MessageLinkInference
  }

  test "infers and persists an answers link with evidence and margin" do
    tenant = create_tenant!("Message Link Inference")
    channel = create_channel!(tenant.schema_name, "ops")
    alice = create_actor!(tenant.schema_name, "alice")
    bob = create_actor!(tenant.schema_name, "bob")

    question =
      create_message!(
        tenant.schema_name,
        bob,
        channel,
        "Did the deploy finish on web-2?",
        "msg-question",
        ~U[2026-03-08 15:00:00Z],
        %{
          "dialogue_act" => %{"label" => "question", "confidence" => 0.94},
          "conversation_external_id" => "ops"
        }
      )

    create_entity!(tenant.schema_name, question.id, "artifact", "web-2")

    _other_candidate =
      create_message!(
        tenant.schema_name,
        bob,
        channel,
        "I am still checking some alerts.",
        "msg-other",
        ~U[2026-03-08 15:05:00Z],
        %{
          "dialogue_act" => %{"label" => "status_update", "confidence" => 0.7},
          "conversation_external_id" => "ops"
        }
      )

    answer =
      create_message!(
        tenant.schema_name,
        alice,
        channel,
        "Yes, web-2 finished successfully.",
        "msg-answer",
        ~U[2026-03-08 15:06:00Z],
        %{
          "dialogue_act" => %{"label" => "answer", "confidence" => 0.96},
          "reply_to_external_id" => "msg-question",
          "conversation_external_id" => "ops"
        }
      )

    create_entity!(tenant.schema_name, answer.id, "artifact", "web-2")

    assert {:ok, result} = MessageLinkInference.infer_and_persist(answer.id, tenant.schema_name)
    assert result.winner.link_type == "replies_to"
    assert result.winner.confidence_band == "high"
    assert result.winner.competing_candidate_margin > 0.0
    assert Enum.any?(result.winner.evidence, &(&1.kind == "explicit_reply"))
    assert Enum.any?(result.winner.evidence, &(&1.kind == "dialogue_act_match"))
    assert Enum.any?(result.winner.evidence, &(&1.kind == "entity_overlap"))

    assert {:ok, persisted} =
             MessageLink
             |> Ash.Query.filter(expr(source_message_id == ^answer.id))
             |> Ash.read_one(tenant: tenant.schema_name)

    assert persisted.target_message_id == question.id
    assert persisted.link_type == "replies_to"
    assert persisted.winning_decision_version == MessageLinkInference.decision_version()
    assert persisted.inferred_by == "threadr.reconstruction.rules"
    assert length(persisted.evidence) >= 3
  end

  test "leaves ambiguous low-signal messages unattached" do
    tenant = create_tenant!("Message Link Ambiguity")
    channel = create_channel!(tenant.schema_name, "ops")
    alice = create_actor!(tenant.schema_name, "alice")
    bob = create_actor!(tenant.schema_name, "bob")
    carol = create_actor!(tenant.schema_name, "carol")

    _candidate_one =
      create_message!(
        tenant.schema_name,
        bob,
        channel,
        "looking",
        "msg-1",
        ~U[2026-03-08 14:00:00Z],
        %{"conversation_external_id" => "ops"}
      )

    _candidate_two =
      create_message!(
        tenant.schema_name,
        carol,
        channel,
        "same",
        "msg-2",
        ~U[2026-03-08 14:01:00Z],
        %{"conversation_external_id" => "ops"}
      )

    focal =
      create_message!(
        tenant.schema_name,
        alice,
        channel,
        "yeah",
        "msg-3",
        ~U[2026-03-08 14:02:00Z],
        %{"conversation_external_id" => "ops"}
      )

    assert {:ok, result} = MessageLinkInference.infer_and_persist(focal.id, tenant.schema_name)
    assert result.winner == nil

    assert {:ok, nil} =
             MessageLink
             |> Ash.Query.filter(expr(source_message_id == ^focal.id))
             |> Ash.read_one(tenant: tenant.schema_name)
  end

  defp create_tenant!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(%{
        name: "#{prefix} #{suffix}",
        subject_name: "message-link-inference-#{suffix}"
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
