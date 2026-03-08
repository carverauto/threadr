defmodule ThreadrWeb.TenantGraphLive.Index do
  use ThreadrWeb, :live_view

  alias Threadr.ControlPlane.Service
  alias Threadr.TimeWindow

  @filter_labels %{
    root_cause: "Actors",
    affected: "Channels",
    healthy: "Messages",
    unknown: "Other"
  }
  @zoom_modes ~w(auto global regional local)

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
         |> assign(:edge_layers, %{
           relationship: false,
           conversation: false,
           authored: false,
           in_channel: false
         })
         |> assign(:node_kinds, %{
           actor: false,
           channel: true,
           conversation: false,
           message: false
         })
         |> assign(:relationship_types, %{
           mentioned: true,
           co_mentioned: false,
           active_in: true,
           other: false
         })
         |> assign(:zoom_mode, "local")
         |> assign(:zoom_modes, @zoom_modes)
         |> assign(:since, "")
         |> assign(:until, "")
         |> assign(:compare_since, "")
         |> assign(:compare_until, "")
         |> assign(:focus_node_kind, nil)
         |> assign(:focus_node_id, nil)
         |> assign(
           :socket_token,
           Phoenix.Token.sign(ThreadrWeb.Endpoint, "user socket", socket.assigns.current_user.id)
         )}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "You do not have access to that tenant graph")
         |> push_navigate(to: ~p"/control-plane/tenants")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    baseline_window = time_window_from_params(params, socket.assigns.since, socket.assigns.until)

    comparison_window =
      compare_window_from_params(
        params,
        socket.assigns.compare_since,
        socket.assigns.compare_until
      )

    {:noreply,
     socket
     |> assign_window(:since, :until, baseline_window)
     |> assign_window(:compare_since, :compare_until, comparison_window)
     |> assign(:focus_node_kind, normalize_focus_value(Map.get(params, "node_kind")))
     |> assign(:focus_node_id, normalize_focus_value(Map.get(params, "node_id")))}
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

  def handle_event("toggle_edge_layer", %{"key" => key}, socket) do
    atom_key = String.to_existing_atom(key)
    edge_layers = Map.update!(socket.assigns.edge_layers, atom_key, &(!&1))

    {:noreply,
     socket
     |> assign(:edge_layers, edge_layers)
     |> push_event("tenant_graph:set_edge_layers", %{layers: stringify_keys(edge_layers)})}
  end

  def handle_event("set_zoom_mode", %{"mode" => mode}, socket) do
    zoom_mode =
      if mode in @zoom_modes do
        mode
      else
        "auto"
      end

    {:noreply,
     socket
     |> assign(:zoom_mode, zoom_mode)
     |> push_event("tenant_graph:set_zoom_mode", %{mode: zoom_mode})}
  end

  def handle_event("toggle_node_kind", %{"key" => key}, socket) do
    atom_key = String.to_existing_atom(key)
    node_kinds = Map.update!(socket.assigns.node_kinds, atom_key, &(!&1))

    {:noreply,
     socket
     |> assign(:node_kinds, node_kinds)
     |> push_event("tenant_graph:set_node_kinds", %{node_kinds: stringify_keys(node_kinds)})}
  end

  def handle_event("toggle_relationship_type", %{"key" => key}, socket) do
    atom_key = String.to_existing_atom(key)
    relationship_types = Map.update!(socket.assigns.relationship_types, atom_key, &(!&1))

    {:noreply,
     socket
     |> assign(:relationship_types, relationship_types)
     |> push_event("tenant_graph:set_relationship_types", %{
       relationship_types: stringify_keys(relationship_types)
     })}
  end

  def handle_event("change_window", params, socket) do
    {:noreply,
     socket
     |> assign(:since, normalize_blank(Map.get(params, "since")))
     |> assign(:until, normalize_blank(Map.get(params, "until")))
     |> assign(:compare_since, normalize_blank(Map.get(params, "compare_since")))
     |> assign(:compare_until, normalize_blank(Map.get(params, "compare_until")))}
  end

  def handle_event("apply_window", _params, socket) do
    params =
      %{}
      |> Map.merge(window_params(baseline_window(socket)))
      |> Map.merge(window_params(comparison_window(socket), :compare))
      |> put_param_if_present("node_kind", socket.assigns.focus_node_kind)
      |> put_param_if_present("node_id", socket.assigns.focus_node_id)

    {:noreply,
     push_patch(
       socket,
       to: ~p"/control-plane/tenants/#{socket.assigns.tenant.subject_name}/graph?#{params}"
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="space-y-6">
        <.header>
          {@tenant.name} Graph
          <:subtitle>
            Investigate one bounded relationship neighborhood, then pivot into history, dossiers, or QA.
          </:subtitle>
          <:actions>
            <div class="flex gap-2">
              <.button navigate={
                ~p"/control-plane/tenants/#{@tenant.subject_name}/history?#{history_link_params(assigns)}"
              }>
                History
              </.button>
              <.button navigate={
                ~p"/control-plane/tenants/#{@tenant.subject_name}/qa?#{qa_link_params(assigns)}"
              }>
                QA Workspace
              </.button>
              <.button navigate={~p"/control-plane/tenants"}>
                Back
              </.button>
            </div>
          </:actions>
        </.header>

        <div class="grid gap-6 xl:grid-cols-[18rem_minmax(0,1fr)]">
          <aside class="min-w-0 space-y-4 rounded-box border border-base-300 bg-base-100 p-4">
            <div>
              <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
                Investigation Window
              </h2>
              <.form
                id="graph-window-form"
                class="mt-3 space-y-2"
                for={%{}}
                phx-change="change_window"
                phx-submit="apply_window"
              >
                <input
                  id="graph-since"
                  name="since"
                  type="datetime-local"
                  class="input input-bordered w-full"
                  value={@since}
                />
                <input
                  id="graph-until"
                  name="until"
                  type="datetime-local"
                  class="input input-bordered w-full"
                  value={@until}
                />
                <.button id="graph-apply-window" class="btn-sm w-full">Apply Window</.button>
              </.form>
            </div>

            <div>
              <div
                id="graph-selection-panel"
                class="min-h-56 max-h-[52vh] min-w-0 space-y-3 overflow-x-hidden overflow-y-auto break-words rounded-box bg-base-200 p-3 text-sm text-base-content/75"
              >
                <div class="font-semibold text-base-content">Selection</div>
                <div>No node selected.</div>
              </div>
            </div>
          </aside>

          <div class="overflow-hidden rounded-box border border-base-300 bg-base-950/95">
            <div
              id="tenant-graph-view"
              phx-hook="TenantGraphExplorer"
              data-socket-token={@socket_token}
              data-topic={"graph:#{@tenant.subject_name}"}
              data-subject-name={@tenant.subject_name}
              data-focus-node-kind={@focus_node_kind}
              data-focus-node-id={@focus_node_id}
              data-since={@since}
              data-until={@until}
              data-compare-since={@compare_since}
              data-compare-until={@compare_until}
              data-details-panel-id="graph-selection-panel"
              data-filter-labels={Jason.encode!(@filter_labels)}
              data-initial-filters={Jason.encode!(stringify_keys(@filters))}
              data-initial-zoom-mode={@zoom_mode}
              data-initial-edge-layers={Jason.encode!(stringify_keys(@edge_layers))}
              data-initial-node-kinds={Jason.encode!(stringify_keys(@node_kinds))}
              data-initial-relationship-types={Jason.encode!(stringify_keys(@relationship_types))}
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

  defp normalize_focus_value(nil), do: nil

  defp normalize_focus_value(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_blank(nil), do: ""
  defp normalize_blank(""), do: ""

  defp normalize_blank(value) do
    value
    |> to_string()
    |> String.trim()
  end

  defp baseline_window(socket) do
    TimeWindow.new(
      since: parse_naive_datetime(socket.assigns.since),
      until: parse_naive_datetime(socket.assigns.until)
    )
  end

  defp comparison_window(socket) do
    TimeWindow.new(
      since: parse_naive_datetime(socket.assigns.compare_since),
      until: parse_naive_datetime(socket.assigns.compare_until)
    )
  end

  defp time_window_from_params(params, fallback_since, fallback_until) do
    TimeWindow.new(
      since: parse_naive_datetime(Map.get(params, "since", fallback_since)),
      until: parse_naive_datetime(Map.get(params, "until", fallback_until))
    )
  end

  defp compare_window_from_params(params, fallback_since, fallback_until) do
    TimeWindow.new(
      since: parse_naive_datetime(Map.get(params, "compare_since", fallback_since)),
      until: parse_naive_datetime(Map.get(params, "compare_until", fallback_until))
    )
  end

  defp assign_window(socket, since_key, until_key, %TimeWindow{} = window) do
    socket
    |> assign(since_key, format_window_value(window.since))
    |> assign(until_key, format_window_value(window.until))
  end

  defp history_link_params(assigns) do
    %{}
    |> Map.merge(window_params(baseline_window(%{assigns: assigns})))
    |> Map.merge(window_params(comparison_window(%{assigns: assigns}), :compare))
  end

  defp qa_link_params(assigns), do: history_link_params(assigns)

  defp window_params(%TimeWindow{} = window, prefix \\ nil) do
    window
    |> TimeWindow.to_map()
    |> Enum.reduce(%{}, fn
      {:since, nil}, acc ->
        acc

      {:until, nil}, acc ->
        acc

      {:since, value}, acc ->
        Map.put(acc, window_param_key(prefix, :since), format_window_value(value))

      {:until, value}, acc ->
        Map.put(acc, window_param_key(prefix, :until), format_window_value(value))
    end)
  end

  defp window_param_key(nil, :since), do: "since"
  defp window_param_key(nil, :until), do: "until"
  defp window_param_key(:compare, :since), do: "compare_since"
  defp window_param_key(:compare, :until), do: "compare_until"

  defp format_window_value(nil), do: ""
  defp format_window_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp format_window_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp format_window_value(value), do: to_string(value)

  defp parse_naive_datetime(nil), do: nil
  defp parse_naive_datetime(""), do: nil

  defp parse_naive_datetime(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, datetime} -> datetime
      _ -> nil
    end
  end

  defp put_param_if_present(params, _key, value) when value in [nil, ""], do: params
  defp put_param_if_present(params, key, value), do: Map.put(params, key, value)
end
