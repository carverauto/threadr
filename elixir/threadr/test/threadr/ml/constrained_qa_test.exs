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
             "paired_actor_messages",
             "shared_conversation_messages",
             "actor_messages_about_counterpart"
           ]

    assert result.query.actor_handles == ["fysty"]
    assert result.query.counterpart_actor_handles == ["leku"]
    assert result.context =~ "garden on my terrace"
  end

  test "pair questions require evidence from both actors and exclude one-sided messages" do
    tenant = create_tenant!("Constrained QA Pair Guard")
    sig = create_actor!(tenant.schema_name, "sig")
    eefer = create_actor!(tenant.schema_name, "eefer--")
    dio = create_actor!(tenant.schema_name, "dio")
    channel = create_channel!(tenant.schema_name, "#!chases")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    create_message!(
      tenant.schema_name,
      eefer.id,
      channel.id,
      "sig: What is Havana Syndrome?",
      "eefer-1",
      now
    )

    create_message!(
      tenant.schema_name,
      sig.id,
      channel.id,
      "basically a label for a weird set of symptoms reported by diplomats.",
      "sig-1",
      DateTime.add(now, 5, :second)
    )

    create_message!(
      tenant.schema_name,
      sig.id,
      channel.id,
      "pretty much yeah mogged means outdone and humiliated by comparison.",
      "sig-mogged",
      DateTime.add(now, 900, :second)
    )

    create_message!(
      tenant.schema_name,
      dio.id,
      channel.id,
      "sig: so mogged means the same as upstaged?",
      "dio-mogged",
      DateTime.add(now, 905, :second)
    )

    assert {:ok, result} =
             ConstrainedQA.answer_question(
               tenant.subject_name,
               "what did sig and eefer-- talk about today?",
               requester_channel_name: "#!chases",
               generation_provider: Threadr.TestGenerationProvider,
               generation_model: "test-chat"
             )

    assert result.query.retrieval == "paired_actor_messages"
    assert result.query.actor_handles == ["sig"]
    assert result.query.counterpart_actor_handles == ["eefer--"]
    assert Enum.any?(result.citations, &(&1.actor_handle == "sig"))
    assert Enum.any?(result.citations, &(&1.actor_handle == "eefer--"))
    assert result.context =~ "Havana Syndrome"
    refute result.context =~ "mogged"
  end

  test "answers exact-term mention questions with literal retrieval" do
    tenant = create_tenant!("Constrained QA Literal Mention")
    farmr = create_actor!(tenant.schema_name, "farmr")
    leku = create_actor!(tenant.schema_name, "leku")
    channel = create_channel!(tenant.schema_name, "#!chases")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    create_message!(
      tenant.schema_name,
      farmr.id,
      channel.id,
      "why is the number 1488 related to white supremacy?",
      "farmr-1488",
      now
    )

    create_message!(
      tenant.schema_name,
      leku.id,
      channel.id,
      "1488 comes up in nazi numerology all the time.",
      "leku-1488",
      DateTime.add(now, 5, :second)
    )

    assert {:ok, result} =
             ConstrainedQA.answer_question(
               tenant.subject_name,
               "who has mentioned 1488?",
               requester_channel_name: "#!chases",
               generation_provider: Threadr.TestConstraintGenerationProvider,
               generation_model: "test-chat"
             )

    assert result.query.retrieval == "literal_term_messages"
    assert result.query.literal_terms == ["1488"]
    assert Enum.any?(result.citations, &(&1.actor_handle == "farmr"))
    assert Enum.any?(result.citations, &(&1.actor_handle == "leku"))
    assert result.context =~ "1488"
  end

  test "answers literal count-style questions from current-channel messages" do
    tenant = create_tenant!("Constrained QA Literal Count")
    eefer = create_actor!(tenant.schema_name, "eefer--")
    leku = create_actor!(tenant.schema_name, "leku")
    channel = create_channel!(tenant.schema_name, "#!chases")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    create_message!(
      tenant.schema_name,
      eefer.id,
      channel.id,
      "leku: umom",
      "umom-1",
      now
    )

    create_message!(
      tenant.schema_name,
      leku.id,
      channel.id,
      "eefer--: umoms",
      "umom-2",
      DateTime.add(now, 5, :second)
    )

    assert {:ok, result} =
             ConstrainedQA.answer_question(
               tenant.subject_name,
               "how many umoms jokes were there today and from whom?",
               requester_channel_name: "#!chases",
               generation_provider: Threadr.TestConstraintGenerationProvider,
               generation_model: "test-chat"
             )

    assert result.query.retrieval == "literal_term_messages"
    assert result.query.literal_terms == ["umom"]
    assert Enum.any?(result.citations, &(&1.actor_handle == "eefer--"))
    assert Enum.any?(result.citations, &(&1.actor_handle == "leku"))
    assert result.context =~ "umom"
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
