defmodule Threadr.ML.ActorQATest do
  use Threadr.DataCase, async: false

  alias Threadr.ControlPlane.Service
  alias Threadr.ML.ActorQA
  alias Threadr.TenantData.{Actor, Channel, Message, MessageMention}

  test "answers what a known actor mostly talks about from grounded actor history" do
    tenant = create_tenant!("Actor QA Topics")
    actor = create_actor!(tenant.schema_name, "twatbot")
    channel = create_channel!(tenant.schema_name, "irc")

    create_message!(
      tenant.schema_name,
      actor.id,
      channel.id,
      "twatbot keeps joking about backup jobs and broken cron tabs."
    )

    create_message!(
      tenant.schema_name,
      actor.id,
      channel.id,
      "twatbot asked whether the backup on server xyz finished."
    )

    create_message!(
      tenant.schema_name,
      actor.id,
      channel.id,
      "twatbot talked about operators, bots, and restart loops."
    )

    assert {:ok, result} =
             ActorQA.answer_question(
               tenant.subject_name,
               "what kind of stupid shit does twatbot mostly talk about?",
               generation_provider: Threadr.TestGenerationProvider,
               generation_model: "test-chat",
               limit: 3
             )

    assert result.query.kind == :talks_about
    assert result.query.actor_handle == "twatbot"
    assert length(result.matches) == 3
    assert result.context =~ "Actor-focused QA for what twatbot talks about."
    assert result.answer.content =~ "what kind of stupid shit does twatbot mostly talk about?"
  end

  test "answers what the tenant knows about an actor from actor messages and mentions" do
    tenant = create_tenant!("Actor QA Profile")
    actor = create_actor!(tenant.schema_name, "twatbot")
    other_actor = create_actor!(tenant.schema_name, "leku")
    channel = create_channel!(tenant.schema_name, "irc")

    own_message =
      create_message!(
        tenant.schema_name,
        actor.id,
        channel.id,
        "twatbot said the operator deploy finally recovered."
      )

    mention_message =
      create_message!(
        tenant.schema_name,
        other_actor.id,
        channel.id,
        "leku said twatbot keeps talking about deploys and bots."
      )

    create_message_mention!(tenant.schema_name, mention_message.id, actor.id)

    create_message!(
      tenant.schema_name,
      actor.id,
      channel.id,
      "twatbot asked about bot image drift again."
    )

    assert {:ok, result} =
             ActorQA.answer_question(
               tenant.subject_name,
               "what do you know about twatbot?",
               generation_provider: Threadr.TestGenerationProvider,
               generation_model: "test-chat",
               limit: 4
             )

    assert result.query.kind == :knows_about
    assert result.query.retrieval == "actor_messages_plus_mentions"
    assert result.query.actor_handle == "twatbot"
    assert Enum.any?(result.matches, &(&1.message_id == own_message.id))
    assert Enum.any?(result.matches, &(&1.message_id == mention_message.id))
    assert result.context =~ "Actor-focused QA for what the tenant history knows about twatbot."
  end

  test "answers what two known actors mostly talk about from grounded actor history" do
    tenant = create_tenant!("Actor QA Shared Topics")
    actor = create_actor!(tenant.schema_name, "hyralak")
    target_actor = create_actor!(tenant.schema_name, "sig")
    channel = create_channel!(tenant.schema_name, "irc")

    create_message!(
      tenant.schema_name,
      actor.id,
      channel.id,
      "hyralak keeps talking about deploys, IRC bots, and operator rollout issues."
    )

    create_message!(
      tenant.schema_name,
      actor.id,
      channel.id,
      "hyralak mentioned bot crashes, deploy drift, and restart loops again."
    )

    create_message!(
      tenant.schema_name,
      actor.id,
      channel.id,
      "hyralak asked about the latest bot rollout and deploy status."
    )

    create_message!(
      tenant.schema_name,
      target_actor.id,
      channel.id,
      "sig mostly talks about IRC bots, deploy failures, and rollout recovery."
    )

    create_message!(
      tenant.schema_name,
      target_actor.id,
      channel.id,
      "sig asked whether the operator deploy fixed the restart loop."
    )

    create_message!(
      tenant.schema_name,
      target_actor.id,
      channel.id,
      "sig talked about bot rollout status and deploy timing again."
    )

    assert {:ok, result} =
             ActorQA.answer_question(
               tenant.subject_name,
               "what do hyralak and sig mostly talk about?",
               generation_provider: Threadr.TestGenerationProvider,
               generation_model: "test-chat",
               limit: 6
             )

    assert result.query.kind == :shared_topics
    assert result.query.actor_handle == "hyralak"
    assert result.query.target_actor_handle == "sig"
    assert length(result.matches) >= 4
    assert result.context =~ "Actor-focused QA for what hyralak and sig mostly talk about."
    assert result.answer.content =~ "what do hyralak and sig mostly talk about?"
  end

  test "resolves self references from requester context" do
    tenant = create_tenant!("Actor QA Self Reference")
    actor = create_actor!(tenant.schema_name, "leku")
    other_actor = create_actor!(tenant.schema_name, "sig")
    channel = create_channel!(tenant.schema_name, "irc")

    create_message!(
      tenant.schema_name,
      actor.id,
      channel.id,
      "leku talked about IRC bots and deploy drift."
    )

    create_message!(
      tenant.schema_name,
      actor.id,
      channel.id,
      "leku asked whether the rollout recovered."
    )

    mention_message =
      create_message!(
        tenant.schema_name,
        other_actor.id,
        channel.id,
        "sig said leku keeps talking about bot deploys and rollout status."
      )

    create_message_mention!(tenant.schema_name, mention_message.id, actor.id)

    assert {:ok, result} =
             ActorQA.answer_question(
               tenant.subject_name,
               "what do you know about me?",
               generation_provider: Threadr.TestGenerationProvider,
               generation_model: "test-chat",
               requester_actor_handle: "leku",
               limit: 4
             )

    assert result.query.kind == :knows_about
    assert result.query.actor_handle == "leku"
    assert result.context =~ "Actor-focused QA for what the tenant history knows about leku."
    assert result.answer.content =~ "what do you know about me?"
  end

  test "returns explicit actor-not-found guidance for missing actors" do
    tenant = create_tenant!("Actor QA Missing")

    assert {:ok, result} =
             ActorQA.answer_question(
               tenant.subject_name,
               "what do you know about madeupguy?",
               generation_provider: Threadr.TestGenerationProvider,
               generation_model: "test-chat"
             )

    assert result.query.status == "actor_not_found"
    assert result.answer.content =~ "can't find actor"
    assert result.matches == []
  end

  test "returns insufficient evidence for sparse actor history" do
    tenant = create_tenant!("Actor QA Sparse")
    actor = create_actor!(tenant.schema_name, "larsin10")
    channel = create_channel!(tenant.schema_name, "irc")

    create_message!(tenant.schema_name, actor.id, channel.id, "larsin10 asked about rust.")
    create_message!(tenant.schema_name, actor.id, channel.id, "larsin10 mentioned compilers.")

    assert {:ok, result} =
             ActorQA.answer_question(
               tenant.subject_name,
               "what does larsin10 talk about?",
               generation_provider: Threadr.TestGenerationProvider,
               generation_model: "test-chat"
             )

    assert result.query.status == "insufficient_evidence"
    assert result.answer.content =~ "isn't enough grounded tenant history"
    assert length(result.matches) == 2
  end

  defp create_tenant!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(%{
        name: "#{prefix} #{suffix}",
        subject_name: "#{String.downcase(String.replace(prefix, " ", "-"))}-#{suffix}"
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

  defp create_message!(tenant_schema, actor_id, channel_id, body) do
    Message
    |> Ash.Changeset.for_create(
      :create,
      %{
        external_id: Ecto.UUID.generate(),
        body: body,
        observed_at: DateTime.utc_now(),
        raw: %{"body" => body},
        metadata: %{},
        actor_id: actor_id,
        channel_id: channel_id
      },
      tenant: tenant_schema
    )
    |> Ash.create!()
  end

  defp create_message_mention!(tenant_schema, message_id, actor_id) do
    MessageMention
    |> Ash.Changeset.for_create(
      :create,
      %{message_id: message_id, actor_id: actor_id},
      tenant: tenant_schema
    )
    |> Ash.create!()
  end
end
