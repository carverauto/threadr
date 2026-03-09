defmodule Threadr.TenantData.ReconstructionCandidatesTest do
  use Threadr.DataCase, async: false

  alias Threadr.ControlPlane.Service

  alias Threadr.TenantData.{
    Actor,
    Channel,
    ExtractedEntity,
    Message,
    ReconstructionCandidates
  }

  test "prioritizes an explicit reply target inside bounded recent message retrieval" do
    tenant = create_tenant!("Reconstruction Candidates")
    channel = create_channel!(tenant.schema_name, "ops")
    alice = create_actor!(tenant.schema_name, "alice")
    bob = create_actor!(tenant.schema_name, "bob")
    now = ~U[2026-03-08 15:00:00Z]

    explicit_target =
      create_message!(
        tenant.schema_name,
        bob,
        channel,
        "Did the deploy finish on server-1?",
        "msg-1",
        DateTime.add(now, -48, :hour),
        %{
          "dialogue_act" => %{"label" => "question", "confidence" => 0.91},
          "conversation_external_id" => "ops"
        }
      )

    create_entity!(tenant.schema_name, explicit_target.id, "artifact", "server-1")

    recent_message =
      create_message!(
        tenant.schema_name,
        bob,
        channel,
        "I am checking logs now.",
        "msg-2",
        DateTime.add(now, -15, :minute),
        %{
          "dialogue_act" => %{"label" => "status_update", "confidence" => 0.8},
          "conversation_external_id" => "ops"
        }
      )

    focal_message =
      create_message!(
        tenant.schema_name,
        alice,
        channel,
        "Yes, deploy completed.",
        "msg-3",
        now,
        %{
          "dialogue_act" => %{"label" => "answer", "confidence" => 0.95},
          "reply_to_external_id" => explicit_target.external_id,
          "conversation_external_id" => "ops"
        }
      )

    assert {:ok, candidates} =
             ReconstructionCandidates.for_message(
               focal_message.id,
               tenant.schema_name,
               message_limit: 2,
               lookback_hours: 24
             )

    assert Enum.map(candidates.recent_messages, & &1.id) == [
             explicit_target.id,
             recent_message.id
           ]

    assert hd(candidates.recent_messages).dialogue_act.label == "question"
    assert hd(candidates.recent_messages).entity_names == ["server-1"]
  end

  test "derives recent conversations and unresolved items from recent message history" do
    tenant = create_tenant!("Reconstruction Conversations")
    channel = create_channel!(tenant.schema_name, "ops")
    alice = create_actor!(tenant.schema_name, "alice")
    bob = create_actor!(tenant.schema_name, "bob")
    carol = create_actor!(tenant.schema_name, "carol")
    now = ~U[2026-03-08 16:00:00Z]

    answered_question =
      create_message!(
        tenant.schema_name,
        alice,
        channel,
        "bob: did the backup finish on server-1?",
        "msg-q1",
        DateTime.add(now, -90, :minute),
        %{
          "dialogue_act" => %{"label" => "question", "confidence" => 0.92},
          "conversation_external_id" => "ops"
        }
      )

    create_entity!(tenant.schema_name, answered_question.id, "artifact", "server-1")

    create_message!(
      tenant.schema_name,
      bob,
      channel,
      "Yes, the backup finished.",
      "msg-a1",
      DateTime.add(now, -85, :minute),
      %{
        "dialogue_act" => %{"label" => "answer", "confidence" => 0.93},
        "reply_to_external_id" => answered_question.external_id,
        "conversation_external_id" => "ops"
      }
    )

    open_request =
      create_message!(
        tenant.schema_name,
        bob,
        channel,
        "Can someone validate the deploy on web-2?",
        "msg-q2",
        DateTime.add(now, -18, :minute),
        %{
          "dialogue_act" => %{"label" => "request", "confidence" => 0.9},
          "conversation_external_id" => "ops"
        }
      )

    create_entity!(tenant.schema_name, open_request.id, "artifact", "web-2")

    coordinating_message =
      create_message!(
        tenant.schema_name,
        carol,
        channel,
        "I can take a look.",
        "msg-s1",
        DateTime.add(now, -12, :minute),
        %{
          "dialogue_act" => %{"label" => "coordination", "confidence" => 0.7},
          "conversation_external_id" => "ops"
        }
      )

    focal_message =
      create_message!(
        tenant.schema_name,
        alice,
        channel,
        "I am checking web-2 now.",
        "msg-focal",
        now,
        %{
          "dialogue_act" => %{"label" => "status_update", "confidence" => 0.88},
          "conversation_external_id" => "ops"
        }
      )

    assert {:ok, candidates} =
             ReconstructionCandidates.for_message(
               focal_message.id,
               tenant.schema_name,
               conversation_limit: 4,
               unresolved_limit: 4,
               lookback_hours: 96
             )

    assert length(candidates.recent_conversations) == 2

    latest_conversation = hd(candidates.recent_conversations)
    assert latest_conversation.message_ids == [open_request.id, coordinating_message.id]
    assert "request" in latest_conversation.dialogue_labels
    assert latest_conversation.entity_names == ["web-2"]

    assert [
             %{
               opener_message_id: unresolved_id,
               dialogue_act: %{label: "request"},
               entity_names: ["web-2"]
             }
           ] = candidates.unresolved_items

    assert unresolved_id == open_request.id
  end

  defp create_tenant!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(%{
        name: "#{prefix} #{suffix}",
        subject_name: "reconstruction-candidates-#{suffix}"
      })

    tenant
  end

  defp create_actor!(tenant_schema, handle) do
    Actor
    |> Ash.Changeset.for_create(
      :create,
      %{
        platform: "discord",
        handle: handle,
        display_name: String.capitalize(handle)
      },
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

  defp create_message!(
         tenant_schema,
         actor,
         channel,
         body,
         external_id,
         observed_at,
         metadata
       ) do
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
