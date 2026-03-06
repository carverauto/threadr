defmodule Mix.Tasks.Threadr.Seed.Demo do
  @shortdoc "Seeds a tenant with demo chat history and embeddings for QA"

  use Mix.Task

  alias Threadr.ControlPlane
  alias Threadr.Events.{ChatMessage, Envelope}
  alias Threadr.ML.Embeddings
  alias Threadr.Messaging.Topology
  alias Threadr.Repo
  alias Threadr.TenantData.{Graph, Ingest}

  @switches [tenant_subject: :string]
  @default_tenant_subject "carverauto"

  @demo_messages [
    %{
      external_id: "demo-ir-001",
      platform: "discord",
      channel: "incident-war-room",
      actor: "alice",
      mentions: ["bob", "carol"],
      body:
        "Bob, your mailbox trace is still incomplete. Before we brief Carol on March 1, I need to know whether the finance clicks and the OAuth approvals are actually connected or just happening in parallel.",
      observed_at: ~U[2026-03-01 13:05:00Z]
    },
    %{
      external_id: "demo-ir-002",
      platform: "irc",
      channel: "#soc",
      actor: "bob",
      mentions: ["alice"],
      body:
        "Alice, I only have partial forwarding-rule data right now. I do not want you treating my first pass as final until I reconcile the mailbox logs with the Okta grant history.",
      observed_at: ~U[2026-03-01 13:12:00Z]
    },
    %{
      external_id: "demo-ir-003",
      platform: "discord",
      channel: "exec-briefing",
      actor: "carol",
      mentions: ["alice", "bob"],
      body:
        "At today's March 1 briefing Alice described Bob's trace as promising but not yet complete. Their conversation is still about whether Bob's mailbox work is strong enough to anchor the timeline.",
      observed_at: ~U[2026-03-01 13:20:00Z]
    },
    %{
      external_id: "demo-ir-004",
      platform: "discord",
      channel: "incident-war-room",
      actor: "alice",
      mentions: ["bob", "dana"],
      body:
        "Bob, on March 2 I still need you to prove whether Dana was the first phishing recipient. Once that is settled, I can start trusting your timeline enough to use it in the exec notes.",
      observed_at: ~U[2026-03-02 15:02:00Z]
    },
    %{
      external_id: "demo-ir-005",
      platform: "irc",
      channel: "#soc",
      actor: "bob",
      mentions: ["alice", "dana"],
      body:
        "Alice, Dana was the first recipient. I matched the phishing click to the mailbox forwarding rule and the grant event. This is the first point where my mailbox trace and the OAuth data line up cleanly.",
      observed_at: ~U[2026-03-02 15:08:00Z]
    },
    %{
      external_id: "demo-ir-006",
      platform: "discord",
      channel: "incident-war-room",
      actor: "alice",
      mentions: ["bob", "carol"],
      body:
        "Carol, Bob's evidence is getting stronger. I am not ready to call him the source of truth yet, but by the end of March 2 I trust his first-recipient work enough to build the draft timeline around it.",
      observed_at: ~U[2026-03-02 15:16:00Z]
    },
    %{
      external_id: "demo-ir-007",
      platform: "discord",
      channel: "incident-war-room",
      actor: "alice",
      mentions: ["bob"],
      body:
        "Bob, compare the finance mailbox traces with the OAuth grants before the 09:30 briefing. I need our timeline clear before Carol asks what changed overnight.",
      observed_at: ~U[2026-03-03 14:05:00Z]
    },
    %{
      external_id: "demo-ir-008",
      platform: "discord",
      channel: "incident-war-room",
      actor: "bob",
      mentions: ["alice", "dana"],
      body:
        "Alice, the first phishing recipient was Dana in finance. I am tracing the mailbox forwarding rule history now and will post the exact timestamps when I have them.",
      observed_at: ~U[2026-03-03 14:08:00Z]
    },
    %{
      external_id: "demo-ir-009",
      platform: "discord",
      channel: "incident-war-room",
      actor: "carol",
      mentions: ["alice", "bob"],
      body:
        "Alice and Bob have been pairing on the timeline since 07:00. Their split is simple: Bob owns mailbox tracing and OAuth grant review while Alice keeps the incident narrative aligned for the exec briefing.",
      observed_at: ~U[2026-03-03 14:11:00Z]
    },
    %{
      external_id: "demo-ir-010",
      platform: "discord",
      channel: "incident-war-room",
      actor: "alice",
      mentions: ["bob", "carol"],
      body:
        "Bob told me the malicious OAuth app is Calendar Sync Helper and that only three users approved it. Carol, treat that as the current working scope until Bob closes the grant audit.",
      observed_at: ~U[2026-03-03 14:14:00Z]
    },
    %{
      external_id: "demo-ir-011",
      platform: "irc",
      channel: "#soc",
      actor: "bob",
      mentions: ["alice"],
      body:
        "Alice asked me to focus on payroll access next because she wants to know whether anything beyond the drive index was touched before Tuesday's finance review.",
      observed_at: ~U[2026-03-03 14:17:00Z]
    },
    %{
      external_id: "demo-ir-012",
      platform: "irc",
      channel: "#soc",
      actor: "dana",
      mentions: ["alice", "bob"],
      body:
        "Bob walked Alice and me through the mailbox rule history. We agreed the forwarding rule on Dana's mailbox appeared eleven minutes after the phishing click, not before.",
      observed_at: ~U[2026-03-03 14:22:00Z]
    },
    %{
      external_id: "demo-ir-013",
      platform: "discord",
      channel: "exec-briefing",
      actor: "carol",
      mentions: ["erin", "alice", "bob"],
      body:
        "Erin, Alice knows Bob is our source for mailbox tracing, OAuth grant review, and first-recipient confirmation. They are briefing together at 14:00 once Bob closes the payroll checks.",
      observed_at: ~U[2026-03-03 14:25:00Z]
    },
    %{
      external_id: "demo-ir-014",
      platform: "discord",
      channel: "incident-war-room",
      actor: "alice",
      mentions: ["bob", "frank"],
      body:
        "Bob just told me no payroll files were downloaded. He says the attacker only queried the payroll shared drive index, and Frank's audit logs line up with that so far.",
      observed_at: ~U[2026-03-03 14:30:00Z]
    },
    %{
      external_id: "demo-ir-015",
      platform: "irc",
      channel: "#threat-intel",
      actor: "erin",
      mentions: ["alice", "bob", "frank"],
      body:
        "During yesterday's 16:00 review Alice and Bob shifted from phishing triage to whether Bob's mailbox trace and Frank's cloud logs tell the same story about payroll access.",
      observed_at: ~U[2026-03-04 16:05:00Z]
    },
    %{
      external_id: "demo-ir-016",
      platform: "discord",
      channel: "incident-war-room",
      actor: "alice",
      mentions: ["bob", "frank"],
      body:
        "By March 4 I am leaning on Bob's timeline instead of cross-checking every step myself. Frank, I need you validating Bob's payroll-access read because Alice and Bob are now presenting a single narrative to leadership.",
      observed_at: ~U[2026-03-04 16:12:00Z]
    },
    %{
      external_id: "demo-ir-017",
      platform: "discord",
      channel: "incident-war-room",
      actor: "bob",
      mentions: ["alice", "frank", "carol"],
      body:
        "Alice asked who I coordinated with overnight. I worked with Frank on the Okta session resets and with Carol on the exec notes, then I sent Alice the updated mailbox trace summary this morning.",
      observed_at: ~U[2026-03-05 14:05:00Z]
    },
    %{
      external_id: "demo-ir-018",
      platform: "irc",
      channel: "#soc",
      actor: "frank",
      mentions: ["alice", "bob"],
      body:
        "Alice and Bob spent the March 5 09:00 to 10:00 window talking about payroll access, OAuth grants, and whether the attacker ever reached production clusters. My audit notes match Bob's timeline.",
      observed_at: ~U[2026-03-05 14:12:00Z]
    },
    %{
      external_id: "demo-ir-019",
      platform: "discord",
      channel: "exec-briefing",
      actor: "carol",
      mentions: ["alice", "bob"],
      body:
        "For the final briefing, Alice's current view of Bob is that he is the source for first recipient, OAuth app name, payroll query evidence, and overnight mailbox trace updates. Most of their recent conversation has focused on payroll access and timeline integrity.",
      observed_at: ~U[2026-03-05 14:20:00Z]
    },
    %{
      external_id: "demo-ir-020",
      platform: "discord",
      channel: "exec-briefing",
      actor: "carol",
      mentions: ["alice", "bob", "erin"],
      body:
        "Compared with March 1, Alice's view of Bob changed materially this week. She moved from treating Bob's mailbox trace as incomplete to treating Bob as the source of truth for recipient order, OAuth scope, payroll evidence, and overnight timeline updates.",
      observed_at: ~U[2026-03-06 15:00:00Z]
    },
    %{
      external_id: "demo-ir-021",
      platform: "irc",
      channel: "#threat-intel",
      actor: "erin",
      mentions: ["alice", "bob"],
      body:
        "The relationship drift is obvious in the week view: on March 1 Alice challenged Bob's evidence, on March 3 they paired on the timeline, and by March 6 Alice was repeating Bob's conclusions directly in leadership updates.",
      observed_at: ~U[2026-03-06 15:08:00Z]
    },
    %{
      external_id: "demo-ir-022",
      platform: "discord",
      channel: "incident-war-room",
      actor: "alice",
      mentions: ["bob", "carol"],
      body:
        "For next week's recovery planning, Bob is staying attached to my workstream. Earlier this week I was still validating his trace line by line; now I want Bob in every review where we discuss payroll access, mailbox evidence, or timeline integrity.",
      observed_at: ~U[2026-03-06 15:16:00Z]
    }
  ]

  @impl true
  def run(args) do
    {opts, _argv, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    tenant_subject = Keyword.get(opts, :tenant_subject, @default_tenant_subject)

    Logger.configure(level: :info)
    Mix.Task.run("app.start")

    {:ok, tenant} =
      ControlPlane.get_tenant_by_subject_name(tenant_subject, context: %{system: true})

    reset_demo_data!(tenant)

    messages =
      @demo_messages
      |> Enum.map(&persist_message!(&1, tenant))

    embedded =
      messages
      |> Enum.map(&embed_message!(&1, tenant))
      |> length()

    Mix.shell().info("Threadr demo seed complete")
    Mix.shell().info("tenant_subject: #{tenant.subject_name}")
    Mix.shell().info("tenant_schema: #{tenant.schema_name}")
    Mix.shell().info("messages_seeded: #{length(messages)}")
    Mix.shell().info("embeddings_persisted: #{embedded}")
    Mix.shell().info("Try these questions in the QA workspace:")
    Mix.shell().info("  - What does Alice know about Bob?")
    Mix.shell().info("  - How did Alice's view of Bob change this week?")
    Mix.shell().info("  - What changed between Alice and Bob from March 1 to March 5?")
    Mix.shell().info("  - What were Alice and Bob talking about on March 5?")
    Mix.shell().info("  - Who does Bob coordinate with?")
  end

  defp reset_demo_data!(tenant) do
    tenant.schema_name
    |> delete_existing_demo_rows!()

    tenant.schema_name
    |> drop_existing_graph!()
  end

  defp delete_existing_demo_rows!(tenant_schema) do
    for table <- [
          "message_embeddings",
          "message_mentions",
          "relationship_observations",
          "relationships",
          "messages",
          "channels",
          "actors"
        ] do
      Repo.query!("DELETE FROM #{qualified_table(tenant_schema, table)}", [])
    end
  end

  defp drop_existing_graph!(tenant_schema) do
    graph_name = Graph.graph_name(tenant_schema)

    Repo.query!(
      """
      SELECT ag_catalog.drop_graph($1, true)
      WHERE EXISTS (SELECT 1 FROM ag_catalog.ag_graph WHERE name = $1)
      """,
      [graph_name]
    )
  end

  defp qualified_table(schema, table) do
    "#{quote_ident(schema)}.#{quote_ident(table)}"
  end

  defp quote_ident(value) do
    escaped = String.replace(value, "\"", "\"\"")
    ~s("#{escaped}")
  end

  defp persist_message!(attrs, tenant) do
    envelope =
      Envelope.new(
        ChatMessage.from_map(%{
          platform: attrs.platform,
          channel: attrs.channel,
          actor: attrs.actor,
          body: attrs.body,
          mentions: attrs.mentions,
          observed_at: attrs.observed_at,
          raw: %{"body" => attrs.body, "demo" => true}
        }),
        "chat.message",
        Topology.subject_for(:chat_messages, tenant.subject_name),
        %{id: attrs.external_id}
      )

    case Ingest.persist_envelope(envelope) do
      {:ok, message} ->
        message

      {:error, reason} ->
        raise "failed to persist demo message #{attrs.external_id}: #{inspect(reason)}"
    end
  end

  defp embed_message!(message, tenant) do
    case Embeddings.generate_for_message(
           message,
           tenant.subject_name,
           publisher: Threadr.ML.Embeddings.InlinePublisher
         ) do
      {:ok, envelope} ->
        envelope

      {:error, reason} ->
        raise "failed to embed demo message #{message.external_id || message.id}: #{inspect(reason)}"
    end
  end
end
