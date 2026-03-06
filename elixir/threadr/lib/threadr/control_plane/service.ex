defmodule Threadr.ControlPlane.Service do
  @moduledoc """
  Operational service layer for tenant provisioning and bot reconciliation.
  """

  @manager_roles ~w(owner admin)
  @membership_roles ~w(owner admin member)
  @bot_statuses [
    :pending,
    :reconciling,
    :running,
    :stopped,
    :degraded,
    :deleting,
    :deleted,
    :error
  ]
  @tenant_schema_prefix "tenant_"

  def create_tenant(attrs, opts \\ []) do
    ash_opts = ash_opts(opts)

    with {:ok, tenant} <-
           attrs
           |> normalize_tenant_attrs()
           |> Threadr.ControlPlane.create_tenant(ash_opts),
         {:ok, _membership} <- maybe_create_owner_membership(tenant, opts),
         {:ok, tenant} <-
           mark_tenant_migration_succeeded(tenant, latest_tenant_migration_version(), ash_opts) do
      {:ok, tenant}
    end
  end

  def create_bot(attrs, opts \\ []) do
    ash_opts = ash_opts(opts)

    with {:ok, bot} <- Threadr.ControlPlane.create_bot(attrs, ash_opts),
         {:ok, bot} <- request_bot_reconcile(bot, %{}, ash_opts),
         {:ok, _operation} <- enqueue_bot_operation(bot, "apply", ash_opts) do
      {:ok, bot}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  def create_tenant_for_user(%{id: _user_id} = user, attrs, opts \\ []) do
    opts
    |> Keyword.put(:owner_user, user)
    |> Keyword.put(:actor, user)
    |> then(&create_tenant(attrs, &1))
  end

  def normalize_tenant_attrs(attrs) do
    name = fetch(attrs, :name)
    slug = fetch(attrs, :slug) || slugify(name)
    schema_name = fetch(attrs, :schema_name) || schema_name_from_slug(slug)
    subject_name = fetch(attrs, :subject_name) || subject_name_from_slug(slug)

    attrs
    |> put_value(:slug, slug)
    |> put_value(:schema_name, schema_name)
    |> put_value(:subject_name, subject_name)
  end

  def slugify(nil), do: nil

  def slugify(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  def schema_name_from_slug(slug) when is_binary(slug) do
    sanitized =
      slug
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "_")
      |> String.trim("_")

    @tenant_schema_prefix <> sanitized
  end

  def subject_name_from_slug(slug) when is_binary(slug) do
    slug
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/u, "-")
    |> String.replace(~r/-{2,}/u, "-")
    |> String.trim("-")
  end

  def manager_role?(role) when role in @manager_roles, do: true
  def manager_role?(_role), do: false

  def latest_tenant_migration_version do
    Threadr.Repo.tenant_migrations_path()
    |> Path.join("**/*.exs")
    |> Path.wildcard()
    |> Enum.map(&Path.basename/1)
    |> Enum.map(&Path.rootname/1)
    |> Enum.map(&Integer.parse/1)
    |> Enum.filter(&match?({_, _}, &1))
    |> Enum.map(&elem(&1, 0))
    |> Enum.max(fn -> nil end)
  end

  def list_user_tenants(%{id: user_id}, opts \\ []) when is_binary(user_id) do
    with {:ok, memberships} <- list_user_memberships(%{id: user_id}, opts) do
      {:ok, Enum.map(memberships, & &1.tenant)}
    end
  end

  def list_user_memberships(%{id: user_id}, opts \\ []) when is_binary(user_id) do
    ash_opts = actor_ash_opts(%{id: user_id}, opts)

    with {:ok, memberships} <-
           Threadr.ControlPlane.list_tenant_memberships(
             Keyword.merge(ash_opts,
               query: [
                 filter: [user_id: user_id],
                 sort: [inserted_at: :asc],
                 load: [:tenant]
               ]
             )
           ) do
      {:ok, memberships}
    end
  end

  def get_user_tenant_by_subject_name(%{id: _user_id} = user, subject_name, opts \\ [])
      when is_binary(subject_name) do
    with {:ok, tenant} <-
           Threadr.ControlPlane.get_tenant_by_subject_name(
             subject_name,
             actor_ash_opts(user, opts)
           ),
         {:ok, membership} <- authorize_tenant_membership(user, tenant, opts) do
      {:ok, tenant, membership}
    else
      {:error, error} -> {:error, normalize_tenant_access_error(error, subject_name)}
    end
  end

  def migrate_tenant_for_user(%{id: _user_id} = user, subject_name, opts \\ [])
      when is_binary(subject_name) do
    with {:ok, tenant, membership} <- get_user_tenant_by_subject_name(user, subject_name, opts),
         :ok <- authorize_manager_role(membership),
         {:ok, result} <-
           Threadr.ControlPlane.TenantMigrations.migrate_tenant(tenant) |> wrap_ok() do
      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def list_bots_for_user(%{id: _user_id} = user, subject_name, opts \\ [])
      when is_binary(subject_name) do
    with {:ok, tenant, _membership} <- get_user_tenant_by_subject_name(user, subject_name, opts),
         {:ok, bots} <-
           Threadr.ControlPlane.list_bots(
             Keyword.merge(actor_ash_opts(user, opts),
               query: [filter: [tenant_id: tenant.id], sort: [name: :asc]]
             )
           ) do
      {:ok, Enum.reject(bots, &(&1.desired_state == "deleted"))}
    end
  end

  def create_bot_for_user(%{id: _user_id} = user, subject_name, attrs, opts \\ [])
      when is_binary(subject_name) do
    with {:ok, tenant, membership} <- get_user_tenant_by_subject_name(user, subject_name, opts),
         :ok <- authorize_manager_role(membership),
         {:ok, bot} <-
           create_bot(Map.put(attrs, :tenant_id, tenant.id), Keyword.put(opts, :actor, user)) do
      {:ok, bot}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def update_bot_for_user(%{id: _user_id} = user, subject_name, bot_id, attrs, opts \\ [])
      when is_binary(subject_name) and is_binary(bot_id) do
    with {:ok, tenant, membership} <- get_user_tenant_by_subject_name(user, subject_name, opts),
         :ok <- authorize_manager_role(membership),
         {:ok, bot} <- fetch_bot_for_tenant(user, tenant.id, bot_id, opts),
         {:ok, updated_bot} <-
           Threadr.ControlPlane.update_bot(
             bot,
             take_attrs(attrs, [:desired_state, :channels, :settings]),
             actor_ash_opts(user, opts)
           ),
         {:ok, updated_bot} <-
           request_bot_reconcile(updated_bot, %{}, actor_ash_opts(user, opts)),
         {:ok, _operation} <- enqueue_bot_operation(updated_bot, "apply", system_ash_opts(opts)) do
      {:ok, updated_bot}
    else
      {:error, reason} -> {:error, normalize_resource_access_error(reason, :bot, bot_id)}
    end
  end

  def delete_bot_for_user(%{id: _user_id} = user, subject_name, bot_id, opts \\ [])
      when is_binary(subject_name) and is_binary(bot_id) do
    with {:ok, tenant, membership} <- get_user_tenant_by_subject_name(user, subject_name, opts),
         :ok <- authorize_manager_role(membership),
         {:ok, bot} <- fetch_bot_for_tenant(user, tenant.id, bot_id, opts),
         {:ok, bot} <-
           transition_bot(
             bot,
             %{desired_state: "deleted"},
             actor_ash_opts(user, opts)
           ),
         {:ok, bot} <- begin_bot_delete(bot, %{}, actor_ash_opts(user, opts)),
         {:ok, _operation} <- enqueue_bot_operation(bot, "delete", system_ash_opts(opts)) do
      :ok
    else
      {:error, reason} -> {:error, normalize_resource_access_error(reason, :bot, bot_id)}
    end
  end

  def list_tenant_memberships_for_user(%{id: _user_id} = user, subject_name, opts \\ [])
      when is_binary(subject_name) do
    with {:ok, tenant, membership} <- get_user_tenant_by_subject_name(user, subject_name, opts),
         :ok <- authorize_manager_role(membership),
         {:ok, memberships} <-
           Threadr.ControlPlane.list_tenant_memberships(
             Keyword.merge(system_ash_opts(opts),
               query: [filter: [tenant_id: tenant.id], sort: [inserted_at: :asc]]
             )
           ),
         {:ok, memberships} <- attach_users_to_memberships(memberships, opts) do
      {:ok, memberships}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def create_tenant_membership_for_user(%{id: _user_id} = user, subject_name, attrs, opts \\ [])
      when is_binary(subject_name) do
    with {:ok, tenant, membership} <- get_user_tenant_by_subject_name(user, subject_name, opts),
         :ok <- authorize_manager_role(membership),
         {:ok, invitee_email} <- fetch_required_string(attrs, :email),
         {:ok, role} <- normalize_membership_role(fetch(attrs, :role) || "member"),
         {:ok, invitee} <- fetch_user_by_email(invitee_email, opts),
         {:ok, tenant_membership} <-
           Threadr.ControlPlane.create_tenant_membership(
             %{tenant_id: tenant.id, user_id: invitee.id, role: role},
             system_ash_opts(opts)
           ) do
      load_membership_user(tenant_membership, opts)
    else
      {:error, reason} -> {:error, normalize_membership_create_error(reason)}
    end
  end

  def update_tenant_membership_for_user(
        %{id: _user_id} = user,
        subject_name,
        membership_id,
        attrs,
        opts \\ []
      )
      when is_binary(subject_name) and is_binary(membership_id) do
    with {:ok, tenant, membership} <- get_user_tenant_by_subject_name(user, subject_name, opts),
         :ok <- authorize_manager_role(membership),
         {:ok, tenant_membership} <-
           fetch_tenant_membership_for_tenant(tenant.id, membership_id, opts),
         {:ok, role} <- normalize_membership_role(fetch(attrs, :role)),
         {:ok, tenant_membership} <-
           Threadr.ControlPlane.update_tenant_membership(
             tenant_membership,
             %{role: role},
             system_ash_opts(opts)
           ) do
      load_membership_user(tenant_membership, opts)
    else
      {:error, reason} ->
        {:error, normalize_resource_access_error(reason, :tenant_membership, membership_id)}
    end
  end

  def delete_tenant_membership_for_user(
        %{id: _user_id} = user,
        subject_name,
        membership_id,
        opts \\ []
      )
      when is_binary(subject_name) and is_binary(membership_id) do
    with {:ok, tenant, membership} <- get_user_tenant_by_subject_name(user, subject_name, opts),
         :ok <- authorize_manager_role(membership),
         {:ok, tenant_membership} <-
           fetch_tenant_membership_for_tenant(tenant.id, membership_id, opts),
         :ok <-
           Threadr.ControlPlane.destroy_tenant_membership(
             tenant_membership,
             system_ash_opts(opts)
           ) do
      :ok
    else
      {:error, reason} ->
        {:error, normalize_resource_access_error(reason, :tenant_membership, membership_id)}
    end
  end

  def list_user_api_keys(%{id: user_id}, opts \\ []) when is_binary(user_id) do
    Threadr.ControlPlane.list_api_keys(
      Keyword.merge(actor_ash_opts(%{id: user_id}, opts),
        query: [filter: [user_id: user_id], sort: [inserted_at: :desc]]
      )
    )
  end

  def create_api_key(%{id: user_id} = user, attrs, opts \\ []) when is_binary(user_id) do
    case Threadr.ControlPlane.create_api_key(
           Map.put(attrs, :user_id, user_id),
           actor_ash_opts(user, opts)
         ) do
      {:ok, api_key} ->
        {:ok, api_key, api_key.__metadata__[:plaintext_api_key]}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def revoke_api_key(%{id: user_id} = user, api_key_id, opts \\ []) when is_binary(user_id) do
    ash_opts = actor_ash_opts(user, opts)

    with {:ok, api_key} <- Threadr.ControlPlane.get_api_key(api_key_id, ash_opts),
         :ok <- authorize_api_key_owner(api_key, user_id),
         {:ok, api_key} <-
           Threadr.ControlPlane.update_api_key(
             api_key,
             %{revoked_at: DateTime.utc_now()},
             ash_opts
           ) do
      {:ok, api_key}
    end
  end

  def touch_api_key(api_key_id, opts \\ []) when is_binary(api_key_id) do
    ash_opts = ash_opts(opts)

    with {:ok, api_key} <- Threadr.ControlPlane.get_api_key(api_key_id, ash_opts),
         {:ok, api_key} <-
           Threadr.ControlPlane.update_api_key(
             api_key,
             %{last_used_at: DateTime.utc_now()},
             ash_opts
           ) do
      {:ok, api_key}
    end
  end

  def report_bot_status_for_controller(subject_name, bot_id, attrs, opts \\ [])
      when is_binary(subject_name) and is_binary(bot_id) do
    with {:ok, tenant} <-
           get_tenant_by_subject_name_system(subject_name, opts),
         {:ok, bot} <- fetch_bot_for_tenant_system(tenant.id, bot_id, opts),
         {:ok, target_status, update_attrs} <- normalize_controller_status_attrs(bot, attrs),
         {:ok, bot} <- apply_controller_bot_status(bot, target_status, update_attrs, opts) do
      {:ok, bot}
    else
      {:error, {:tenant_not_found, _} = error} -> {:error, error}
      {:error, error} -> {:error, normalize_resource_access_error(error, :bot, bot_id)}
    end
  end

  def list_bot_controller_contracts(opts \\ []) do
    Threadr.ControlPlane.list_bot_controller_contracts(
      Keyword.merge(system_ash_opts(opts), query: [sort: [updated_at: :asc]])
    )
  end

  def get_bot_controller_contract_for_controller(subject_name, bot_id, opts \\ [])
      when is_binary(subject_name) and is_binary(bot_id) do
    with {:ok, tenant} <- get_tenant_by_subject_name_system(subject_name, opts),
         {:ok, bot} <- fetch_bot_for_tenant_system(tenant.id, bot_id, opts) do
      Threadr.ControlPlane.get_bot_controller_contract(bot.id, system_ash_opts(opts))
    else
      {:error, {:tenant_not_found, _} = error} -> {:error, error}
      {:error, error} -> {:error, normalize_resource_access_error(error, :bot, bot_id)}
    end
  end

  def mark_tenant_migration_running(tenant, opts \\ []) do
    Threadr.ControlPlane.update_tenant(
      tenant,
      %{
        tenant_migration_status: "running",
        tenant_migration_error: nil
      },
      ash_opts(opts)
    )
  end

  def mark_tenant_migration_succeeded(tenant, version, opts \\ []) do
    Threadr.ControlPlane.update_tenant(
      tenant,
      %{
        tenant_migration_status: "succeeded",
        tenant_migration_version: version,
        tenant_migrated_at: DateTime.utc_now(),
        tenant_migration_error: nil
      },
      ash_opts(opts)
    )
  end

  def mark_tenant_migration_failed(tenant, reason, opts \\ []) do
    Threadr.ControlPlane.update_tenant(
      tenant,
      %{
        tenant_migration_status: "failed",
        tenant_migration_error: inspect(reason)
      },
      ash_opts(opts)
    )
  end

  defp enqueue_bot_operation(bot, operation, opts) do
    ash_opts = system_ash_opts(opts)
    payload = bot_operation_payload(bot, operation)

    with {:ok, bot_operation} <-
           Threadr.ControlPlane.create_bot_reconcile_operation(
             %{
               tenant_id: bot.tenant_id,
               bot_id: bot.id,
               operation: operation,
               status: "pending",
               payload: payload,
               attempt_count: 0,
               next_attempt_at: DateTime.utc_now()
             },
             ash_opts
           ) do
      Threadr.ControlPlane.BotOperationDispatcher.trigger()
      {:ok, bot_operation}
    end
  end

  defp bot_operation_payload(bot, operation) do
    %{
      "operation" => operation,
      "bot" => %{
        "id" => bot.id,
        "tenant_id" => bot.tenant_id,
        "name" => bot.name,
        "platform" => bot.platform,
        "desired_state" => bot.desired_state,
        "status" => bot.status,
        "channels" => bot.channels,
        "settings" => bot.settings,
        "deployment_name" => bot.deployment_name
      }
    }
  end

  defp transition_bot(bot, attrs, ash_opts) do
    Threadr.ControlPlane.update_bot(bot, attrs, ash_opts)
  end

  defp request_bot_reconcile(bot, attrs, ash_opts) do
    Threadr.ControlPlane.request_bot_reconcile(bot, attrs, ash_opts)
  end

  defp begin_bot_delete(bot, attrs, ash_opts) do
    Threadr.ControlPlane.begin_bot_delete(bot, attrs, ash_opts)
  end

  defp report_bot_status(bot, target_status, attrs, ash_opts) do
    Threadr.ControlPlane.report_bot_status(
      bot,
      Map.put(attrs, :target_status, target_status),
      ash_opts
    )
  end

  defp apply_controller_bot_status(bot, :deleted, attrs, opts) do
    with {:ok, bot} <- finalize_bot_delete(bot, attrs, system_ash_opts(opts)),
         :ok <- destroy_bot(bot, system_ash_opts(opts)) do
      {:ok, bot}
    end
  end

  defp apply_controller_bot_status(bot, target_status, attrs, opts) do
    report_bot_status(bot, target_status, attrs, system_ash_opts(opts))
  end

  defp finalize_bot_delete(bot, attrs, ash_opts) do
    Threadr.ControlPlane.finalize_bot_delete(bot, attrs, ash_opts)
  end

  defp destroy_bot(bot, ash_opts) do
    case Threadr.ControlPlane.destroy_bot(bot, ash_opts) do
      :ok -> :ok
      {:ok, _destroyed_bot} -> :ok
      other -> other
    end
  end

  defp normalize_controller_status_attrs(bot, attrs) do
    with {:ok, target_status} <- fetch_bot_status(attrs),
         {:ok, deployment_name} <- normalize_deployment_name(bot, fetch(attrs, :deployment_name)),
         {:ok, status_metadata} <- normalize_status_metadata(fetch(attrs, :metadata)),
         {:ok, last_observed_at} <- normalize_observed_at(fetch(attrs, :observed_at)),
         {:ok, observed_generation} <- normalize_generation(fetch(attrs, :generation)),
         :ok <- validate_generation(bot, observed_generation) do
      {:ok, target_status,
       %{
         deployment_name: deployment_name,
         status_reason: normalize_reason(fetch(attrs, :reason)),
         status_metadata: Map.put(status_metadata, "source", "controller_callback"),
         last_observed_at: last_observed_at,
         observed_generation: observed_generation
       }}
    end
  end

  defp fetch_bot_status(attrs) do
    case Threadr.ControlPlane.BotStatus.match(fetch(attrs, :status)) do
      {:ok, status} when status in @bot_statuses -> {:ok, status}
      {:ok, status} -> {:error, {:invalid_bot_status, status}}
      :error -> {:error, {:invalid_bot_status, fetch(attrs, :status)}}
    end
  end

  defp normalize_deployment_name(%{deployment_name: current}, nil) when is_binary(current),
    do: {:ok, current}

  defp normalize_deployment_name(_bot, nil), do: {:ok, nil}

  defp normalize_deployment_name(%{deployment_name: nil}, deployment_name)
       when is_binary(deployment_name) and deployment_name != "",
       do: {:ok, deployment_name}

  defp normalize_deployment_name(%{deployment_name: current}, deployment_name)
       when is_binary(current) and is_binary(deployment_name) and current == deployment_name,
       do: {:ok, current}

  defp normalize_deployment_name(%{deployment_name: current}, deployment_name)
       when is_binary(current) and is_binary(deployment_name) and current != deployment_name,
       do: {:error, {:deployment_mismatch, current, deployment_name}}

  defp normalize_deployment_name(_bot, deployment_name) when deployment_name in ["", nil],
    do: {:ok, nil}

  defp normalize_deployment_name(_bot, deployment_name),
    do: {:error, {:invalid_deployment_name, deployment_name}}

  defp normalize_status_metadata(nil), do: {:ok, %{}}

  defp normalize_status_metadata(metadata) when is_map(metadata),
    do: {:ok, stringify_map(metadata)}

  defp normalize_status_metadata(metadata), do: {:error, {:invalid_status_metadata, metadata}}

  defp normalize_observed_at(nil), do: {:ok, DateTime.utc_now()}
  defp normalize_observed_at(%DateTime{} = observed_at), do: {:ok, observed_at}

  defp normalize_observed_at(observed_at) when is_binary(observed_at) do
    case DateTime.from_iso8601(observed_at) do
      {:ok, observed_at, _offset} -> {:ok, observed_at}
      _ -> {:error, {:invalid_observed_at, observed_at}}
    end
  end

  defp normalize_observed_at(observed_at), do: {:error, {:invalid_observed_at, observed_at}}

  defp normalize_generation(nil), do: {:ok, nil}
  defp normalize_generation(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp normalize_generation(value) when is_binary(value) do
    case Integer.parse(value) do
      {value, ""} when value >= 0 -> {:ok, value}
      _ -> {:error, {:invalid_generation, value}}
    end
  end

  defp normalize_generation(value), do: {:error, {:invalid_generation, value}}

  defp validate_generation(_bot, nil), do: :ok
  defp validate_generation(%{desired_generation: generation}, generation), do: :ok

  defp validate_generation(%{desired_generation: current_generation}, reported_generation) do
    {:error, {:generation_mismatch, current_generation, reported_generation}}
  end

  defp normalize_reason(nil), do: nil
  defp normalize_reason(reason), do: to_string(reason)

  defp fetch(attrs, key) when is_map(attrs) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp put_value(attrs, key, value) when is_map(attrs) do
    if Map.has_key?(attrs, key) or not Map.has_key?(attrs, Atom.to_string(key)) do
      Map.put(attrs, key, value)
    else
      Map.put(attrs, Atom.to_string(key), value)
    end
  end

  defp maybe_create_owner_membership(tenant, opts) do
    case Keyword.get(opts, :owner_user) do
      %{id: user_id} ->
        Threadr.ControlPlane.create_tenant_membership(
          %{
            user_id: user_id,
            tenant_id: tenant.id,
            role: "owner"
          },
          ash_opts([])
        )

      _ ->
        {:ok, nil}
    end
  end

  defp authorize_api_key_owner(%{user_id: user_id}, user_id), do: :ok
  defp authorize_api_key_owner(_api_key, _user_id), do: {:error, :forbidden}

  defp fetch_bot_for_tenant(user, tenant_id, bot_id, opts) do
    case Threadr.ControlPlane.get_bot(bot_id, actor_ash_opts(user, opts)) do
      {:ok, %{tenant_id: ^tenant_id} = bot} -> {:ok, bot}
      {:ok, _bot} -> {:error, :forbidden}
      {:error, error} -> {:error, error}
    end
  end

  defp get_tenant_by_subject_name_system(subject_name, opts) do
    case Threadr.ControlPlane.get_tenant_by_subject_name(subject_name, system_ash_opts(opts)) do
      {:ok, tenant} -> {:ok, tenant}
      {:error, error} -> {:error, normalize_tenant_access_error(error, subject_name)}
    end
  end

  defp fetch_bot_for_tenant_system(tenant_id, bot_id, opts) do
    case Threadr.ControlPlane.get_bot(bot_id, system_ash_opts(opts)) do
      {:ok, %{tenant_id: ^tenant_id} = bot} -> {:ok, bot}
      {:ok, _bot} -> {:error, :forbidden}
      {:error, error} -> {:error, error}
    end
  end

  defp fetch_tenant_membership_for_tenant(tenant_id, membership_id, opts) do
    case Threadr.ControlPlane.get_tenant_membership(membership_id, system_ash_opts(opts)) do
      {:ok, %{tenant_id: ^tenant_id} = tenant_membership} -> {:ok, tenant_membership}
      {:ok, _tenant_membership} -> {:error, :forbidden}
      {:error, error} -> {:error, error}
    end
  end

  defp fetch_user_by_email(email, opts) do
    case Threadr.ControlPlane.get_user_by_email(email, system_ash_opts(opts)) do
      {:ok, nil} -> {:error, {:user_not_found, email}}
      {:ok, user} -> {:ok, user}
      {:error, error} -> normalize_user_lookup_error(error, email)
    end
  end

  defp load_membership_user(tenant_membership, opts) do
    with {:ok, memberships} <-
           Threadr.ControlPlane.list_tenant_memberships(
             Keyword.merge(system_ash_opts(opts), query: [filter: [id: tenant_membership.id]])
           ),
         {:ok, [loaded_membership]} <- attach_users_to_memberships(memberships, opts) do
      {:ok, loaded_membership}
    end
  end

  defp attach_users_to_memberships(memberships, opts) do
    memberships
    |> Enum.reduce_while({:ok, []}, fn membership, {:ok, acc} ->
      case Threadr.ControlPlane.get_user_by_id(membership.user_id, system_ash_opts(opts)) do
        {:ok, user} ->
          {:cont, {:ok, [Map.put(membership, :user, user) | acc]}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, memberships_with_users} -> {:ok, Enum.reverse(memberships_with_users)}
      error -> error
    end
  end

  defp authorize_tenant_membership(user, tenant, opts) do
    with {:ok, memberships} <- list_user_memberships(user, opts),
         membership when not is_nil(membership) <-
           Enum.find(memberships, &(&1.tenant_id == tenant.id)) do
      {:ok, membership}
    else
      nil -> {:error, :forbidden}
      {:error, reason} -> {:error, reason}
    end
  end

  defp authorize_manager_role(%{role: role}) when role in @manager_roles, do: :ok
  defp authorize_manager_role(_membership), do: {:error, :forbidden}

  defp normalize_membership_role(role) when role in @membership_roles, do: {:ok, role}
  defp normalize_membership_role(role) when is_binary(role), do: {:error, {:invalid_role, role}}
  defp normalize_membership_role(nil), do: {:error, {:invalid_role, nil}}

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {to_string(key), stringify_value(value)}
    end)
  end

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(value) when is_list(value), do: Enum.map(value, &stringify_value/1)
  defp stringify_value(value), do: value

  defp fetch_required_string(attrs, key) do
    case fetch(attrs, key) do
      nil ->
        {:error, {:missing_required_field, key}}

      value ->
        trimmed = value |> to_string() |> String.trim()

        if byte_size(trimmed) > 0 do
          {:ok, trimmed}
        else
          {:error, {:missing_required_field, key}}
        end
    end
  end

  defp take_attrs(attrs, keys) do
    Enum.reduce(keys, %{}, fn key, acc ->
      cond do
        is_map(attrs) and Map.has_key?(attrs, key) ->
          Map.put(acc, key, Map.get(attrs, key))

        is_map(attrs) and Map.has_key?(attrs, Atom.to_string(key)) ->
          Map.put(acc, key, Map.get(attrs, Atom.to_string(key)))

        true ->
          acc
      end
    end)
  end

  defp normalize_tenant_access_error({:tenant_not_found, _} = error, _subject_name), do: error

  defp normalize_tenant_access_error(%Ash.Error.Invalid{errors: errors}, subject_name) do
    if Enum.any?(errors, &match?(%Ash.Error.Query.NotFound{}, &1)) do
      {:tenant_not_found, subject_name}
    else
      %Ash.Error.Invalid{errors: errors}
    end
  end

  defp normalize_tenant_access_error(error, _subject_name), do: error

  defp normalize_resource_access_error({:tenant_not_found, _} = error, _resource_type, _lookup),
    do: error

  defp normalize_resource_access_error(
         %Ash.Error.Invalid{errors: errors},
         resource_type,
         lookup_value
       ) do
    if Enum.any?(errors, &match?(%Ash.Error.Query.NotFound{}, &1)) do
      {resource_type, :not_found, lookup_value}
    else
      %Ash.Error.Invalid{errors: errors}
    end
  end

  defp normalize_resource_access_error(error, _resource_type, _lookup_value), do: error

  defp normalize_membership_create_error({:user_not_found, _} = error), do: error
  defp normalize_membership_create_error({:invalid_role, _} = error), do: error
  defp normalize_membership_create_error({:missing_required_field, _} = error), do: error
  defp normalize_membership_create_error(error), do: error

  defp normalize_user_lookup_error(%Ash.Error.Invalid{errors: errors}, email) do
    if Enum.any?(errors, &match?(%Ash.Error.Query.NotFound{}, &1)) do
      {:error, {:user_not_found, email}}
    else
      {:error, %Ash.Error.Invalid{errors: errors}}
    end
  end

  defp normalize_user_lookup_error(error, _email), do: {:error, error}

  defp wrap_ok({:error, _} = error), do: error
  defp wrap_ok(result), do: {:ok, result}

  defp actor_ash_opts(user, opts) do
    opts
    |> Keyword.put(:actor, user)
    |> ash_opts()
  end

  defp ash_opts(opts) do
    opts = Keyword.drop(opts, [:owner_user])

    cond do
      Keyword.has_key?(opts, :actor) ->
        opts

      Keyword.has_key?(opts, :context) ->
        opts

      true ->
        Keyword.put(opts, :context, %{system: true})
    end
  end

  defp system_ash_opts(opts) do
    opts
    |> Keyword.drop([:owner_user, :actor, :context])
    |> Keyword.put(:context, %{system: true})
  end
end
