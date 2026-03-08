defmodule Threadr.ControlPlane.Checks.ManagesTenant do
  @moduledoc """
  Authorizes a user against tenant membership for create/update/destroy operations.
  """

  use Ash.Policy.SimpleCheck
  import Ecto.Query

  alias Threadr.Repo

  @impl true
  def describe(opts) do
    if Keyword.get(opts, :manager?, true) do
      "actor manages the target tenant"
    else
      "actor is a member of the target tenant"
    end
  end

  @impl true
  def match?(%{id: user_id}, %{subject: subject}, opts) when is_binary(user_id) do
    with {:ok, tenant_id} <- tenant_id(subject),
         true <- membership_exists?(tenant_id, user_id, Keyword.get(opts, :manager?, true)) do
      true
    else
      _ -> false
    end
  end

  def match?(_, _, _), do: false

  defp tenant_id(%Ash.Changeset{} = changeset) do
    case changeset.resource do
      Threadr.ControlPlane.Bot ->
        value =
          changeset.attributes[:tenant_id] ||
            Map.get(changeset.arguments, :tenant_id) ||
            changeset.data.tenant_id

        present(value)

      Threadr.ControlPlane.TenantMembership ->
        value =
          changeset.attributes[:tenant_id] ||
            Map.get(changeset.arguments, :tenant_id) ||
            changeset.data.tenant_id

        present(value)

      Threadr.ControlPlane.TenantLlmConfig ->
        value =
          changeset.attributes[:tenant_id] ||
            Map.get(changeset.arguments, :tenant_id) ||
            changeset.data.tenant_id

        present(value)

      Threadr.ControlPlane.Tenant ->
        present(changeset.data.id)

      _ ->
        {:error, :unsupported_resource}
    end
  end

  defp tenant_id(%resource{} = record)
       when resource in [
              Threadr.ControlPlane.Bot,
              Threadr.ControlPlane.TenantLlmConfig,
              Threadr.ControlPlane.Tenant,
              Threadr.ControlPlane.TenantMembership
            ] do
    case resource do
      Threadr.ControlPlane.Bot -> present(record.tenant_id)
      Threadr.ControlPlane.TenantLlmConfig -> present(record.tenant_id)
      Threadr.ControlPlane.TenantMembership -> present(record.tenant_id)
      Threadr.ControlPlane.Tenant -> present(record.id)
    end
  end

  defp tenant_id(_), do: {:error, :missing_subject}

  defp present(nil), do: {:error, :missing_tenant_id}
  defp present(value), do: {:ok, value}

  defp membership_exists?(tenant_id, user_id, manager?) do
    tenant_id = normalize_uuid!(tenant_id)
    user_id = normalize_uuid!(user_id)

    query =
      from(tm in "tenant_memberships",
        where: field(tm, :tenant_id) == type(^tenant_id, Ecto.UUID),
        where: field(tm, :user_id) == type(^user_id, Ecto.UUID),
        select: 1,
        limit: 1
      )

    query =
      if manager? do
        where(query, [tm], field(tm, :role) in ["owner", "admin"])
      else
        query
      end

    Repo.exists?(query)
  end

  defp normalize_uuid!(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> uuid
      :error -> raise ArgumentError, "invalid UUID: #{inspect(value)}"
    end
  end

  defp normalize_uuid!(value), do: value
end
