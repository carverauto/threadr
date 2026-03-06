defmodule Threadr.Commands.Executor do
  @moduledoc """
  Behaviour for executing tenant-scoped ingest commands.
  """

  @callback execute(struct(), String.t()) :: {:ok, map()} | {:error, term()}
end
