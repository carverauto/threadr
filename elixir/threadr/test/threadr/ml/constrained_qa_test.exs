defmodule Threadr.ML.ConstrainedQATest do
  use Threadr.DataCase, async: false

  alias Threadr.ControlPlane.Service
  alias Threadr.ML.ConstrainedQA
  alias Threadr.TenantData.{Actor, Channel, Message}

  test "answers actor topical questions constrained to today" do
    tenant = create_tenant!("Constrained QA Actor Today")
    actor = create_actor!(tenant.schema_name, "farmr")
    channel = create_channel!(tenant.schema_name, "#!chases")

    create_message!(
      tenant.schema_name,
      actor.id,
      channel.id,
      "farmr talked about terrace produce, planters, and a garden today.",
      "farmr-today",
      DateTime.utc_now() |> DateTime.truncate(:second)
    )

    assert {:ok, result} =
             ConstrainedQA.answer_question(
               tenant.subject_name,
               "what did farmr talk about today?",
               generation_provider: Threadr.TestConstraintGenerationProvider,
               generation_model: "test-chat"
             )

    assert result.query.mode == "constrained_qa"
    assert result.query.actor_handles == ["farmr"]
    assert result.context =~ "farmr"
    assert result.context =~ "terrace produce"
  end

  test "answers current-channel topical summary questions constrained to today" do
    tenant = create_tenant!("Constrained QA Channel Today")
    farmr = create_actor!(tenant.schema_name, "farmr")
    leku = create_actor!(tenant.schema_name, "leku")
    channel = create_channel!(tenant.schema_name, "#!chases")

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    create_message!(
      tenant.schema_name,
      farmr.id,
      channel.id,
      "terrace garden and produce",
      "m1",
      now
    )

    create_message!(
      tenant.schema_name,
      leku.id,
      channel.id,
      "cig butts on the terrace",
      "m2",
      now
    )

    assert {:ok, result} =
             ConstrainedQA.answer_question(
               tenant.subject_name,
               "what were the general topics that people talked about today in this channel then?",
               requester_channel_name: "#!chases",
               generation_provider: Threadr.TestConstraintGenerationProvider,
               generation_model: "test-chat"
             )

    assert result.query.channel_name == "#!chases"
    assert result.context =~ "#!chases"
    refute result.context =~ "##!chases"
  end

  test "answers actor plus counterpart topical questions constrained to today" do
    tenant = create_tenant!("Constrained QA Counterpart")
    fysty = create_actor!(tenant.schema_name, "fysty")
    leku = create_actor!(tenant.schema_name, "leku")
    channel = create_channel!(tenant.schema_name, "#!chases")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    create_message!(
      tenant.schema_name,
      fysty.id,
      channel.id,
      "leku I should start a garden on my terrace with produce.",
      "fysty-counterpart",
      now
    )

    create_message!(
      tenant.schema_name,
      leku.id,
      channel.id,
      "terrace plan sounds good",
      "leku-counterpart",
      now
    )

    assert {:ok, result} =
             ConstrainedQA.answer_question(
               tenant.subject_name,
               "what did fysty talk about today with leku?",
               generation_provider: Threadr.TestConstraintGenerationProvider,
               generation_model: "test-chat"
             )

    assert result.query.retrieval in [
             "shared_conversation_messages",
             "actor_messages_about_counterpart"
           ]

    assert result.query.actor_handles == ["fysty"]
    assert result.query.counterpart_actor_handles == ["leku"]
    assert result.context =~ "garden on my terrace"
  end

  defp create_tenant!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(%{
        name: "#{prefix} #{suffix}",
        subject_name: "constrained-qa-#{suffix}"
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

  defp create_message!(tenant_schema, actor_id, channel_id, body, external_id, observed_at) do
    Message
    |> Ash.Changeset.for_create(
      :create,
      %{
        external_id: external_id,
        body: body,
        observed_at: observed_at,
        raw: %{"body" => body},
        metadata: %{},
        actor_id: actor_id,
        channel_id: channel_id
      },
      tenant: tenant_schema
    )
    |> Ash.create!()
  end
end
