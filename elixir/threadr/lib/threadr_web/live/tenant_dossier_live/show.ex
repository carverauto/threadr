defmodule ThreadrWeb.TenantDossierLive.Show do
  use ThreadrWeb, :live_view

  alias Threadr.ControlPlane.Service
  alias Threadr.TenantData.LiveUpdates

  @impl true
  def mount(
        %{"subject_name" => subject_name, "node_kind" => node_kind, "node_id" => node_id},
        _session,
        socket
      ) do
    with {:ok, result} <-
           Service.get_tenant_dossier_for_user(
             socket.assigns.current_user,
             subject_name,
             node_kind,
             node_id
           ) do
      if connected?(socket), do: LiveUpdates.subscribe(subject_name)

      {:ok,
       socket
       |> assign(:tenant, result.tenant)
       |> assign(:membership_role, result.membership.role)
       |> assign(:dossier, result.dossier)}
    else
      {:error, {:resource_not_found, _kind, _id}} ->
        {:ok,
         socket
         |> put_flash(:error, "Dossier target not found")
         |> push_navigate(to: ~p"/control-plane/tenants")}

      {:error, :forbidden} ->
        {:ok,
         socket
         |> put_flash(:error, "You do not have access to that tenant")
         |> push_navigate(to: ~p"/control-plane/tenants")}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Failed to load dossier")
         |> push_navigate(to: ~p"/control-plane/tenants")}
    end
  end

  @impl true
  def handle_info({:tenant_ingest, %{event: :message_persisted} = payload}, socket) do
    if LiveUpdates.relevant_to_dossier?(socket.assigns.dossier, payload) do
      {:noreply, reload_dossier(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <section class="space-y-6">
        <.header>
          Dossier
          <:subtitle>
            Relationship and timeline context for the selected {@dossier.type}.
          </:subtitle>
          <:actions>
            <div class="flex gap-2">
              <.button navigate={~p"/control-plane/tenants"}>Tenants</.button>
              <.button navigate={~p"/control-plane/tenants/#{@tenant.subject_name}/history"}>
                History
              </.button>
              <.button navigate={~p"/control-plane/tenants/#{@tenant.subject_name}/graph"}>
                Graph
              </.button>
            </div>
          </:actions>
        </.header>

        <div class="grid gap-4 lg:grid-cols-[1.2fr_1fr]">
          <div class="card bg-base-100 border border-base-300 shadow-sm">
            <div class="card-body">
              <div class="flex items-center justify-between gap-4">
                <div>
                  <div class="text-sm text-base-content/60">Tenant</div>
                  <div class="font-semibold">{@tenant.name}</div>
                  <div class="text-sm text-base-content/70">{@tenant.subject_name}</div>
                </div>
                <span class="badge badge-outline">{@membership_role}</span>
              </div>

              <div class="mt-4 space-y-2">
                <div class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/50">
                  Focal Record
                </div>
                <div class="rounded-box border border-base-300 bg-base-200 p-4">
                  <div class="text-lg font-semibold">{focal_title(@dossier)}</div>
                  <div class="mt-1 text-sm text-base-content/70">{focal_subtitle(@dossier)}</div>
                </div>
              </div>
            </div>
          </div>

          <div class="card bg-base-200 shadow-sm">
            <div class="card-body">
              <div class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/50">
                Summary
              </div>
              <div class="stats stats-vertical shadow-sm">
                <div :for={{label, value} <- summary_rows(@dossier)} class="stat">
                  <div class="stat-title">{label}</div>
                  <div class="stat-value text-2xl">{value}</div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="grid gap-4 xl:grid-cols-2">
          <div class="card bg-base-100 border border-base-300 shadow-sm">
            <div class="card-body">
              <div class="text-sm font-semibold text-base-content/70">Recent Messages</div>
              <div class="space-y-3">
                <div
                  :for={message <- @dossier.recent_messages || []}
                  id={"dossier-message-#{message["id"] || message[:id]}"}
                  class="rounded-box border border-base-300 bg-base-200 p-3"
                >
                  <div class="flex items-center justify-between gap-3 text-xs text-base-content/60">
                    <span>{message_channel(message)} {message_actor(message)}</span>
                    <span>{format_datetime(message["observed_at"] || message[:observed_at])}</span>
                  </div>
                  <div class="mt-2 text-sm">{message["body"] || message[:body]}</div>
                </div>
                <div
                  :if={Enum.empty?(@dossier.recent_messages || [])}
                  class="text-sm text-base-content/60"
                >
                  No recent messages available.
                </div>
              </div>
            </div>
          </div>

          <div class="card bg-base-100 border border-base-300 shadow-sm">
            <div class="card-body gap-4">
              <div :if={@dossier[:top_relationships]} class="space-y-2">
                <div class="text-sm font-semibold text-base-content/70">Top Relationships</div>
                <div class="space-y-2">
                  <div
                    :for={relationship <- @dossier.top_relationships}
                    class="rounded-box border border-base-300 bg-base-200 p-3 text-sm"
                  >
                    <div class="font-medium">
                      {relationship["to_actor_handle"] || relationship[:to_actor_handle]}
                    </div>
                    <div class="text-xs text-base-content/60">
                      {relationship["relationship"] || relationship[:relationship]} · weight {relationship[
                        "weight"
                      ] || relationship[:weight]}
                    </div>
                  </div>
                </div>
              </div>

              <div :if={@dossier[:top_channels]} class="space-y-2">
                <div class="text-sm font-semibold text-base-content/70">Top Channels</div>
                <div class="space-y-2">
                  <div
                    :for={channel <- @dossier.top_channels}
                    class="rounded-box border border-base-300 bg-base-200 p-3 text-sm"
                  >
                    <div class="font-medium">
                      #{channel["channel_name"] || channel[:channel_name]}
                    </div>
                    <div class="text-xs text-base-content/60">
                      {channel["message_count"] || channel[:message_count]} messages
                    </div>
                  </div>
                </div>
              </div>

              <div :if={@dossier[:top_actors]} class="space-y-2">
                <div class="text-sm font-semibold text-base-content/70">Top Actors</div>
                <div class="space-y-2">
                  <div
                    :for={actor <- @dossier.top_actors}
                    class="rounded-box border border-base-300 bg-base-200 p-3 text-sm"
                  >
                    <div class="font-medium">{actor["actor_handle"] || actor[:actor_handle]}</div>
                    <div class="text-xs text-base-content/60">
                      {actor["message_count"] || actor[:message_count]} messages
                    </div>
                  </div>
                </div>
              </div>

              <div class="space-y-2">
                <div class="text-sm font-semibold text-base-content/70">Neighborhood</div>
                <pre class="whitespace-pre-wrap text-xs leading-6 text-base-content/75">{neighborhood_text(@dossier.neighborhood)}</pre>
              </div>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp focal_title(%{type: "actor", focal: focal}),
    do: focal["display_name"] || focal[:display_name] || focal["handle"] || focal[:handle]

  defp focal_title(%{type: "channel", focal: focal}), do: "##{focal["name"] || focal[:name]}"
  defp focal_title(%{type: "message", focal: focal}), do: focal["body"] || focal[:body]
  defp focal_title(_dossier), do: "Dossier"

  defp focal_subtitle(%{type: "actor", focal: focal}),
    do: "#{focal["platform"] || focal[:platform]} · #{focal["handle"] || focal[:handle]}"

  defp focal_subtitle(%{type: "channel", focal: focal}),
    do: focal["platform"] || focal[:platform] || ""

  defp focal_subtitle(%{type: "message", focal: focal}),
    do: format_datetime(focal["observed_at"] || focal[:observed_at])

  defp focal_subtitle(_dossier), do: ""

  defp summary_rows(dossier) do
    dossier.summary
    |> Enum.map(fn {key, value} ->
      {key |> to_string() |> String.replace("_", " ") |> String.capitalize(), value}
    end)
  end

  defp message_channel(message) do
    case message["channel_name"] || message[:channel_name] do
      nil -> ""
      channel -> "##{channel}"
    end
  end

  defp message_actor(message) do
    message["actor_handle"] || message[:actor_handle] || ""
  end

  defp neighborhood_text(nil), do: "No neighborhood context available."

  defp neighborhood_text(neighborhood) do
    actor_count = length(neighborhood[:actors] || neighborhood["actors"] || [])

    relationship_count =
      length(neighborhood[:relationships] || neighborhood["relationships"] || [])

    message_count = length(neighborhood[:messages] || neighborhood["messages"] || [])

    """
    Actors: #{actor_count}
    Relationships: #{relationship_count}
    Messages: #{message_count}
    """
  end

  defp format_datetime(nil), do: "Unknown time"

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")

  defp format_datetime(%NaiveDateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp format_datetime(value), do: to_string(value)

  defp reload_dossier(socket) do
    dossier = socket.assigns.dossier
    focal = dossier.focal

    case Service.get_tenant_dossier_for_user(
           socket.assigns.current_user,
           socket.assigns.tenant.subject_name,
           dossier.type,
           focal["id"] || focal[:id]
         ) do
      {:ok, result} ->
        assign(socket, :dossier, result.dossier)

      {:error, _reason} ->
        socket
    end
  end
end
