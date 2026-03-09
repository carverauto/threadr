defmodule Threadr.TenantData.IngestTest do
  use Threadr.DataCase, async: false

  import Ash.Expr
  require Ash.Query

  alias Threadr.ControlPlane.Service
  alias Threadr.Events.{ChatContextEvent, ChatMessage, Envelope}
  alias Threadr.Messaging.Topology

  alias Threadr.TenantData.{
    Alias,
    AliasObservation,
    Conversation,
    ConversationMembership,
    ContextEvent,
    Graph,
    Ingest,
    MessageLink,
    PendingItem,
    Relationship,
    RelationshipObservation
  }

  test "projects persisted messages into AGE and infers co-mentioned relationships idempotently" do
    tenant = create_tenant!("AGE Graph")
    observed_at = DateTime.utc_now() |> DateTime.truncate(:second)
    external_id = Ecto.UUID.generate()

    envelope =
      Envelope.new(
        ChatMessage.from_map(%{
          platform: "discord",
          channel: "ops",
          actor: "alice",
          body: "Alice mentioned Bob and Carol in incident response planning.",
          mentions: ["bob", "carol"],
          observed_at: observed_at,
          metadata: %{
            "platform_message_id" => external_id,
            "platform_channel_id" => "ops",
            "platform_actor_id" => "discord-user-1",
            "observed_handle" => "alice",
            "observed_display_name" => "Alice Display"
          },
          raw: %{"text" => "Alice mentioned Bob and Carol in incident response planning."}
        }),
        "chat.message",
        Topology.subject_for(:chat_messages, tenant.subject_name),
        %{id: external_id}
      )

    assert {:ok, message} = Ingest.persist_envelope(envelope)

    relationships = fetch_relationships(tenant.schema_name, message.id)

    assert Enum.sort(Enum.map(relationships, & &1.relationship_type)) == [
             "CO_MENTIONED",
             "MENTIONED",
             "MENTIONED"
           ]

    assert Enum.all?(relationships, &(&1.weight == 1))

    co_mentioned =
      Enum.find(relationships, &(&1.relationship_type == "CO_MENTIONED"))

    assert co_mentioned.metadata["source"] == "age.co_mentions"

    observations = fetch_relationship_observations(tenant.schema_name, message.id)

    assert length(observations) == 3

    graph_name = Graph.graph_name(tenant.schema_name)

    assert vertex_count(graph_name, "Actor") == 3
    assert vertex_count(graph_name, "Channel") == 1
    assert vertex_count(graph_name, "Message") == 1
    assert edge_count(graph_name, "SENT") == 1
    assert edge_count(graph_name, "IN_CHANNEL") == 1
    assert edge_count(graph_name, "MENTIONS") == 2
    assert edge_count(graph_name, "RELATES_TO") == 3

    assert {:ok, same_message} = Ingest.persist_envelope(envelope)
    assert same_message.id == message.id

    relationships_after_replay = fetch_relationships(tenant.schema_name, message.id)
    observations_after_replay = fetch_relationship_observations(tenant.schema_name, message.id)
    alias_observations = fetch_alias_observations(tenant.schema_name, message.id)
    aliases = fetch_aliases(tenant.schema_name)

    assert length(relationships_after_replay) == 3
    assert Enum.all?(relationships_after_replay, &(&1.weight == 1))
    assert length(observations_after_replay) == 3
    assert length(alias_observations) == 2

    assert Enum.sort(Enum.map(alias_observations, & &1.source_event_type)) == [
             "message",
             "message"
           ]

    assert Enum.sort(Enum.map(aliases, & &1.alias_kind)) == ["display_name", "handle"]
    assert message.metadata["platform_actor_id"] == "discord-user-1"
    assert message.metadata["observed_display_name"] == "Alice Display"
    assert edge_count(graph_name, "MENTIONS") == 2
    assert edge_count(graph_name, "RELATES_TO") == 3
  end

  test "persists chat context events and links them to source messages when available" do
    tenant = create_tenant!("Context Events")
    observed_at = DateTime.utc_now() |> DateTime.truncate(:second)
    external_id = Ecto.UUID.generate()

    message_envelope =
      Envelope.new(
        ChatMessage.from_map(%{
          platform: "discord",
          channel: "ops",
          actor: "alice",
          body: "Alice mentioned Bob in incident response planning.",
          observed_at: observed_at,
          metadata: %{
            "platform_message_id" => external_id,
            "platform_channel_id" => "ops",
            "observed_handle" => "alice",
            "observed_display_name" => "Alice Display"
          },
          raw: %{"text" => "Alice mentioned Bob in incident response planning."}
        }),
        "chat.message",
        Topology.subject_for(:chat_messages, tenant.subject_name),
        %{id: external_id}
      )

    assert {:ok, message} = Ingest.persist_envelope(message_envelope)

    context_envelope =
      Envelope.new(
        Threadr.Events.ChatContextEvent.from_map(%{
          platform: "discord",
          event_type: "message_edit",
          channel: "ops",
          actor: "alice",
          observed_at: DateTime.add(observed_at, 5, :second),
          metadata: %{
            "source_message_external_id" => external_id,
            "observed_handle" => "alice",
            "observed_display_name" => "Alice Display"
          },
          raw: %{"content" => "Alice mentioned Bob in incident response planning. (edited)"}
        }),
        "chat.context",
        Topology.subject_for(:chat_messages, tenant.subject_name),
        %{id: "#{external_id}:edit"}
      )

    assert {:ok, context_event} = Ingest.persist_envelope(context_envelope)
    assert context_event.event_type == "message_edit"
    assert context_event.source_message_id == message.id
    assert context_event.metadata["source_message_external_id"] == external_id

    persisted_events = fetch_context_events(tenant.schema_name)
    assert length(persisted_events) == 1
  end

  test "persists alias observations for nick change context events" do
    tenant = create_tenant!("Nick Change Context")
    observed_at = DateTime.utc_now() |> DateTime.truncate(:second)

    context_envelope =
      Envelope.new(
        ChatContextEvent.from_map(%{
          platform: "irc",
          event_type: "nick_change",
          actor: "alice",
          observed_at: observed_at,
          metadata: %{
            "observed_handle" => "alice",
            "observed_display_name" => "alice",
            "new_handle" => "alice_",
            "irc_user" => "alice",
            "irc_host" => "workstation.example.org"
          },
          raw: %{
            "nick" => "alice",
            "new_nick" => "alice_",
            "user" => "alice",
            "host" => "workstation.example.org"
          }
        }),
        "chat.context",
        Topology.subject_for(:chat_messages, tenant.subject_name),
        %{id: "irc:alice:alice_:nick"}
      )

    assert {:ok, context_event} = Ingest.persist_envelope(context_envelope)

    alias_observations =
      fetch_alias_observations_for_context_event(tenant.schema_name, context_event.id)

    assert length(alias_observations) == 3

    assert Enum.sort(Enum.map(alias_observations, & &1.source_event_type)) == [
             "nick_change",
             "nick_change",
             "nick_change"
           ]

    assert Enum.all?(alias_observations, &(&1.source_context_event_id == context_event.id))
    assert Enum.all?(alias_observations, &is_nil(&1.source_message_id))
    assert Enum.all?(alias_observations, &is_nil(&1.channel_id))

    aliases = fetch_aliases(tenant.schema_name)

    assert Enum.sort(Enum.map(aliases, &{&1.alias_kind, &1.value})) == [
             {"display_name", "alice"},
             {"handle", "alice"},
             {"handle", "alice_"}
           ]
  end

  test "preserves prior authorship across IRC nick changes without unsafe merges" do
    tenant = create_tenant!("Nick Change Authorship")
    observed_at = DateTime.utc_now() |> DateTime.truncate(:second)

    original_envelope =
      Envelope.new(
        ChatMessage.from_map(%{
          platform: "irc",
          channel: "#ops",
          actor: "alice",
          body: "starting backup validation",
          observed_at: observed_at,
          metadata: %{
            "platform_message_id" => "irc-msg-1",
            "observed_handle" => "alice"
          },
          raw: %{"text" => "starting backup validation"}
        }),
        "chat.message",
        Topology.subject_for(:chat_messages, tenant.subject_name),
        %{id: "irc-msg-1"}
      )

    assert {:ok, original_message} = Ingest.persist_envelope(original_envelope)

    nick_change_envelope =
      Envelope.new(
        ChatContextEvent.from_map(%{
          platform: "irc",
          event_type: "nick_change",
          actor: "alice",
          observed_at: DateTime.add(observed_at, 10, :second),
          metadata: %{
            "observed_handle" => "alice",
            "observed_display_name" => "alice",
            "new_handle" => "alice_",
            "irc_user" => "alice",
            "irc_host" => "workstation.example.org"
          },
          raw: %{
            "nick" => "alice",
            "new_nick" => "alice_",
            "user" => "alice",
            "host" => "workstation.example.org"
          }
        }),
        "chat.context",
        Topology.subject_for(:chat_messages, tenant.subject_name),
        %{id: "irc:alice:alice_:nick"}
      )

    assert {:ok, context_event} = Ingest.persist_envelope(nick_change_envelope)

    renamed_envelope =
      Envelope.new(
        ChatMessage.from_map(%{
          platform: "irc",
          channel: "#ops",
          actor: "alice_",
          body: "backup validation finished",
          observed_at: DateTime.add(observed_at, 20, :second),
          metadata: %{
            "platform_message_id" => "irc-msg-2",
            "observed_handle" => "alice_"
          },
          raw: %{"text" => "backup validation finished"}
        }),
        "chat.message",
        Topology.subject_for(:chat_messages, tenant.subject_name),
        %{id: "irc-msg-2"}
      )

    assert {:ok, renamed_message} = Ingest.persist_envelope(renamed_envelope)

    actors = fetch_actors(tenant.schema_name)

    alias_observations =
      fetch_alias_observations_for_context_event(tenant.schema_name, context_event.id)

    assert Enum.sort(Enum.map(actors, & &1.handle)) == ["alice", "alice_"]
    refute original_message.actor_id == renamed_message.actor_id
    assert length(alias_observations) == 3

    assert fetch_message!(tenant.schema_name, original_message.id).actor_id ==
             original_message.actor_id

    assert fetch_message!(tenant.schema_name, renamed_message.id).actor_id ==
             renamed_message.actor_id
  end

  test "persists alias observations for presence context events without channels" do
    tenant = create_tenant!("Presence Context")
    observed_at = DateTime.utc_now() |> DateTime.truncate(:second)

    context_envelope =
      Envelope.new(
        ChatContextEvent.from_map(%{
          platform: "discord",
          event_type: "presence_snapshot",
          actor: "Alice Display",
          observed_at: observed_at,
          metadata: %{
            "platform_guild_id" => "guild-1",
            "platform_actor_id" => "discord-user-1",
            "observed_handle" => "alice",
            "observed_display_name" => "Alice Display",
            "presence_state" => %{"status" => "online"}
          },
          raw: %{"status" => "online"}
        }),
        "chat.context",
        Topology.subject_for(:chat_messages, tenant.subject_name),
        %{id: "guild-1:presence_snapshot:discord-user-1:online"}
      )

    assert {:ok, context_event} = Ingest.persist_envelope(context_envelope)

    alias_observations =
      fetch_alias_observations_for_context_event(tenant.schema_name, context_event.id)

    assert length(alias_observations) == 2

    assert Enum.sort(Enum.map(alias_observations, & &1.source_event_type)) == [
             "presence",
             "presence"
           ]

    assert Enum.all?(alias_observations, &(&1.platform_account_id == "discord-user-1"))
    assert Enum.all?(alias_observations, &is_nil(&1.channel_id))
    assert Enum.all?(alias_observations, &is_nil(&1.source_message_id))

    aliases = fetch_aliases(tenant.schema_name)
    assert Enum.sort(Enum.map(aliases, & &1.alias_kind)) == ["display_name", "handle"]
  end

  test "persists roster presence context events as presence evidence without authorship" do
    tenant = create_tenant!("IRC Roster Presence")
    observed_at = DateTime.utc_now() |> DateTime.truncate(:second)

    context_envelope =
      Envelope.new(
        ChatContextEvent.from_map(%{
          platform: "irc",
          event_type: "roster_presence",
          channel: "#intel",
          actor: "alice",
          observed_at: observed_at,
          metadata: %{
            "platform_channel_id" => "#intel",
            "conversation_external_id" => "#intel",
            "observed_handle" => "alice",
            "observed_display_name" => "alice",
            "irc_membership_prefixes" => ["@"],
            "irc_membership_flags" => ["op"],
            "presence_source" => "names_reply",
            "roster_batch_id" => "batch-1"
          },
          raw: %{
            "channel" => "#intel",
            "nick" => "alice",
            "prefixes" => ["@"],
            "flags" => ["op"]
          }
        }),
        "chat.context",
        Topology.subject_for(:chat_messages, tenant.subject_name),
        %{id: "irc:#intel:batch-1:alice:roster"}
      )

    assert {:ok, context_event} = Ingest.persist_envelope(context_envelope)

    alias_observations =
      fetch_alias_observations_for_context_event(tenant.schema_name, context_event.id)

    assert length(alias_observations) == 2
    assert Enum.all?(alias_observations, &(&1.source_event_type == "presence"))
    assert Enum.all?(alias_observations, &is_nil(&1.source_message_id))
    assert Enum.all?(alias_observations, & &1.channel_id)

    assert [%{handle: "alice"}] = fetch_actors(tenant.schema_name)
    assert [%{event_type: "roster_presence"}] = fetch_context_events(tenant.schema_name)
    assert [] = Relationship |> Ash.read!(tenant: tenant.schema_name)
  end

  test "persists message links for explicit reply messages" do
    tenant = create_tenant!("Message Links")
    observed_at = DateTime.utc_now() |> DateTime.truncate(:second)

    question_envelope =
      Envelope.new(
        ChatMessage.from_map(%{
          platform: "discord",
          channel: "ops",
          actor: "bob",
          body: "Did the deploy finish on web-2?",
          observed_at: observed_at,
          metadata: %{
            "platform_message_id" => "msg-question",
            "platform_channel_id" => "ops",
            "conversation_external_id" => "ops"
          },
          raw: %{"text" => "Did the deploy finish on web-2?"}
        }),
        "chat.message",
        Topology.subject_for(:chat_messages, tenant.subject_name),
        %{id: "msg-question"}
      )

    assert {:ok, question} = Ingest.persist_envelope(question_envelope)

    answer_envelope =
      Envelope.new(
        ChatMessage.from_map(%{
          platform: "discord",
          channel: "ops",
          actor: "alice",
          body: "Yes, it finished.",
          observed_at: DateTime.add(observed_at, 5, :second),
          metadata: %{
            "platform_message_id" => "msg-answer",
            "platform_channel_id" => "ops",
            "reply_to_external_id" => "msg-question",
            "conversation_external_id" => "ops"
          },
          raw: %{"text" => "Yes, it finished."}
        }),
        "chat.message",
        Topology.subject_for(:chat_messages, tenant.subject_name),
        %{id: "msg-answer"}
      )

    assert {:ok, answer} = Ingest.persist_envelope(answer_envelope)

    assert {:ok, link} =
             MessageLink
             |> Ash.Query.filter(expr(source_message_id == ^answer.id))
             |> Ash.read_one(tenant: tenant.schema_name)

    assert link.target_message_id == question.id
    assert link.link_type == "replies_to"
    assert link.score >= 0.7

    assert Enum.any?(
             link.evidence,
             &(&1["kind"] == "explicit_reply" or &1.kind == "explicit_reply")
           )

    [conversation] = Conversation |> Ash.read!(tenant: tenant.schema_name)
    assert conversation.starter_message_id == question.id
    assert conversation.most_recent_message_id == answer.id
    assert conversation.lifecycle_state in ["active", "revived"]

    memberships =
      ConversationMembership
      |> Ash.Query.filter(expr(conversation_id == ^conversation.id))
      |> Ash.read!(tenant: tenant.schema_name)

    assert Enum.sort(Enum.map(memberships, & &1.member_kind)) == [
             "actor",
             "actor",
             "message",
             "message"
           ]
  end

  test "opens and resolves pending items through normal ingest" do
    tenant = create_tenant!("Pending Items")
    observed_at = DateTime.utc_now() |> DateTime.truncate(:second)

    request_envelope =
      Envelope.new(
        ChatMessage.from_map(%{
          platform: "discord",
          channel: "ops",
          actor: "bob",
          body: "Can someone validate web-7?",
          observed_at: observed_at,
          metadata: %{
            "platform_message_id" => "msg-request",
            "platform_channel_id" => "ops",
            "conversation_external_id" => "ops",
            "dialogue_act" => %{"label" => "request", "confidence" => 0.9}
          },
          raw: %{"text" => "Can someone validate web-7?"}
        }),
        "chat.message",
        Topology.subject_for(:chat_messages, tenant.subject_name),
        %{id: "msg-request"}
      )

    assert {:ok, request_message} = Ingest.persist_envelope(request_envelope)

    assert {:ok, pending_item} =
             PendingItem
             |> Ash.Query.filter(expr(opener_message_id == ^request_message.id))
             |> Ash.read_one(tenant: tenant.schema_name)

    assert pending_item.status == "open"

    completion_envelope =
      Envelope.new(
        ChatMessage.from_map(%{
          platform: "discord",
          channel: "ops",
          actor: "alice",
          body: "I validated web-7 successfully.",
          observed_at: DateTime.add(observed_at, 5, :second),
          metadata: %{
            "platform_message_id" => "msg-complete",
            "platform_channel_id" => "ops",
            "reply_to_external_id" => "msg-request",
            "conversation_external_id" => "ops",
            "dialogue_act" => %{"label" => "status_update", "confidence" => 0.85}
          },
          raw: %{"text" => "I validated web-7 successfully."}
        }),
        "chat.message",
        Topology.subject_for(:chat_messages, tenant.subject_name),
        %{id: "msg-complete"}
      )

    assert {:ok, completion_message} = Ingest.persist_envelope(completion_envelope)

    assert {:ok, resolved_item} =
             PendingItem
             |> Ash.Query.filter(expr(opener_message_id == ^request_message.id))
             |> Ash.read_one(tenant: tenant.schema_name)

    assert resolved_item.status == "completed"
    assert resolved_item.resolver_message_id == completion_message.id

    [conversation] = Conversation |> Ash.read!(tenant: tenant.schema_name)
    assert conversation.open_pending_item_count == 0
  end

  defp create_tenant!(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, tenant} =
      Service.create_tenant(%{
        name: "#{prefix} #{suffix}",
        subject_name: "tenant-age-#{suffix}"
      })

    tenant
  end

  defp fetch_relationships(tenant_schema, message_id) do
    Relationship
    |> Ash.Query.filter(expr(source_message_id == ^message_id))
    |> Ash.read!(tenant: tenant_schema)
  end

  defp fetch_relationship_observations(tenant_schema, message_id) do
    RelationshipObservation
    |> Ash.Query.filter(expr(source_message_id == ^message_id))
    |> Ash.read!(tenant: tenant_schema)
  end

  defp fetch_alias_observations(tenant_schema, message_id) do
    AliasObservation
    |> Ash.Query.filter(expr(source_message_id == ^message_id))
    |> Ash.read!(tenant: tenant_schema)
  end

  defp fetch_alias_observations_for_context_event(tenant_schema, context_event_id) do
    AliasObservation
    |> Ash.Query.filter(expr(source_context_event_id == ^context_event_id))
    |> Ash.read!(tenant: tenant_schema)
  end

  defp fetch_aliases(tenant_schema) do
    Alias
    |> Ash.read!(tenant: tenant_schema)
  end

  defp fetch_context_events(tenant_schema) do
    ContextEvent
    |> Ash.read!(tenant: tenant_schema)
  end

  defp fetch_actors(tenant_schema) do
    Threadr.TenantData.Actor
    |> Ash.read!(tenant: tenant_schema)
  end

  defp fetch_message!(tenant_schema, message_id) do
    Threadr.TenantData.Message
    |> Ash.Query.filter(expr(id == ^message_id))
    |> Ash.read_one!(tenant: tenant_schema)
  end

  defp vertex_count(graph_name, label_name) do
    {:ok, %{rows: [[count]]}} =
      Repo.query("SELECT count(*)::int FROM #{qualified_table(graph_name, label_name)}")

    count
  end

  defp edge_count(graph_name, label_name) do
    {:ok, %{rows: [[count]]}} =
      Repo.query("SELECT count(*)::int FROM #{qualified_table(graph_name, label_name)}")

    count
  end

  defp qualified_table(graph_name, label_name) do
    "#{quote_ident(graph_name)}.#{quote_ident(label_name)}"
  end

  defp quote_ident(value) do
    escaped = String.replace(to_string(value), "\"", "\"\"")
    ~s("#{escaped}")
  end
end
