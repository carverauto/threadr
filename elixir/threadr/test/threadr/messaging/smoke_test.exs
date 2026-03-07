defmodule Threadr.Messaging.SmokeTest do
  use ExUnit.Case, async: false

  import Ash.Expr
  require Ash.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Gnat.Jetstream.API.Consumer
  alias Threadr.Events
  alias Threadr.Events.{ChatMessage, Envelope}
  alias Threadr.Messaging.Publisher
  alias Threadr.Messaging.Topology
  alias Threadr.Messaging.Smoke
  alias Threadr.TenantData.{CommandExecution, MessageEmbedding}

  @integration_env "THREADR_RUN_INTEGRATION"
  @integration_enabled System.get_env(@integration_env) in ~w(true 1 TRUE)

  setup_all do
    unless @integration_enabled do
      {:skip, "set #{@integration_env}=true to run local CNPG/NATS integration tests"}
    else
      owner = Sandbox.start_owner!(Threadr.Repo, shared: true)
      on_exit(fn -> Sandbox.stop_owner(owner) end)

      Mix.Task.reenable("threadr.nats.setup")
      Mix.Task.run("threadr.nats.setup")

      suffix = System.unique_integer([:positive])
      tenant_subject_name = "threadr-integration-test-#{suffix}"
      tenant_name = "Threadr Integration Test #{suffix}"
      consumer_name = "THREADR_TEST_#{System.unique_integer([:positive])}"
      previous_config = Application.fetch_env!(:threadr, Threadr.Messaging.Topology)
      updated_config = Keyword.put(previous_config, :consumer_name, consumer_name)
      Application.put_env(:threadr, Threadr.Messaging.Topology, updated_config)

      on_exit(fn ->
        Application.put_env(:threadr, Threadr.Messaging.Topology, previous_config)
        :ok = Consumer.delete(Topology.connection_name(), Topology.stream_name(), consumer_name)
      end)

      create_test_consumer!(consumer_name, tenant_subject_name)
      {:ok, _pid} = start_supervised(Threadr.Messaging.Pipeline)

      {:ok,
       consumer_name: consumer_name,
       tenant_subject_name: tenant_subject_name,
       tenant_name: tenant_name}
    end
  end

  test "publishes a tenant-scoped message and persists the graph through Broadway", %{
    tenant_subject_name: tenant_subject_name,
    tenant_name: tenant_name
  } do
    report =
      Smoke.run(
        tenant_name: tenant_name,
        tenant_subject_name: tenant_subject_name,
        actor: "integration-bot",
        mentions: ["alpha", "beta"]
      )

    assert report.tenant_subject_name == tenant_subject_name
    assert report.tenant_schema =~ "tenant_threadr_integration_test_"
    assert report.elapsed_ms <= 5_000
    assert report.body == "threadr smoke message @alpha @beta"
    assert report.result.message.external_id == report.external_id
    assert report.result.message.body == report.body
    assert report.result.mention_count == 2
    assert report.result.relationship_count == 2
  end

  test "duplicate delivery does not increment relationship weights twice", %{
    tenant_subject_name: tenant_subject_name,
    tenant_name: tenant_name
  } do
    external_id = Ecto.UUID.generate()

    report =
      Smoke.run(
        tenant_name: tenant_name,
        tenant_subject_name: tenant_subject_name,
        actor: "idempotency-bot",
        mentions: ["gamma", "delta"],
        external_id: external_id
      )

    assert Enum.all?(report.result.relationships, &(&1.weight == 1))

    envelope =
      Envelope.new(
        ChatMessage.from_map(%{
          platform: "discord",
          channel: "ops",
          actor: "idempotency-bot",
          body: report.body,
          mentions: ["gamma", "delta"],
          observed_at: report.result.message.observed_at,
          raw: %{"text" => report.body}
        }),
        "chat.message",
        Topology.subject_for(:chat_messages, tenant_subject_name),
        %{id: external_id}
      )

    :ok = Publisher.publish(envelope)
    Process.sleep(2_500)

    graph = Smoke.fetch_graph!(report.tenant_schema, external_id)

    assert graph.message.id == report.result.message.id
    assert graph.mention_count == 2
    assert graph.relationship_count == 2
    assert Enum.all?(graph.relationships, &(&1.weight == 1))
  end

  test "processing results persist message embeddings for tenant messages", %{
    tenant_subject_name: tenant_subject_name,
    tenant_name: tenant_name
  } do
    report =
      Smoke.run(
        tenant_name: tenant_name,
        tenant_subject_name: tenant_subject_name,
        actor: "embedding-bot",
        mentions: []
      )

    envelope =
      Events.build_processing_result(
        %{
          pipeline: "embeddings",
          status: "completed",
          completed_at: DateTime.utc_now(),
          message_id: report.external_id,
          payload: %{
            "model" => "test-embedding-model",
            "embedding" => [0.1, 0.2, 0.3],
            "provider" => "integration"
          },
          metrics: %{"latency_ms" => 12}
        },
        tenant_subject_name
      )

    :ok = Publisher.publish(envelope)

    embedding =
      await_message_embedding!(
        report.tenant_schema,
        report.result.message.id,
        "test-embedding-model"
      )

    assert embedding.dimensions == 3
    assert embedding.message_id == report.result.message.id
    assert embedding.metadata["pipeline"] == "embeddings"
    assert embedding.metadata["payload"]["provider"] == "integration"
  end

  test "ingest commands are handled on the tenant-scoped command subject", %{
    consumer_name: consumer_name,
    tenant_subject_name: tenant_subject_name,
    tenant_name: tenant_name
  } do
    _report =
      Smoke.run(
        tenant_name: tenant_name,
        tenant_subject_name: tenant_subject_name,
        actor: "command-anchor",
        mentions: []
      )

    envelope =
      Events.build_ingest_command(
        %{
          platform: "discord",
          command: "backfill",
          issued_at: DateTime.utc_now(),
          args: %{"channel" => "ops"}
        },
        tenant_subject_name
      )

    :ok = Publisher.publish(envelope)

    command_execution =
      await_command_execution!(tenant_subject_name, envelope.id, "backfill")

    after_info = fetch_consumer_info!(consumer_name)

    assert command_execution.platform == "discord"
    assert command_execution.command == "backfill"
    assert command_execution.status == "succeeded"
    assert command_execution.args["channel"] == "ops"
    assert command_execution.worker_id == Atom.to_string(node())
    assert not is_nil(command_execution.claimed_at)
    assert not is_nil(command_execution.completed_at)
    assert command_execution.metadata["execution"]["executor"] == "noop"
    assert after_info.num_pending == 0
  end

  defp create_test_consumer!(consumer_name, tenant_subject_name) do
    spec = %Consumer{
      stream_name: Topology.stream_name(),
      durable_name: consumer_name,
      ack_policy: :explicit,
      replay_policy: :instant,
      deliver_policy: :new,
      filter_subject: "threadr.tenants.#{tenant_subject_name}.>"
    }

    case Consumer.create(Topology.connection_name(), spec) do
      {:ok, _consumer} -> :ok
      {:error, reason} -> raise "failed to create test JetStream consumer: #{inspect(reason)}"
    end
  end

  defp fetch_consumer_info!(consumer_name) do
    {:ok, info} =
      Consumer.info(Topology.connection_name(), Topology.stream_name(), consumer_name)

    info
  end

  defp await_command_execution!(tenant_subject_name, external_id, command) do
    deadline = System.monotonic_time(:millisecond) + 5_000
    do_await_command_execution(tenant_subject_name, external_id, command, deadline)
  end

  defp do_await_command_execution(tenant_subject_name, external_id, command, deadline) do
    {:ok, tenant} =
      Threadr.ControlPlane.get_tenant_by_subject_name(
        tenant_subject_name,
        context: %{system: true}
      )

    query =
      CommandExecution
      |> Ash.Query.filter(expr(external_id == ^external_id and command == ^command))

    case Ash.read_one!(query, tenant: tenant.schema_name) do
      nil ->
        if System.monotonic_time(:millisecond) >= deadline do
          raise "timed out waiting for command #{command} with external_id #{external_id}"
        end

        Process.sleep(250)
        do_await_command_execution(tenant_subject_name, external_id, command, deadline)

      %CommandExecution{status: status}
      when status in ["claimed", "running"] ->
        if System.monotonic_time(:millisecond) >= deadline do
          raise "timed out waiting for command #{command} terminal state for #{external_id}"
        end

        Process.sleep(250)
        do_await_command_execution(tenant_subject_name, external_id, command, deadline)

      command_execution ->
        command_execution
    end
  end

  defp await_message_embedding!(tenant_schema, message_id, model) do
    deadline = System.monotonic_time(:millisecond) + 5_000
    do_await_message_embedding(tenant_schema, message_id, model, deadline)
  end

  defp do_await_message_embedding(tenant_schema, message_id, model, deadline) do
    query =
      MessageEmbedding
      |> Ash.Query.filter(expr(message_id == ^message_id and model == ^model))

    case Ash.read_one!(query, tenant: tenant_schema) do
      nil ->
        if System.monotonic_time(:millisecond) >= deadline do
          raise "timed out waiting for embedding #{model} on message #{message_id}"
        end

        Process.sleep(250)
        do_await_message_embedding(tenant_schema, message_id, model, deadline)

      embedding ->
        embedding
    end
  end
end
