defmodule Threadr.ML.ReconstructionQuery do
  @moduledoc """
  Helpers for reconstruction-backed queries that must degrade cleanly when a
  tenant schema has not been migrated with the reconstruction tables yet.
  """

  alias Threadr.Repo

  def all(query, tenant_schema, fallback \\ [])
      when is_binary(tenant_schema) do
    Repo.all(query, prefix: tenant_schema)
  rescue
    error in Postgrex.Error ->
      if missing_table?(error) do
        fallback
      else
        reraise error, __STACKTRACE__
      end
  end

  def missing_table?(%Postgrex.Error{postgres: %{code: :undefined_table}}), do: true
  def missing_table?(%Postgrex.Error{postgres: %{code: "42P01"}}), do: true
  def missing_table?(_error), do: false
end
