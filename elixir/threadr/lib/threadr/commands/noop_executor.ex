defmodule Threadr.Commands.NoopExecutor do
  @moduledoc """
  Default executor used until platform-specific command runners exist.
  """

  @behaviour Threadr.Commands.Executor

  @impl true
  def execute(command_execution, tenant_schema) do
    {:ok,
     %{
       "executor" => "noop",
       "tenant_schema" => tenant_schema,
       "command" => command_execution.command
     }}
  end
end
