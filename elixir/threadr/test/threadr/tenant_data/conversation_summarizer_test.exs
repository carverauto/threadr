defmodule Threadr.TenantData.ConversationSummarizerTest do
  use Threadr.DataCase, async: false

  import Ash.Expr
  require Ash.Query

  alias Threadr.ControlPlane.Service

  alias Threadr.TenantData.{
    Actor,
    Channel,
    Conversation,
    ConversationAttachment,
    ConversationSummarizer,
    ConversationSummaryDispatcher,
    ExtractedEntity,
    Message,
    MessageLinkInference
  }

  setup do
    previous_ml = Application.get_env(:threadr, Threadr.ML, [])

    on_exit(fn ->
      Application.put_env(:threadr, Threadr.ML, previous_ml)
    end)

    :ok
  end

  test "summarize_conversation stores a generated topic and summary on the conversation" do
    %{tenant: tenant, conversation: conversation} = create_reconstructed_conversation!("direct")

    assert conversation.metadata["summary_needs_refresh"] == true

    assert {:ok, summarized} =
             ConversationSummarizer.summarize_conversation(
               conversation.id,
               tenant.schema_name,
               generation_provider: Threadr.TestConversationSummaryProvider,
               generation_model: "test-chat"
             )

    assert summarized.topic_summary == "web-4 validation"
    assert summarized.metadata["summary_needs_refresh"] == false

    assert summarized.metadata["conversation_summary"]["text"] =~
             "Alice later reported the validation was complete"

    assert summarized.metadata["conversation_summary"]["message_ids"] ==
             [conversation.starter_message_id, summarized.most_recent_message_id]

    assert summarized.confidence_summary["summary_source"] == "batch_generation"
  end

  test "dispatcher refreshes pending conversation summaries across tenants" do
    ml_config = Application.get_env(:threadr, Threadr.ML, [])

    Application.put_env(
      :threadr,
      Threadr.ML,
      Keyword.put(ml_config, :generation,
        provider: Threadr.TestConversationSummaryProvider,
        model: "test-chat"
      )
    )

    %{tenant: tenant, conversation: conversation} = create_reconstructed_conversation!("dispatch")

    assert :ok = ConversationSummaryDispatcher.process_pending_once()

    assert {:ok, refreshed} =
             Conversation
             |> Ash.Query.filter(expr(id == ^conversation.id))
             |> Ash.read_one(tenant: tenant.schema_name)

    assert refreshed.topic_summary == "web-4 validation"
    assert refreshed.metadata["summary_needs_refresh"] == false
    assert refreshed.metadata["conversation_summary"]["provider"] == "test-conversation-summary"
  end

  defp create_reconstructed_conversation!(suffix) do
    tenant = create_tenant!("Conversation Summary #{suffix}")
    channel = create_channel!(tenant.schema_name, "ops-#{suffix}")
    alice = create_actor!(tenant.schema_name, "alice-#{suffix}")
    bob = create_actor!(tenant.schema_name, "bob-#{suffix}")

    question =
      create_message!(
        tenant.schema_name,
        bob,
        channel,
        "Can you validate web-4?",
        "msg-request-#{suffix}",
        ~U[2026-03-08 10:00:00Z],
        %{
          "dialogue_act" => %{"label" => "request", "confidence" => 0.92},
          "conversation_external_id" => channel.name
        }
      )

    completion =
      create_message!(
        tenant.schema_name,
        alice,
        channel,
        "I validated web-4 successfully.",
        "msg-complete-#{suffix}",
        ~U[2026-03-08 10:05:00Z],
        %{
          "dialogue_act" => %{"label" => "status_update", "confidence" => 0.86},
          "reply_to_external_id" => question.external_id,
          "conversation_external_id" => channel.name
        }
      )

    create_entity!(tenant.schema_name, question.id, "artifact", "web-4")
    create_entity!(tenant.schema_name, completion.id, "artifact", "web-4")

    {:ok, inference} = MessageLinkInference.infer_and_persist(completion.id, tenant.schema_name)

    {:ok, conversation} =
      ConversationAttachment.attach_message(
        completion.id,
        tenant.schema_name,
        inference: inference
      )

    %{tenant: tenant, conversation: conversation}
  end

  defp create_tenant!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(%{
        name: "#{prefix} #{suffix}",
        subject_name: "conversation-summary-#{suffix}"
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
