defmodule ThreadrWeb.TenantHistoryLive.Index do
  use ThreadrWeb, :live_view

  alias Threadr.ControlPlane.Service
  alias Threadr.TenantData.LiveUpdates

  @default_filters %{
    "query" => "",
    "actor_handle" => "",
    "channel_name" => "",
    "entity_name" => "",
    "entity_type" => "",
    "fact_type" => "",
    "since" => "",
    "until" => "",
    "compare_since" => "",
    "compare_until" => "",
    "limit" => "50"
  }

  @origin_keys ~w(origin_surface origin_question origin_node_kind origin_node_id origin_since origin_until origin_compare_since origin_compare_until)

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
       |> assign(:messages, listing.messages)
       |> assign(:facts_over_time, listing.facts_over_time)
       |> assign(:comparison_result, nil)
       |> assign(:origin_context, %{})}
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
          |> assign(:facts_over_time, listing.facts_over_time)
          |> clear_flash()

        {:error, message} ->
          socket
          |> assign(:filters, filters)
          |> put_flash(:error, message)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("compare_windows", _params, socket) do
    filters = socket.assigns.filters

    case Service.compare_tenant_history_windows_for_user(
           socket.assigns.current_user,
           socket.assigns.tenant.subject_name,
           history_compare_opts(filters)
         ) do
      {:ok, result} ->
        {:noreply, socket |> assign(:comparison_result, result) |> clear_flash()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "History comparison failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = normalize_filters(params)
    origin_context = Map.take(params, @origin_keys)

    socket =
      case load_history(socket.assigns.current_user, socket.assigns.tenant.subject_name, filters) do
        {:ok, listing} ->
          socket
          |> assign(:filters, filters)
          |> assign(:messages, listing.messages)
          |> assign(:facts_over_time, listing.facts_over_time)
          |> assign(:origin_context, origin_context)
          |> clear_flash()

        {:error, message} ->
          socket
          |> assign(:filters, filters)
          |> assign(:origin_context, origin_context)
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
              <.button
                :if={back_path(@tenant.subject_name, @origin_context)}
                navigate={back_path(@tenant.subject_name, @origin_context)}
              >
                Back to Comparison
              </.button>
              <.button navigate={
                ~p"/control-plane/tenants/#{@tenant.subject_name}/qa?#{qa_params(@filters, qa_question(@filters))}"
              }>
                Ask in QA
              </.button>
              <.button
                :if={compare_window_present?(@filters)}
                navigate={
                  ~p"/control-plane/tenants/#{@tenant.subject_name}/qa?#{qa_params(@filters, qa_compare_question(@filters))}"
                }
              >
                Compare in QA
              </.button>
              <.button navigate={~p"/control-plane/tenants/#{@tenant.subject_name}/graph?#{graph_params(nil, nil, @filters)}"}>
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
                <.input
                  name="entity_name"
                  label="Entity"
                  value={@filters["entity_name"]}
                  placeholder="alice"
                />
                <.input
                  name="entity_type"
                  label="Entity Type"
                  value={@filters["entity_type"]}
                  placeholder="person"
                />
                <.input
                  name="fact_type"
                  label="Fact Type"
                  value={@filters["fact_type"]}
                  placeholder="access_statement"
                />
                <.input name="since" type="datetime-local" label="Since" value={@filters["since"]} />
                <.input name="until" type="datetime-local" label="Until" value={@filters["until"]} />
                <.input
                  name="compare_since"
                  type="datetime-local"
                  label="Compare Since"
                  value={@filters["compare_since"]}
                />
                <.input
                  name="compare_until"
                  type="datetime-local"
                  label="Compare Until"
                  value={@filters["compare_until"]}
                />
                <.input
                  name="limit"
                  type="number"
                  min="1"
                  max="200"
                  label="Rows"
                  value={@filters["limit"]}
                />
              </form>

              <div class="mt-4 flex justify-end">
                <button
                  id="tenant-history-compare-submit"
                  type="button"
                  phx-click="compare_windows"
                  class="btn btn-outline btn-sm"
                >
                  Compare Windows
                </button>
              </div>
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
                <div class="stat">
                  <div class="stat-title">Facts</div>
                  <div class="stat-value text-2xl">{fact_count(@messages)}</div>
                </div>
              </div>

              <div class="mt-4 space-y-2">
                <div class="text-sm font-semibold text-base-content/70">Facts Over Time</div>
                <div :if={@facts_over_time == []} class="text-sm text-base-content/60">
                  No extracted facts matched the current filters.
                </div>
                <div
                  :for={entry <- @facts_over_time}
                  class="rounded-box border border-base-300 bg-base-100 p-3 text-sm"
                >
                  <div class="flex items-center justify-between gap-3">
                    <div class="font-medium">{Date.to_iso8601(entry.day)}</div>
                    <div class="text-xs text-base-content/60">
                      {entry.fact_count} facts · {entry.fact_type_count} types
                    </div>
                  </div>
                  <div class="mt-1 text-xs text-base-content/70">
                    Top fact: {entry.top_fact} ({entry.top_fact_count})
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div :if={@comparison_result} class="card bg-base-100 border border-base-300 shadow-sm">
          <div class="card-body space-y-4">
            <div class="text-sm font-semibold text-base-content/70">Comparison Summary</div>
            <div class="rounded-box border border-base-300 bg-base-200 p-4 text-sm whitespace-pre-wrap">
              {@comparison_result.answer.content}
            </div>

            <div class="grid gap-4 xl:grid-cols-2">
              <div class="rounded-box border border-base-300 bg-base-200 p-4">
                <div class="text-sm font-semibold text-base-content/70">Entity Delta</div>
                <.entity_delta_panel
                  id="history-entity-delta"
                  delta={@comparison_result.comparison.entity_delta}
                  tenant_subject_name={@tenant.subject_name}
                  baseline_window={%{since: @filters["since"], until: @filters["until"]}}
                  comparison_window={
                    %{since: @filters["compare_since"], until: @filters["compare_until"]}
                  }
                />
              </div>
              <div class="rounded-box border border-base-300 bg-base-200 p-4">
                <div class="text-sm font-semibold text-base-content/70">Fact Delta</div>
                <.fact_delta_panel
                  id="history-fact-delta"
                  delta={@comparison_result.comparison.fact_delta}
                  tenant_subject_name={@tenant.subject_name}
                  baseline_window={%{since: @filters["since"], until: @filters["until"]}}
                  comparison_window={
                    %{since: @filters["compare_since"], until: @filters["compare_until"]}
                  }
                />
              </div>
            </div>

            <div class="grid gap-4 xl:grid-cols-2">
              <div class="space-y-2">
                <div class="text-sm font-semibold text-base-content/70">Baseline Window</div>
                <div class="rounded-box border border-base-300 bg-base-200 p-3 text-sm">
                  <div class="font-medium">
                    {window_label(@filters["since"], @filters["until"])}
                  </div>
                  <div class="mt-1 text-xs text-base-content/60">
                    {length(@comparison_result.comparison.baseline.messages)} messages · {length(
                      @comparison_result.comparison.baseline.facts_over_time
                    )} daily fact buckets
                  </div>
                </div>
                <div
                  :for={message <- Enum.take(@comparison_result.comparison.baseline.messages, 5)}
                  class="rounded-box border border-base-300 bg-base-100 p-3 text-sm"
                >
                  <div class="font-medium">{message.actor_handle} in #{message.channel_name}</div>
                  <div class="text-xs text-base-content/60">
                    {format_datetime(message.observed_at)}
                  </div>
                  <div class="mt-1">{message.body}</div>
                </div>
              </div>

              <div class="space-y-2">
                <div class="text-sm font-semibold text-base-content/70">Comparison Window</div>
                <div class="rounded-box border border-base-300 bg-base-200 p-3 text-sm">
                  <div class="font-medium">
                    {window_label(@filters["compare_since"], @filters["compare_until"])}
                  </div>
                  <div class="mt-1 text-xs text-base-content/60">
                    {length(@comparison_result.comparison.comparison.messages)} messages · {length(
                      @comparison_result.comparison.comparison.facts_over_time
                    )} daily fact buckets
                  </div>
                </div>
                <div
                  :for={message <- Enum.take(@comparison_result.comparison.comparison.messages, 5)}
                  class="rounded-box border border-base-300 bg-base-100 p-3 text-sm"
                >
                  <div class="font-medium">{message.actor_handle} in #{message.channel_name}</div>
                  <div class="text-xs text-base-content/60">
                    {format_datetime(message.observed_at)}
                  </div>
                  <div class="mt-1">{message.body}</div>
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

            <div
              :if={message.extracted_entities != [] or message.extracted_facts != []}
              class="mt-3 space-y-2"
            >
              <div :if={message.extracted_entities != []} class="flex flex-wrap gap-2">
                <span
                  :for={entity <- message.extracted_entities}
                  class="badge badge-outline badge-sm"
                >
                  {entity.entity_type}: {entity.canonical_name || entity.name}
                </span>
              </div>

              <div :if={message.extracted_facts != []} class="space-y-1">
                <div
                  :for={fact <- message.extracted_facts}
                  class="rounded-box bg-base-200 px-3 py-2 text-xs text-base-content/80"
                >
                  <span class="font-medium">{fact.subject}</span>
                  <span>{fact.predicate}</span>
                  <span class="font-medium">{fact.object}</span>
                  <span class="text-base-content/50">
                    ({fact.fact_type}{if fact.valid_at, do: " · " <> fact.valid_at, else: ""})
                  </span>
                </div>
              </div>
            </div>

            <div class="mt-3 flex flex-wrap gap-2">
              <.link
                navigate={
                  ~p"/control-plane/tenants/#{@tenant.subject_name}/graph?#{graph_params("actor", message.actor_id, @filters)}"
                }
                class="btn btn-ghost btn-xs"
              >
                Actor in Graph
              </.link>
              <.link
                navigate={
                  ~p"/control-plane/tenants/#{@tenant.subject_name}/graph?#{graph_params("channel", message.channel_id, @filters)}"
                }
                class="btn btn-ghost btn-xs"
              >
                Channel in Graph
              </.link>
              <.link
                navigate={
                  ~p"/control-plane/tenants/#{@tenant.subject_name}/graph?#{graph_params("message", message.id, @filters)}"
                }
                class="btn btn-ghost btn-xs"
              >
                Message in Graph
              </.link>
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
    |> put_opt(:entity_name, filters["entity_name"])
    |> put_opt(:entity_type, filters["entity_type"])
    |> put_opt(:fact_type, filters["fact_type"])
    |> put_opt(:since, parse_naive_datetime(filters["since"]))
    |> put_opt(:until, parse_naive_datetime(filters["until"]))
    |> put_opt(:limit, filters["limit"])
  end

  defp history_compare_opts(filters) do
    history_opts(filters)
    |> put_opt(:compare_since, parse_naive_datetime(filters["compare_since"]))
    |> put_opt(:compare_until, parse_naive_datetime(filters["compare_until"]))
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

  defp window_label("", ""), do: "beginning/end"
  defp window_label(nil, nil), do: "beginning/end"

  defp window_label(since, until),
    do: "#{blank_window_value(since)} -> #{blank_window_value(until)}"

  defp blank_window_value(nil), do: "beginning/end"
  defp blank_window_value(""), do: "beginning/end"
  defp blank_window_value(value), do: value

  attr(:id, :string, required: true)
  attr(:delta, :map, required: true)
  attr(:tenant_subject_name, :string, required: true)
  attr(:baseline_window, :map, required: true)
  attr(:comparison_window, :map, required: true)

  defp entity_delta_panel(assigns) do
    ~H"""
    <div id={@id} class="mt-2 space-y-2 text-sm">
      <div class="text-xs text-base-content/60">Unchanged: {@delta.unchanged}</div>
      <div>
        <div class="text-xs font-semibold text-success">New People</div>
        <div :if={@delta.highlights.new_people == []} class="text-xs text-base-content/60">none</div>
        <.link
          :for={entry <- @delta.highlights.new_people}
          navigate={
            ~p"/control-plane/tenants/#{@tenant_subject_name}/history?#{history_entity_params(@comparison_window, entry)}"
          }
          class="block text-xs link link-hover"
        >
          {entry.label} ({entry.count})
        </.link>
      </div>
      <div>
        <div class="text-xs font-semibold text-error">Removed People</div>
        <div :if={@delta.highlights.removed_people == []} class="text-xs text-base-content/60">
          none
        </div>
        <.link
          :for={entry <- @delta.highlights.removed_people}
          navigate={
            ~p"/control-plane/tenants/#{@tenant_subject_name}/history?#{history_entity_params(@baseline_window, entry)}"
          }
          class="block text-xs link link-hover"
        >
          {entry.label} ({entry.count})
        </.link>
      </div>
      <div>
        <div class="text-xs font-semibold">Entity Types</div>
        <div
          :if={@delta.added_by_type == [] and @delta.removed_by_type == []}
          class="text-xs text-base-content/60"
        >
          none
        </div>
        <div :for={entry <- @delta.added_by_type} class="text-xs text-success">
          + {entry.type} ({entry.count})
        </div>
        <div :for={entry <- @delta.removed_by_type} class="text-xs text-error">
          - {entry.type} ({entry.count})
        </div>
      </div>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:delta, :map, required: true)
  attr(:tenant_subject_name, :string, required: true)
  attr(:baseline_window, :map, required: true)
  attr(:comparison_window, :map, required: true)

  defp fact_delta_panel(assigns) do
    ~H"""
    <div id={@id} class="mt-2 space-y-2 text-sm">
      <div class="text-xs text-base-content/60">Unchanged: {@delta.unchanged}</div>
      <div>
        <div class="text-xs font-semibold text-success">New Claims</div>
        <div :if={@delta.highlights.new_claims == []} class="text-xs text-base-content/60">none</div>
        <.link
          :for={entry <- @delta.highlights.new_claims}
          navigate={
            ~p"/control-plane/tenants/#{@tenant_subject_name}/history?#{history_fact_params(@comparison_window, entry)}"
          }
          class="block text-xs link link-hover"
        >
          {entry.label} ({entry.count})
        </.link>
      </div>
      <div>
        <div class="text-xs font-semibold text-error">Dropped Claims</div>
        <div :if={@delta.highlights.dropped_claims == []} class="text-xs text-base-content/60">
          none
        </div>
        <.link
          :for={entry <- @delta.highlights.dropped_claims}
          navigate={
            ~p"/control-plane/tenants/#{@tenant_subject_name}/history?#{history_fact_params(@baseline_window, entry)}"
          }
          class="block text-xs link link-hover"
        >
          {entry.label} ({entry.count})
        </.link>
      </div>
      <div>
        <div class="text-xs font-semibold">By Subject</div>
        <div
          :if={@delta.added_by_subject == [] and @delta.removed_by_subject == []}
          class="text-xs text-base-content/60"
        >
          none
        </div>
        <div :for={entry <- @delta.added_by_subject} class="text-xs text-success">
          + {entry.subject} ({entry.count})
        </div>
        <div :for={entry <- @delta.removed_by_subject} class="text-xs text-error">
          - {entry.subject} ({entry.count})
        </div>
      </div>
    </div>
    """
  end

  defp unique_count(messages, key) do
    messages
    |> Enum.map(&Map.get(&1, key))
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
    |> MapSet.size()
  end

  defp fact_count(messages) do
    messages
    |> Enum.flat_map(&Map.get(&1, :extracted_facts, []))
    |> length()
  end

  defp history_error({:tenant_not_found, _}), do: "Tenant not found"
  defp history_error(:forbidden), do: "You do not have access to that tenant"
  defp history_error(reason), do: "Failed to load tenant history: #{inspect(reason)}"

  defp back_path(_tenant_subject_name, %{} = origin_context) when map_size(origin_context) == 0,
    do: nil

  defp back_path(tenant_subject_name, %{"origin_surface" => "qa"} = origin_context) do
    ~p"/control-plane/tenants/#{tenant_subject_name}/qa?#{%{question: origin_context["origin_question"], since: origin_context["origin_since"], until: origin_context["origin_until"], compare_since: origin_context["origin_compare_since"], compare_until: origin_context["origin_compare_until"]}}"
  end

  defp back_path(tenant_subject_name, %{"origin_surface" => "dossier"} = origin_context) do
    ~p"/control-plane/tenants/#{tenant_subject_name}/dossiers/#{origin_context["origin_node_kind"]}/#{origin_context["origin_node_id"]}?#{%{since: origin_context["origin_since"], until: origin_context["origin_until"], compare_since: origin_context["origin_compare_since"], compare_until: origin_context["origin_compare_until"]}}"
  end

  defp back_path(tenant_subject_name, %{"origin_surface" => "graph"} = origin_context) do
    ~p"/control-plane/tenants/#{tenant_subject_name}/graph?#{%{node_kind: origin_context["origin_node_kind"], node_id: origin_context["origin_node_id"], since: origin_context["origin_since"], until: origin_context["origin_until"], compare_since: origin_context["origin_compare_since"], compare_until: origin_context["origin_compare_until"]}}"
  end

  defp back_path(_tenant_subject_name, _origin_context), do: nil

  defp compare_window_present?(filters) do
    filters["compare_since"] not in [nil, ""] or filters["compare_until"] not in [nil, ""]
  end

  defp qa_question(filters) do
    cond do
      filters["query"] not in [nil, ""] ->
        filters["query"]

      filters["actor_handle"] not in [nil, ""] ->
        "What did #{filters["actor_handle"]} discuss?"

      filters["entity_name"] not in [nil, ""] ->
        "What happened to #{filters["entity_name"]}?"

      true ->
        "What happened in this period?"
    end
  end

  defp qa_compare_question(filters) do
    cond do
      filters["actor_handle"] not in [nil, ""] ->
        "What changed for #{filters["actor_handle"]} between these periods?"

      filters["entity_name"] not in [nil, ""] ->
        "What changed around #{filters["entity_name"]} between these periods?"

      true ->
        "What changed between these periods?"
    end
  end

  defp qa_params(filters, question) do
    %{}
    |> put_map_if_present("question", question)
    |> put_map_if_present("since", filters["since"])
    |> put_map_if_present("until", filters["until"])
    |> put_map_if_present("compare_since", filters["compare_since"])
    |> put_map_if_present("compare_until", filters["compare_until"])
    |> put_map_if_present("limit", filters["limit"])
  end

  defp put_map_if_present(map, _key, nil), do: map
  defp put_map_if_present(map, _key, ""), do: map
  defp put_map_if_present(map, key, value), do: Map.put(map, key, value)

  defp history_entity_params(window, entry) do
    %{}
    |> put_map_if_present("entity_name", entry[:entity_name] || entry["entity_name"])
    |> put_map_if_present("entity_type", entry[:entity_type] || entry["entity_type"])
    |> put_map_if_present("since", window[:since] || window["since"])
    |> put_map_if_present("until", window[:until] || window["until"])
  end

  defp history_fact_params(window, entry) do
    %{}
    |> put_map_if_present("query", entry[:label] || entry["label"])
    |> put_map_if_present("since", window[:since] || window["since"])
    |> put_map_if_present("until", window[:until] || window["until"])
  end

  defp graph_params(node_kind, node_id, filters) do
    %{}
    |> put_map_if_present("node_kind", node_kind)
    |> put_map_if_present("node_id", node_id)
    |> put_map_if_present("since", filters["since"])
    |> put_map_if_present("until", filters["until"])
    |> put_map_if_present("compare_since", filters["compare_since"])
    |> put_map_if_present("compare_until", filters["compare_until"])
  end

  defp reload_history(socket) do
    case load_history(
           socket.assigns.current_user,
           socket.assigns.tenant.subject_name,
           socket.assigns.filters
         ) do
      {:ok, listing} ->
        socket
        |> assign(:messages, listing.messages)
        |> assign(:facts_over_time, listing.facts_over_time)
        |> clear_flash()

      {:error, message} ->
        put_flash(socket, :error, message)
    end
  end
end
