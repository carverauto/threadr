defmodule ThreadrWeb.TenantLive.Index do
  use ThreadrWeb, :live_view

  alias Threadr.ControlPlane.Service

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :tenants, load_tenants(socket.assigns.current_user))}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, assign(socket, :tenants, load_tenants(socket.assigns.current_user))}
  end

  def handle_event("migrate", %{"subject_name" => subject_name}, socket) do
    socket =
      case Service.migrate_tenant_for_user(socket.assigns.current_user, subject_name) do
        {:ok, result} ->
          socket
          |> put_flash(:info, "Migration completed for #{result.subject_name}")
          |> assign(:tenants, load_tenants(socket.assigns.current_user))

        {:error, {:tenant_not_found, _}} ->
          socket
          |> put_flash(:error, "Tenant not found")
          |> assign(:tenants, load_tenants(socket.assigns.current_user))

        {:error, :forbidden} ->
          socket
          |> put_flash(:error, "You do not have permission to migrate that tenant")
          |> assign(:tenants, load_tenants(socket.assigns.current_user))

        {:error, reason} ->
          socket
          |> put_flash(:error, "Migration failed: #{inspect(reason)}")
          |> assign(:tenants, load_tenants(socket.assigns.current_user))
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="space-y-6">
        <.header>
          Control Plane
          <:subtitle>
            Tenant schemas, upgrade state, and manual tenant migration control.
          </:subtitle>
          <:actions>
            <div class="flex gap-2">
              <.button navigate={~p"/settings/api-keys"}>API Keys</.button>
              <.button phx-click="refresh">Refresh</.button>
            </div>
          </:actions>
        </.header>

        <div class="text-sm text-base-content/70">
          Signed in as <span class="font-semibold">{@current_user.email}</span>
        </div>

        <div class="stats stats-vertical lg:stats-horizontal shadow-sm bg-base-200 w-full">
          <div class="stat">
            <div class="stat-title">Tenants</div>
            <div class="stat-value text-3xl">{length(@tenants)}</div>
          </div>
          <div class="stat">
            <div class="stat-title">Latest Tenant Migration</div>
            <div class="stat-value text-3xl">{Service.latest_tenant_migration_version() || "-"}</div>
          </div>
        </div>

        <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
          <.table id="tenants" rows={@tenants} row_id={&"tenant-#{&1.id}"}>
            <:col :let={tenant} label="Tenant">
              <div class="font-semibold">{tenant.name}</div>
              <div class="text-xs text-base-content/60">{tenant.id}</div>
            </:col>
            <:col :let={tenant} label="Routing">
              <div>{tenant.subject_name}</div>
              <div class="text-xs text-base-content/60">{tenant.schema_name}</div>
            </:col>
            <:col :let={tenant} label="Tenant Status">
              <span class={badge_class(tenant.status)}>{tenant.status}</span>
            </:col>
            <:col :let={tenant} label="Role">
              <span class="badge badge-outline">{tenant.membership_role}</span>
            </:col>
            <:col :let={tenant} label="Migration">
              <div class="flex items-center gap-2">
                <span class={badge_class(tenant.tenant_migration_status)}>
                  {tenant.tenant_migration_status}
                </span>
                <span class="text-sm text-base-content/70">
                  v{tenant.tenant_migration_version || "-"}
                </span>
              </div>
              <div class="text-xs text-base-content/60">
                {format_datetime(tenant.tenant_migrated_at)}
              </div>
              <div :if={tenant.tenant_migration_error} class="text-xs text-error mt-1">
                {tenant.tenant_migration_error}
              </div>
            </:col>
            <:action :let={tenant}>
              <.button
                class="btn btn-sm"
                navigate={~p"/control-plane/tenants/#{tenant.subject_name}/qa"}
              >
                Workspace
              </.button>
            </:action>
            <:action :let={tenant}>
              <.button
                :if={Service.manager_role?(tenant.membership_role)}
                class="btn btn-sm btn-primary"
                phx-click="migrate"
                phx-value-subject_name={tenant.subject_name}
                data-role="migrate-tenant"
                data-subject-name={tenant.subject_name}
              >
                Migrate
              </.button>
            </:action>
          </.table>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp load_tenants(current_user) do
    case Service.list_user_memberships(current_user) do
      {:ok, memberships} ->
        memberships
        |> Enum.map(fn membership ->
          membership.tenant
          |> Map.from_struct()
          |> Map.put(:membership_role, membership.role)
        end)
        |> Enum.sort_by(& &1.subject_name)

      {:error, _reason} ->
        []
    end
  end

  defp format_datetime(nil), do: "Never"

  defp format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp badge_class("active"), do: "badge badge-success badge-outline"
  defp badge_class("succeeded"), do: "badge badge-success"
  defp badge_class("running"), do: "badge badge-warning"
  defp badge_class("reconciling"), do: "badge badge-info"
  defp badge_class("stopped"), do: "badge badge-neutral"
  defp badge_class("degraded"), do: "badge badge-warning badge-outline"
  defp badge_class("deleting"), do: "badge badge-error badge-outline"
  defp badge_class("pending"), do: "badge badge-ghost"
  defp badge_class("failed"), do: "badge badge-error"
  defp badge_class(_status), do: "badge badge-neutral"
end
