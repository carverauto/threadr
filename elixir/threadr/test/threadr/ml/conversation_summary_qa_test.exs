defmodule Threadr.ML.ConversationSummaryQATest do
  use Threadr.DataCase, async: false

  alias Threadr.ControlPlane.Service
  alias Threadr.ML.ConversationSummaryQA

  alias Threadr.TenantData.{
    Actor,
    Channel,
    ConversationAttachment,
    ExtractedEntity,
    Message,
    MessageLinkInference
  }

  test "answers time-bounded conversation summary questions with grounded citations" do
    tenant = create_tenant!("Conversation Summary QA")
    alice = create_actor!(tenant.schema_name, "alice")
    bob = create_actor!(tenant.schema_name, "bob")
    channel = create_channel!(tenant.schema_name, "ops")

    request_message =
      create_message!(
        tenant.schema_name,
        alice.id,
        channel.id,
        "Can you validate web-4 before deploy?",
        "msg-question",
        ~U[2026-03-08 10:00:00Z],
        %{
          "dialogue_act" => %{"label" => "request", "confidence" => 0.92},
          "conversation_external_id" => "ops"
        }
      )

    response_message =
      create_message!(
        tenant.schema_name,
        bob.id,
        channel.id,
        "Yes, I validated web-4 before deploy.",
        "msg-answer",
        ~U[2026-03-08 10:05:00Z],
        %{
          "dialogue_act" => %{"label" => "status_update", "confidence" => 0.86},
          "reply_to_external_id" => request_message.external_id,
          "conversation_external_id" => "ops"
        }
      )

    create_entity!(tenant.schema_name, request_message.id, "artifact", "web-4")
    create_entity!(tenant.schema_name, response_message.id, "artifact", "web-4")

    {:ok, _initial_conversation} =
      ConversationAttachment.attach_message(
        request_message.id,
        tenant.schema_name
      )

    {:ok, inference} =
      MessageLinkInference.infer_and_persist(response_message.id, tenant.schema_name)

    {:ok, _conversation} =
      ConversationAttachment.attach_message(
        response_message.id,
        tenant.schema_name,
        inference: inference
      )

    assert {:ok, result} =
             ConversationSummaryQA.answer_question(
               tenant.subject_name,
               "What happened last week?",
               since: ~U[2026-03-01 00:00:00Z],
               until: ~U[2026-03-09 00:00:00Z],
               generation_provider: Threadr.TestGenerationProvider,
               generation_model: "test-chat"
             )

    assert result.query.kind == :time_bounded_summary
    assert result.query.retrieval == "reconstructed_conversations_plus_messages"
    assert result.query.conversation_count == 1
    assert result.query.message_count == 2
    assert length(result.citations) == 2
    assert length(result.matches) == 2

    assert result.context =~
             "Conversation summary QA for tenant activity in the requested time window."

    assert result.context =~ "Supporting citations: C1, C2"
    assert result.answer.content =~ "What happened last week?"
  end

  test "returns not_conversation_summary_question when reconstruction tables are unavailable" do
    tenant = create_tenant!("Conversation Summary QA Missing Tables")

    drop_reconstruction_tables!(tenant.schema_name)

    assert {:error, :not_conversation_summary_question} =
             ConversationSummaryQA.answer_question(
               tenant.subject_name,
               "What happened today?",
               since: ~U[2026-03-09 00:00:00Z],
               until: ~U[2026-03-10 00:00:00Z],
               generation_provider: Threadr.TestGenerationProvider,
               generation_model: "test-chat"
             )
  end

  test "infers time bounds and current-channel scope for recap questions" do
    tenant = create_tenant!("Conversation Summary QA Recap")
    alice = create_actor!(tenant.schema_name, "alice")
    bob = create_actor!(tenant.schema_name, "bob")
    carol = create_actor!(tenant.schema_name, "carol")
    chases = create_channel!(tenant.schema_name, "#!chases")
    ops = create_channel!(tenant.schema_name, "#ops")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    chases_request =
      create_message!(
        tenant.schema_name,
        alice.id,
        chases.id,
        "Can you validate web-9 before deploy?",
        "msg-chases-question",
        now,
        %{
          "dialogue_act" => %{"label" => "request", "confidence" => 0.92},
          "conversation_external_id" => "#!chases"
        }
      )

    chases_response =
      create_message!(
        tenant.schema_name,
        bob.id,
        chases.id,
        "Yes, I validated web-9 and the release looks clean.",
        "msg-chases-answer",
        DateTime.add(now, 120, :second),
        %{
          "dialogue_act" => %{"label" => "status_update", "confidence" => 0.86},
          "reply_to_external_id" => chases_request.external_id,
          "conversation_external_id" => "#!chases"
        }
      )

    ops_request =
      create_message!(
        tenant.schema_name,
        carol.id,
        ops.id,
        "Can you reboot the worker after hours?",
        "msg-ops-question",
        DateTime.add(now, 240, :second),
        %{
          "dialogue_act" => %{"label" => "request", "confidence" => 0.92},
          "conversation_external_id" => "#ops"
        }
      )

    ops_response =
      create_message!(
        tenant.schema_name,
        bob.id,
        ops.id,
        "Yes, I will reboot it tonight after the queue drains.",
        "msg-ops-answer",
        DateTime.add(now, 360, :second),
        %{
          "dialogue_act" => %{"label" => "status_update", "confidence" => 0.86},
          "reply_to_external_id" => ops_request.external_id,
          "conversation_external_id" => "#ops"
        }
      )

    {:ok, _} = ConversationAttachment.attach_message(chases_request.id, tenant.schema_name)

    {:ok, chases_inference} =
      MessageLinkInference.infer_and_persist(chases_response.id, tenant.schema_name)

    {:ok, _} =
      ConversationAttachment.attach_message(
        chases_response.id,
        tenant.schema_name,
        inference: chases_inference
      )

    {:ok, _} = ConversationAttachment.attach_message(ops_request.id, tenant.schema_name)

    {:ok, ops_inference} =
      MessageLinkInference.infer_and_persist(ops_response.id, tenant.schema_name)

    {:ok, _} =
      ConversationAttachment.attach_message(
        ops_response.id,
        tenant.schema_name,
        inference: ops_inference
      )

    assert {:ok, result} =
             ConversationSummaryQA.answer_question(
               tenant.subject_name,
               "can you recap the channel discussions for today please",
               requester_channel_name: "#!chases",
               generation_provider: Threadr.TestGenerationProvider,
               generation_model: "test-chat"
             )

    assert result.query.kind == :time_bounded_summary
    assert result.query.channel_name == "#!chases"
    assert result.query.conversation_count == 1
    assert result.query.message_count == 2
    assert result.context =~ "#!chases"
    refute result.context =~ "#ops"
    assert result.answer.content =~ "can you recap the channel discussions for today please"
  end

  test "recap questions include more than the latest five same-day conversations" do
    tenant = create_tenant!("Conversation Summary QA Wider Recall")
    alice = create_actor!(tenant.schema_name, "alice")
    bob = create_actor!(tenant.schema_name, "bob")
    channel = create_channel!(tenant.schema_name, "#!chases")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    for index <- 1..7 do
      request_message =
        create_message!(
          tenant.schema_name,
          alice.id,
          channel.id,
          "Conversation #{index} request about topic #{index}",
          "msg-recap-request-#{index}",
          DateTime.add(now, index * 120, :second),
          %{
            "dialogue_act" => %{"label" => "request", "confidence" => 0.92},
            "conversation_external_id" => "recap-#{index}"
          }
        )

      response_message =
        create_message!(
          tenant.schema_name,
          bob.id,
          channel.id,
          "Conversation #{index} response about topic #{index}",
          "msg-recap-response-#{index}",
          DateTime.add(now, index * 120 + 60, :second),
          %{
            "dialogue_act" => %{"label" => "status_update", "confidence" => 0.86},
            "reply_to_external_id" => request_message.external_id,
            "conversation_external_id" => "recap-#{index}"
          }
        )

      create_entity!(tenant.schema_name, request_message.id, "topic", "topic-#{index}")
      create_entity!(tenant.schema_name, response_message.id, "topic", "topic-#{index}")

      {:ok, _} = ConversationAttachment.attach_message(request_message.id, tenant.schema_name)

      {:ok, inference} =
        MessageLinkInference.infer_and_persist(response_message.id, tenant.schema_name)

      {:ok, _} =
        ConversationAttachment.attach_message(
          response_message.id,
          tenant.schema_name,
          inference: inference
        )
    end

    assert {:ok, result} =
             ConversationSummaryQA.answer_question(
               tenant.subject_name,
               "can you recap the channel discussions for today please",
               requester_channel_name: "#!chases",
               generation_provider: Threadr.TestGenerationProvider,
               generation_model: "test-chat"
             )

    assert result.query.conversation_count == 7
    assert result.query.message_count == 14
    assert length(result.conversations) == 7
    assert length(result.citations) >= 7
  end

  test "summarizes a same-day named-channel message window even without reconstructed conversations" do
    tenant = create_tenant!("Conversation Summary QA Message Window")
    leku = create_actor!(tenant.schema_name, "leku")
    thanew = create_actor!(tenant.schema_name, "THANEW")
    larsini0 = create_actor!(tenant.schema_name, "larsini0")
    channel = create_channel!(tenant.schema_name, "#!chases")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    create_message!(
      tenant.schema_name,
      larsini0.id,
      channel.id,
      "THANEW: u can tell i play a certain kind of dnb",
      "msg-window-1",
      now,
      %{}
    )

    create_message!(
      tenant.schema_name,
      thanew.id,
      channel.id,
      "not a big fan of dnb tbh",
      "msg-window-2",
      DateTime.add(now, 120, :second),
      %{}
    )

    create_message!(
      tenant.schema_name,
      leku.id,
      channel.id,
      "zero point energy tweet was nonsense",
      "msg-window-3",
      DateTime.add(now, 240, :second),
      %{}
    )

    assert {:ok, result} =
             ConversationSummaryQA.answer_question(
               tenant.subject_name,
               "summarize the topics from todays chats in #!chases",
               requester_channel_name: "#!chases",
               generation_provider: Threadr.TestGenerationProvider,
               generation_model: "test-chat"
             )

    assert result.query.retrieval == "message_window"
    assert result.query.conversation_count == 0
    assert result.query.message_count == 3
    assert result.context =~ "window_messages=3"
    assert result.context =~ "not a big fan of dnb tbh"
    assert result.context =~ "zero point energy tweet was nonsense"
  end

  test "includes hybrid-ranked summary messages that fall outside the chronological window slice" do
    tenant = create_tenant!("Conversation Summary QA Hybrid Window")
    leku = create_actor!(tenant.schema_name, "leku")
    thanew = create_actor!(tenant.schema_name, "THANEW")
    larsini0 = create_actor!(tenant.schema_name, "larsini0")
    channel = create_channel!(tenant.schema_name, "#!chases")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    create_message!(
      tenant.schema_name,
      leku.id,
      channel.id,
      "today mostly involved random banter about travel prep",
      "hybrid-window-1",
      now,
      %{}
    )

    create_message!(
      tenant.schema_name,
      larsini0.id,
      channel.id,
      "people also complained about coffee and sleep",
      "hybrid-window-2",
      DateTime.add(now, 60, :second),
      %{}
    )

    create_message!(
      tenant.schema_name,
      leku.id,
      channel.id,
      "someone dropped a zero point energy link again",
      "hybrid-window-3",
      DateTime.add(now, 120, :second),
      %{}
    )

    create_message!(
      tenant.schema_name,
      thanew.id,
      channel.id,
      "not a big fan of dnb tbh",
      "hybrid-window-4",
      DateTime.add(now, 180, :second),
      %{}
    )

    assert {:ok, result} =
             ConversationSummaryQA.answer_question(
               tenant.subject_name,
               "summarize the topics from todays chats in #!chases about dnb",
               requester_channel_name: "#!chases",
               message_limit: 3,
               embedding_provider: Threadr.TestEmbeddingProvider,
               embedding_model: "test-embedding-model",
               generation_provider: Threadr.TestGenerationProvider,
               generation_model: "test-chat"
             )

    assert result.query.retrieval == "message_window"
    assert result.query.message_count == 3
    assert result.context =~ "not a big fan of dnb tbh"
  end

  defp create_tenant!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(%{
        name: "#{prefix} #{suffix}",
        subject_name: "conversation-summary-qa-#{suffix}"
      })

    tenant
  end

  defp create_actor!(tenant_schema, handle) do
    Actor
    |> Ash.Changeset.for_create(
      :create,
      %{platform: "irc", handle: handle, display_name: String.capitalize(handle)},
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

  defp drop_reconstruction_tables!(tenant_schema) do
    Threadr.Repo.query!(
      "DROP TABLE IF EXISTS \"#{tenant_schema}\".\"conversation_memberships\" CASCADE"
    )

    Threadr.Repo.query!("DROP TABLE IF EXISTS \"#{tenant_schema}\".\"conversations\" CASCADE")
  end
end
