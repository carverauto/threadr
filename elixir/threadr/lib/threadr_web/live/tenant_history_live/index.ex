defmodule ThreadrWeb.TenantHistoryLive.Index do
  use ThreadrWeb, :live_view

  alias Threadr.ControlPlane.Service
  alias Threadr.TenantData.LiveUpdates

  @default_filters %{
    "query" => "",
    "actor_handle" => "",
    "channel_name" => "",
    "since" => "",
    "until" => "",
    "limit" => "50"
  }

  @impl true
  def mount(%{"subject_name" => subject_name}, _session, socket) do
    with {:ok, tenant, membership} <-
           Service.get_user_tenant_by_subject_name(socket.assigns.current_user, subject_name),
         {:ok, listing} <-
           load_history(socket.assigns.current_user, subject_name, @default_filters) do
      if connected?(socket), do: LiveUpdates.subscribe(subject_name)

      {:ok,
       socket
       |> assign(:tenant, tenant)
       |> assign(:membership_role, membership.role)
       |> assign(:filters, @default_filters)
       |> assign(:messages, listing.messages)}
    else
      {:error, :forbidden} ->
        {:ok,
         socket
         |> put_flash(:error, "You do not have access to that tenant")
         |> push_navigate(to: ~p"/control-plane/tenants")}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Tenant not found")
         |> push_navigate(to: ~p"/control-plane/tenants")}
    end
  end

  @impl true
  def handle_event("change_filters", params, socket) do
    filters = normalize_filters(params)

    socket =
      case load_history(socket.assigns.current_user, socket.assigns.tenant.subject_name, filters) do
        {:ok, listing} ->
          socket
          |> assign(:filters, filters)
          |> assign(:messages, listing.messages)
          |> clear_flash()

        {:error, message} ->
          socket
          |> assign(:filters, filters)
          |> put_flash(:error, message)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:tenant_ingest, %{event: :message_persisted}}, socket) do
    {:noreply, reload_history(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <section class="space-y-6">
        <.header>
          Tenant History
          <:subtitle>
            Time-ordered chat observations for {@tenant.name}. Filter by actor, channel, text, and time window.
          </:subtitle>
          <:actions>
            <div class="flex gap-2">
              <.button navigate={~p"/control-plane/tenants"}>Tenants</.button>
              <.button navigate={~p"/control-plane/tenants/#{@tenant.subject_name}/qa"}>QA</.button>
              <.button navigate={~p"/control-plane/tenants/#{@tenant.subject_name}/graph"}>
                Graph
              </.button>
            </div>
          </:actions>
        </.header>

        <div class="grid gap-4 lg:grid-cols-[1.3fr_1fr]">
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

              <form
                id="tenant-history-form"
                phx-change="change_filters"
                class="grid gap-4 md:grid-cols-2 xl:grid-cols-3"
              >
                <.input
                  name="query"
                  label="Body Contains"
                  value={@filters["query"]}
                  placeholder="alice bob payroll"
                />
                <.input
                  name="actor_handle"
                  label="Actor"
                  value={@filters["actor_handle"]}
                  placeholder="alice"
                />
                <.input
                  name="channel_name"
                  label="Channel"
                  value={@filters["channel_name"]}
                  placeholder="ops"
                />
                <.input name="since" type="datetime-local" label="Since" value={@filters["since"]} />
                <.input name="until" type="datetime-local" label="Until" value={@filters["until"]} />
                <.input
                  name="limit"
                  type="number"
                  min="1"
                  max="200"
                  label="Rows"
                  value={@filters["limit"]}
                />
              </form>
            </div>
          </div>

          <div class="card bg-base-200 shadow-sm">
            <div class="card-body">
              <div class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/60">
                Timeline Summary
              </div>
              <div class="stats stats-vertical shadow-sm">
                <div class="stat">
                  <div class="stat-title">Visible Messages</div>
                  <div class="stat-value text-3xl">{length(@messages)}</div>
                </div>
                <div class="stat">
                  <div class="stat-title">Actors</div>
                  <div class="stat-value text-2xl">{unique_count(@messages, :actor_id)}</div>
                </div>
                <div class="stat">
                  <div class="stat-title">Channels</div>
                  <div class="stat-value text-2xl">{unique_count(@messages, :channel_id)}</div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="space-y-3">
          <div
            :for={message <- @messages}
            id={"history-message-#{message.id}"}
            class="rounded-box border border-base-300 bg-base-100 p-4 shadow-sm"
          >
            <div class="flex flex-wrap items-center justify-between gap-3">
              <div class="flex flex-wrap items-center gap-2 text-sm">
                <.link
                  navigate={
                    ~p"/control-plane/tenants/#{@tenant.subject_name}/dossiers/actor/#{message.actor_id}"
                  }
                  class="font-semibold link link-hover"
                >
                  {message.actor_handle}
                </.link>
                <span class="text-base-content/50">in</span>
                <.link
                  navigate={
                    ~p"/control-plane/tenants/#{@tenant.subject_name}/dossiers/channel/#{message.channel_id}"
                  }
                  class="link link-hover"
                >
                  #{message.channel_name}
                </.link>
              </div>
              <div class="text-xs text-base-content/60">
                {format_datetime(message.observed_at)}
              </div>
            </div>

            <div class="mt-3 text-sm leading-6 text-base-content/90">
              {message.body}
            </div>

            <div class="mt-3 flex flex-wrap gap-2">
              <.link
                navigate={
                  ~p"/control-plane/tenants/#{@tenant.subject_name}/dossiers/message/#{message.id}"
                }
                class="btn btn-ghost btn-xs"
              >
                Message Dossier
              </.link>
            </div>
          </div>

          <div
            :if={@messages == []}
            class="rounded-box border border-dashed border-base-300 bg-base-100 p-8 text-center text-sm text-base-content/60"
          >
            No messages matched the current filters.
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp load_history(user, subject_name, filters) do
    case Service.list_tenant_messages_for_user(user, subject_name, history_opts(filters)) do
      {:ok, listing} -> {:ok, listing}
      {:error, reason} -> {:error, history_error(reason)}
    end
  end

  defp normalize_filters(params) do
    @default_filters
    |> Map.merge(Map.take(params, Map.keys(@default_filters)))
    |> Enum.into(%{}, fn {key, value} -> {key, normalize_blank(value)} end)
  end

  defp history_opts(filters) do
    []
    |> put_opt(:query, filters["query"])
    |> put_opt(:actor_handle, filters["actor_handle"])
    |> put_opt(:channel_name, filters["channel_name"])
    |> put_opt(:since, parse_naive_datetime(filters["since"]))
    |> put_opt(:until, parse_naive_datetime(filters["until"]))
    |> put_opt(:limit, filters["limit"])
  end

  defp put_opt(opts, _key, nil), do: opts
  defp put_opt(opts, _key, ""), do: opts
  defp put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp normalize_blank(nil), do: ""
  defp normalize_blank(value), do: value |> to_string() |> String.trim()

  defp parse_naive_datetime(""), do: nil
  defp parse_naive_datetime(nil), do: nil

  defp parse_naive_datetime(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, datetime} -> datetime
      _ -> nil
    end
  end

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")

  defp format_datetime(%NaiveDateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp format_datetime(value), do: to_string(value)

  defp unique_count(messages, key) do
    messages
    |> Enum.map(&Map.get(&1, key))
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
    |> MapSet.size()
  end

  defp history_error({:tenant_not_found, _}), do: "Tenant not found"
  defp history_error(:forbidden), do: "You do not have access to that tenant"
  defp history_error(reason), do: "Failed to load tenant history: #{inspect(reason)}"

  defp reload_history(socket) do
    case load_history(
           socket.assigns.current_user,
           socket.assigns.tenant.subject_name,
           socket.assigns.filters
         ) do
      {:ok, listing} ->
        socket
        |> assign(:messages, listing.messages)
        |> clear_flash()

      {:error, message} ->
        put_flash(socket, :error, message)
    end
  end
end
