defmodule ThreadrWeb.TenantGraphLive.Index do
  use ThreadrWeb, :live_view

  alias Threadr.ControlPlane.Service
  alias Threadr.TenantData.GraphSnapshot

  @filter_labels %{
    root_cause: "Actors",
    affected: "Channels",
    healthy: "Threads",
    unknown: "Other"
  }

  @impl true
  def mount(%{"subject_name" => subject_name}, _session, socket) do
    case Service.get_user_tenant_by_subject_name(socket.assigns.current_user, subject_name) do
      {:ok, tenant, membership} ->
        {:ok,
         socket
         |> assign(:tenant, tenant)
         |> assign(:membership, membership)
         |> assign(:page_title, "#{tenant.name} Graph")
         |> assign(:filters, %{root_cause: true, affected: true, healthy: true, unknown: true})
         |> assign(:filter_labels, @filter_labels)
         |> assign(:schema_version, GraphSnapshot.schema_version())
         |> assign(:socket_token, Phoenix.Token.sign(ThreadrWeb.Endpoint, "user socket", socket.assigns.current_user.id))}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "You do not have access to that tenant graph")
         |> push_navigate(to: ~p"/control-plane/tenants")}
    end
  end

  @impl true
  def handle_event("toggle_filter", %{"key" => key}, socket) do
    atom_key = String.to_existing_atom(key)
    filters = Map.update!(socket.assigns.filters, atom_key, &(!&1))

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> push_event("tenant_graph:set_filters", %{filters: stringify_keys(filters)})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="space-y-6">
        <.header>
          {@tenant.name} Graph
          <:subtitle>
            Tenant-scoped relationship graph streamed as Arrow and rendered through deck.gl.
          </:subtitle>
          <:actions>
            <div class="flex gap-2">
              <.button navigate={~p"/control-plane/tenants/#{@tenant.subject_name}/qa"}>
                QA Workspace
              </.button>
              <.button navigate={~p"/control-plane/tenants"}>
                Back
              </.button>
            </div>
          </:actions>
        </.header>

        <div class="grid gap-6 xl:grid-cols-[20rem_minmax(0,1fr)]">
          <aside class="space-y-4 rounded-box border border-base-300 bg-base-100 p-4">
            <div>
              <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
                Stream
              </h2>
              <div class="mt-2 text-sm text-base-content/70">
                Tenant subject <span class="font-semibold text-base-content">{@tenant.subject_name}</span>
              </div>
              <div class="text-sm text-base-content/70">
                Schema <span class="font-semibold text-base-content">{@tenant.schema_name}</span>
              </div>
              <div class="text-sm text-base-content/70">
                Graph schema version <span class="font-semibold text-base-content">{@schema_version}</span>
              </div>
            </div>

            <div>
              <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
                Filters
              </h2>
              <div class="mt-3 space-y-2">
                <button
                  :for={{key, label} <- @filter_labels}
                  type="button"
                  class={[
                    "btn btn-sm w-full justify-between",
                    @filters[key] && "btn-primary",
                    !@filters[key] && "btn-ghost"
                  ]}
                  phx-click="toggle_filter"
                  phx-value-key={Atom.to_string(key)}
                >
                  <span>{label}</span>
                  <span class="badge badge-outline">{if @filters[key], do: "on", else: "off"}</span>
                </button>
              </div>
            </div>

            <div class="rounded-box bg-base-200 p-3 text-sm text-base-content/70">
              Click a node to inspect it. Filters apply locally in the client without forcing a
              new snapshot.
            </div>
          </aside>

          <div class="overflow-hidden rounded-box border border-base-300 bg-base-950/95">
            <div
              id="tenant-graph-view"
              phx-hook="TenantGraphExplorer"
              data-socket-token={@socket_token}
              data-topic={"graph:#{@tenant.subject_name}"}
              data-filter-labels={Jason.encode!(@filter_labels)}
              data-initial-filters={Jason.encode!(stringify_keys(@filters))}
              class="h-[72vh] w-full"
            >
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {Atom.to_string(key), value} end)
  end
end
