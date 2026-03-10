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

  test "derives actor topical constraints heuristically when routing falls back" do
    tenant = create_tenant!("Constrained QA Actor Preference")
    thanew = create_actor!(tenant.schema_name, "THANEW")
    leku = create_actor!(tenant.schema_name, "leku")
    channel = create_channel!(tenant.schema_name, "#!chases")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    create_message!(
      tenant.schema_name,
      thanew.id,
      channel.id,
      "not a big fan of dnb tbh",
      "thanew-dnb-1",
      now
    )

    create_message!(
      tenant.schema_name,
      thanew.id,
      channel.id,
      "but its good background shit for playing games",
      "thanew-dnb-2",
      DateTime.add(now, 10, :second)
    )

    create_message!(
      tenant.schema_name,
      leku.id,
      channel.id,
      "i like jungle more than dnb",
      "leku-dnb",
      DateTime.add(now, 20, :second)
    )

    assert {:ok, result} =
             ConstrainedQA.answer_question(
               tenant.subject_name,
               "does THANEW like dnb?",
               requester_channel_name: "#!chases",
               generation_provider: Threadr.TestConstraintGenerationProvider,
               generation_model: "test-chat"
             )

    assert result.query.mode == "constrained_qa"
    assert result.query.retrieval == "hybrid_topic_messages"
    assert result.query.actor_handles == ["THANEW"]
    assert result.query.topic_terms == ["dnb"]
    assert result.context =~ "not a big fan of dnb tbh"
    refute result.context =~ "i like jungle more than dnb"
  end

  test "falls back to a broader actor slice when rhetorical topic terms do not match literally" do
    tenant = create_tenant!("Constrained QA Actor Rhetorical")
    thanew = create_actor!(tenant.schema_name, "THANEW")
    other = create_actor!(tenant.schema_name, "leku")
    channel = create_channel!(tenant.schema_name, "#!chases")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    create_message!(
      tenant.schema_name,
      thanew.id,
      channel.id,
      "corporate bootlicker is HR's dream and an employee's worst nightmare",
      "thanew-work-1",
      now
    )

    create_message!(
      tenant.schema_name,
      thanew.id,
      channel.id,
      "nobody is logging this immediately just to prove production",
      "thanew-work-2",
      DateTime.add(now, 15, :second)
    )

    create_message!(
      tenant.schema_name,
      other.id,
      channel.id,
      "this should not leak into the actor slice",
      "leku-noise",
      DateTime.add(now, 30, :second)
    )

    assert {:ok, result} =
             ConstrainedQA.answer_question(
               tenant.subject_name,
               "what disgusting filth did THANEW talk about today? i want all the dirt",
               requester_channel_name: "#!chases",
               generation_provider: Threadr.TestConstraintGenerationProvider,
               generation_model: "test-chat"
             )

    assert result.query.actor_handles == ["THANEW"]
    assert result.query.topic_terms == ["disgusting", "filth", "dirt"]
    assert result.context =~ "corporate bootlicker"
    assert result.context =~ "prove production"
    refute result.context =~ "this should not leak"
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

  test "pair questions can use same-channel topical clusters without direct mentions" do
    tenant = create_tenant!("Constrained QA Topical Pair Cluster")
    leku = create_actor!(tenant.schema_name, "leku")
    bysin = create_actor!(tenant.schema_name, "bysin")
    fysty = create_actor!(tenant.schema_name, "fysty")
    channel = create_channel!(tenant.schema_name, "#!chases")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    create_message!(
      tenant.schema_name,
      leku.id,
      channel.id,
      "AES related-key attacks are interesting, but reduced-round cryptanalysis is not a practical break.",
      "leku-aes-1",
      now
    )

    create_message!(
      tenant.schema_name,
      fysty.id,
      channel.id,
      "i should really start a terrace garden instead",
      "fysty-garden",
      DateTime.add(now, 20, :second)
    )

    create_message!(
      tenant.schema_name,
      bysin.id,
      channel.id,
      "the bigger weakness is usually implementation bugs and cache-timing leakage, not full AES collapse.",
      "bysin-aes-1",
      DateTime.add(now, 35, :second)
    )

    create_message!(
      tenant.schema_name,
      leku.id,
      channel.id,
      "yeah biclique attacks make for good cryptography trivia, but side-channel issues are the real risk.",
      "leku-aes-2",
      DateTime.add(now, 55, :second)
    )

    create_message!(
      tenant.schema_name,
      bysin.id,
      channel.id,
      "exactly, AES itself is sturdy enough and the practical weaknesses show up around key handling and timing.",
      "bysin-aes-2",
      DateTime.add(now, 75, :second)
    )

    assert {:ok, result} =
             ConstrainedQA.answer_question(
               tenant.subject_name,
               "what did leku and bysin talk about today?",
               requester_channel_name: "#!chases",
               generation_provider: Threadr.TestGenerationProvider,
               generation_model: "test-chat"
             )

    assert result.query.retrieval == "topical_pair_messages"
    assert Enum.any?(result.citations, &(&1.actor_handle == "leku"))
    assert Enum.any?(result.citations, &(&1.actor_handle == "bysin"))
    assert result.context =~ "AES"
    assert result.context =~ "cryptography"
    assert result.context =~ "cache-timing"
  end

  test "pair questions fail closed for unrelated same-day solo chatter" do
    tenant = create_tenant!("Constrained QA Pair Fail Closed")
    leku = create_actor!(tenant.schema_name, "leku")
    bysin = create_actor!(tenant.schema_name, "bysin")
    channel = create_channel!(tenant.schema_name, "#!chases")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    create_message!(
      tenant.schema_name,
      leku.id,
      channel.id,
      "my terrace tomatoes are finally doing well.",
      "leku-garden",
      now
    )

    create_message!(
      tenant.schema_name,
      bysin.id,
      channel.id,
      "i need to rotate the tires on my truck this weekend.",
      "bysin-truck",
      DateTime.add(now, 45, :second)
    )

    assert {:error, :not_constrained_question} =
             ConstrainedQA.answer_question(
               tenant.subject_name,
               "what did leku and bysin talk about today?",
               requester_channel_name: "#!chases",
               generation_provider: Threadr.TestGenerationProvider,
               generation_model: "test-chat"
             )
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

  test "answers channel-scoped topical activity questions from older same-day evidence" do
    tenant = create_tenant!("Constrained QA Channel Topic Activity")
    thanew = create_actor!(tenant.schema_name, "THANEW")
    larsinio = create_actor!(tenant.schema_name, "larsinio")
    channel = create_channel!(tenant.schema_name, "#!chases")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    create_message!(
      tenant.schema_name,
      thanew.id,
      channel.id,
      "first up",
      "first-up-1",
      now
    )

    create_message!(
      tenant.schema_name,
      larsinio.id,
      channel.id,
      "says u",
      "first-up-2",
      DateTime.add(now, 60, :second)
    )

    for index <- 1..10 do
      create_message!(
        tenant.schema_name,
        larsinio.id,
        channel.id,
        "later chatter #{index}",
        "later-#{index}",
        DateTime.add(now, 600 + index, :second)
      )
    end

    assert {:ok, result} =
             ConstrainedQA.answer_question(
               tenant.subject_name,
               "who was first up today?",
               requester_channel_name: "#!chases",
               generation_provider: Threadr.TestConstraintGenerationProvider,
               generation_model: "test-chat"
             )

    assert result.query.retrieval == "hybrid_topic_messages"
    assert result.query.topic_terms == ["first", "up"]
    assert result.query.channel_name == "#!chases"
    assert result.context =~ "first up"
    refute result.context =~ "later chatter 10"
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
