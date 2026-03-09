defmodule Threadr.ML.InteractionQATest do
  use Threadr.DataCase, async: false

  alias Threadr.ControlPlane.Service
  alias Threadr.ML.InteractionQA

  alias Threadr.TenantData.{
    Actor,
    Channel,
    ConversationAttachment,
    ConversationRelationshipRecompute,
    Message,
    MessageLinkInference
  }

  test "answers who an actor mostly talks with from reconstructed interaction evidence" do
    tenant = create_tenant!("Interaction QA")
    sig = create_actor!(tenant.schema_name, "sig")
    bysin = create_actor!(tenant.schema_name, "bysin")
    channel = create_channel!(tenant.schema_name, "#!chases")

    request_message =
      create_message!(
        tenant.schema_name,
        sig.id,
        channel.id,
        "bysin can you sanity check the deploy?",
        "msg-sig-1",
        ~U[2026-03-08 10:00:00Z],
        %{
          "dialogue_act" => %{"label" => "request", "confidence" => 0.92},
          "conversation_external_id" => "#!chases"
        }
      )

    response_message =
      create_message!(
        tenant.schema_name,
        bysin.id,
        channel.id,
        "yeah I checked it, deploy looks clean",
        "msg-bysin-1",
        ~U[2026-03-08 10:02:00Z],
        %{
          "dialogue_act" => %{"label" => "status_update", "confidence" => 0.88},
          "reply_to_external_id" => request_message.external_id,
          "conversation_external_id" => "#!chases"
        }
      )

    {:ok, conversation} =
      ConversationAttachment.attach_message(request_message.id, tenant.schema_name)

    {:ok, inference} =
      MessageLinkInference.infer_and_persist(response_message.id, tenant.schema_name)

    {:ok, _conversation} =
      ConversationAttachment.attach_message(
        response_message.id,
        tenant.schema_name,
        inference: inference
      )

    assert {:ok, _} =
             ConversationRelationshipRecompute.recompute_conversation_relationships(
               conversation.id,
               tenant.schema_name
             )

    assert {:ok, result} =
             InteractionQA.answer_question(
               tenant.subject_name,
               "who does sig talk with the most?",
               generation_provider: Threadr.TestGenerationProvider,
               generation_model: "test-chat"
             )

    assert result.query.mode == "interaction_qa"
    assert result.query.actor_handle == "sig"
    assert length(result.partners) == 1
    assert hd(result.partners).partner_handle == "bysin"
    assert result.context =~ "bysin"
    assert result.context =~ "#!chases"
    refute result.context =~ "##!chases"
  end

  test "returns not_interaction_question when reconstruction tables are unavailable" do
    tenant = create_tenant!("Interaction QA Missing Tables")
    _sig = create_actor!(tenant.schema_name, "sig")

    drop_reconstruction_tables!(tenant.schema_name)

    assert {:error, :not_interaction_question} =
             InteractionQA.answer_question(
               tenant.subject_name,
               "who does sig talk with the most?",
               generation_provider: Threadr.TestGenerationProvider,
               generation_model: "test-chat"
             )
  end

  test "falls back to reconstructed conversation memberships when relationships are absent" do
    tenant = create_tenant!("Interaction QA Conversation Fallback")
    thanew = create_actor!(tenant.schema_name, "THANEW")
    bysin = create_actor!(tenant.schema_name, "bysin")
    channel = create_channel!(tenant.schema_name, "#!chases")

    request_message =
      create_message!(
        tenant.schema_name,
        thanew.id,
        channel.id,
        "bysin did you look at the spark plugs yet?",
        "msg-thanew-1",
        ~U[2026-03-08 12:00:00Z],
        %{
          "dialogue_act" => %{"label" => "request", "confidence" => 0.92},
          "conversation_external_id" => "#!chases"
        }
      )

    response_message =
      create_message!(
        tenant.schema_name,
        bysin.id,
        channel.id,
        "yeah they looked rough, the gap was off and the insulator was toast",
        "msg-bysin-2",
        ~U[2026-03-08 12:02:00Z],
        %{
          "dialogue_act" => %{"label" => "answer", "confidence" => 0.88},
          "reply_to_external_id" => request_message.external_id,
          "conversation_external_id" => "#!chases"
        }
      )

    {:ok, _conversation} =
      ConversationAttachment.attach_message(request_message.id, tenant.schema_name)

    {:ok, inference} =
      MessageLinkInference.infer_and_persist(response_message.id, tenant.schema_name)

    {:ok, _conversation} =
      ConversationAttachment.attach_message(
        response_message.id,
        tenant.schema_name,
        inference: inference
      )

    assert {:ok, result} =
             InteractionQA.answer_question(
               tenant.subject_name,
               "who does THANEW mostly talk with?",
               generation_provider: Threadr.TestGenerationProvider,
               generation_model: "test-chat"
             )

    assert result.query.mode == "interaction_qa"
    assert result.query.actor_handle == "THANEW"
    assert hd(result.partners).partner_handle == "bysin"
    assert result.context =~ "bysin"
  end

  defp create_tenant!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(%{
        name: "#{prefix} #{suffix}",
        subject_name: "interaction-qa-#{suffix}"
      })

    tenant
  end

  defp create_actor!(tenant_schema, handle) do
    Actor
    |> Ash.Changeset.for_create(
      :create,
      %{platform: "irc", handle: handle, display_name: handle},
      tenant: tenant_schema
    )
    |> Ash.create!()
  end

  defp create_channel!(tenant_schema, name) do
    Channel
    |> Ash.Changeset.for_create(
      :create,
      %{platform: "irc", name: name},
      tenant: tenant_schema
    )
    |> Ash.create!()
  end

  defp create_message!(
         tenant_schema,
         actor_id,
         channel_id,
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
        raw: %{"body" => body},
        metadata: metadata,
        actor_id: actor_id,
        channel_id: channel_id
      },
      tenant: tenant_schema
    )
    |> Ash.create!()
  end

  defp drop_reconstruction_tables!(tenant_schema) do
    Threadr.Repo.query!(
      "DROP TABLE IF EXISTS \"#{tenant_schema}\".\"conversation_memberships\" CASCADE"
    )

    Threadr.Repo.query!("DROP TABLE IF EXISTS \"#{tenant_schema}\".\"conversations\" CASCADE")
  end
end
