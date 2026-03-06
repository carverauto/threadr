defmodule Threadr.Messaging.Handlers.Commands do
  @moduledoc """
  Tenant-aware handler for normalized ingest commands.
  """

  import Ash.Expr
  require Ash.Query
  require Logger

  alias Threadr.Events.{Envelope, IngestCommand}
  alias Threadr.Messaging.Topology
  alias Threadr.TenantData.CommandExecution

  @terminal_statuses ~w(succeeded failed)
  @in_progress_statuses ~w(claimed running)

  def handle_envelope(
        %Envelope{type: "ingest.command", data: %IngestCommand{} = command} = envelope
      ) do
    with {:ok, tenant_subject_name} <- Topology.tenant_subject_name_from_subject(envelope.subject),
         {:ok, tenant} <-
           Threadr.ControlPlane.get_tenant_by_subject_name(
             tenant_subject_name,
             context: %{system: true}
           ),
         {:ok, command_execution} <-
           upsert_command_execution(command, envelope, tenant.schema_name),
         {:ok, command_execution} <- maybe_execute_command(command_execution, tenant.schema_name) do
      Logger.info(
        "handled ingest command #{command.command} for tenant #{tenant.subject_name} with status #{command_execution.status}"
      )

      {:ok,
       %{
         tenant_schema: tenant.schema_name,
         tenant_subject_name: tenant.subject_name,
         command: command.command,
         command_execution_id: command_execution.id
       }}
    end
  end

  def handle_envelope(%Envelope{type: type}) do
    {:error, {:unsupported_envelope_type, type}}
  end

  defp upsert_command_execution(command, envelope, tenant_schema) do
    query =
      CommandExecution
      |> Ash.Query.filter(expr(external_id == ^envelope.id))

    case Ash.read_one(query, tenant: tenant_schema) do
      {:ok, nil} ->
        CommandExecution
        |> Ash.Changeset.for_create(
          :create,
          %{
            external_id: envelope.id,
            platform: command.platform,
            command: command.command,
            target: command.target,
            args: stringify_map(command.args),
            status: "received",
            metadata: %{
              "subject" => envelope.subject,
              "source" => envelope.source,
              "correlation_id" => envelope.correlation_id
            },
            issued_at: command.issued_at
          },
          tenant: tenant_schema
        )
        |> Ash.create()

      result ->
        result
    end
  end

  defp maybe_execute_command(
         %CommandExecution{status: status} = command_execution,
         _tenant_schema
       )
       when status in @terminal_statuses or status in @in_progress_statuses do
    {:ok, command_execution}
  end

  defp maybe_execute_command(%CommandExecution{} = command_execution, tenant_schema) do
    with {:ok, claimed_execution} <- claim_command_execution(command_execution, tenant_schema),
         {:ok, completed_execution} <- execute_command(claimed_execution, tenant_schema) do
      {:ok, completed_execution}
    end
  end

  defp claim_command_execution(command_execution, tenant_schema) do
    command_execution
    |> Ash.Changeset.for_update(
      :update,
      %{
        status: "claimed",
        worker_id: worker_id(),
        claimed_at: DateTime.utc_now(),
        last_error: nil
      },
      tenant: tenant_schema
    )
    |> Ash.update()
  end

  defp execute_command(command_execution, tenant_schema) do
    executor = Application.fetch_env!(:threadr, :command_executor)

    case executor.execute(command_execution, tenant_schema) do
      {:ok, result_metadata} ->
        command_execution
        |> Ash.Changeset.for_update(
          :update,
          %{
            status: "succeeded",
            completed_at: DateTime.utc_now(),
            metadata:
              merge_metadata(command_execution.metadata, %{
                "execution" => stringify_map(result_metadata)
              }),
            last_error: nil
          },
          tenant: tenant_schema
        )
        |> Ash.update()

      {:error, reason} ->
        command_execution
        |> Ash.Changeset.for_update(
          :update,
          %{
            status: "failed",
            completed_at: DateTime.utc_now(),
            last_error: inspect(reason),
            metadata:
              merge_metadata(command_execution.metadata, %{
                "execution_error" => inspect(reason)
              })
          },
          tenant: tenant_schema
        )
        |> Ash.update()
    end
  end

  defp worker_id do
    node()
    |> Atom.to_string()
  end

  defp merge_metadata(existing, updates) when is_map(existing) and is_map(updates) do
    Map.merge(stringify_map(existing), stringify_map(updates))
  end

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
