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
       |> assign(:dossier, result.dossier)
       |> assign(:since, "")
       |> assign(:until, "")
       |> assign(:compare_since, "")
       |> assign(:compare_until, "")
       |> assign(:comparison_result, nil)}
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
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:since, normalize_blank(Map.get(params, "since", socket.assigns.since)))
     |> assign(:until, normalize_blank(Map.get(params, "until", socket.assigns.until)))
     |> assign(
       :compare_since,
       normalize_blank(Map.get(params, "compare_since", socket.assigns.compare_since))
     )
     |> assign(
       :compare_until,
       normalize_blank(Map.get(params, "compare_until", socket.assigns.compare_until))
     )}
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
  def handle_event("change_compare", params, socket) do
    {:noreply,
     socket
     |> assign(:since, normalize_blank(Map.get(params, "since")))
     |> assign(:until, normalize_blank(Map.get(params, "until")))
     |> assign(:compare_since, normalize_blank(Map.get(params, "compare_since")))
     |> assign(:compare_until, normalize_blank(Map.get(params, "compare_until")))}
  end

  @impl true
  def handle_event("compare_windows", _params, socket) do
    dossier = socket.assigns.dossier
    focal = dossier.focal

    with {:ok, result} <-
           Service.compare_tenant_dossier_windows_for_user(
             socket.assigns.current_user,
             socket.assigns.tenant.subject_name,
             dossier.type,
             focal["id"] || focal[:id],
             since: parse_naive_datetime(socket.assigns.since),
             until: parse_naive_datetime(socket.assigns.until),
             compare_since: parse_naive_datetime(socket.assigns.compare_since),
             compare_until: parse_naive_datetime(socket.assigns.compare_until)
           ) do
      {:noreply, socket |> assign(:comparison_result, result) |> clear_flash()}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Dossier comparison failed: #{inspect(reason)}")}
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
              <.button
                id="dossier-ask-in-qa"
                navigate={
                  ~p"/control-plane/tenants/#{@tenant.subject_name}/qa?#{qa_params(@dossier, @since, @until, @compare_since, @compare_until, qa_question(@dossier))}"
                }
              >
                Ask in QA
              </.button>
              <.button
                :if={compare_window_present?(@compare_since, @compare_until)}
                id="dossier-compare-in-qa"
                navigate={
                  ~p"/control-plane/tenants/#{@tenant.subject_name}/qa?#{qa_params(@dossier, @since, @until, @compare_since, @compare_until, qa_compare_question(@dossier))}"
                }
              >
                Compare in QA
              </.button>
              <.button
                navigate={
                  ~p"/control-plane/tenants/#{@tenant.subject_name}/graph?#{graph_params(@dossier, @since, @until, @compare_since, @compare_until)}"
                }
              >
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

              <div
                :if={@dossier[:extracted_entities] && @dossier.extracted_entities != []}
                class="space-y-2"
              >
                <div class="text-sm font-semibold text-base-content/70">Extracted Entities</div>
                <div class="flex flex-wrap gap-2">
                  <span
                    :for={entity <- @dossier.extracted_entities}
                    class="badge badge-outline"
                  >
                    {entity["entity_type"] || entity[:entity_type]}: {entity["canonical_name"] ||
                      entity[:canonical_name] || entity["name"] || entity[:name]}
                  </span>
                </div>
              </div>

              <div
                :if={@dossier[:extracted_facts] && @dossier.extracted_facts != []}
                class="space-y-2"
              >
                <div class="text-sm font-semibold text-base-content/70">Extracted Facts</div>
                <div class="space-y-2">
                  <div
                    :for={fact <- @dossier.extracted_facts}
                    class="rounded-box border border-base-300 bg-base-200 p-3 text-sm"
                  >
                    <div class="font-medium">
                      {fact["subject"] || fact[:subject]} {fact["predicate"] || fact[:predicate]} {fact[
                        "object"
                      ] || fact[:object]}
                    </div>
                    <div class="text-xs text-base-content/60">
                      {fact["fact_type"] || fact[:fact_type]}{format_fact_time(
                        fact["valid_at"] || fact[:valid_at]
                      )}
                    </div>
                  </div>
                </div>
              </div>

              <div
                :if={@dossier[:facts_over_time] && @dossier.facts_over_time != []}
                class="space-y-2"
              >
                <div class="text-sm font-semibold text-base-content/70">Facts Over Time</div>
                <div class="space-y-2">
                  <div
                    :for={entry <- @dossier.facts_over_time}
                    class="rounded-box border border-base-300 bg-base-200 p-3 text-sm"
                  >
                    <div class="flex items-center justify-between gap-3">
                      <div class="font-medium">{entry["day"] || entry[:day]}</div>
                      <div class="text-xs text-base-content/60">
                        {entry["fact_count"] || entry[:fact_count]} facts
                      </div>
                    </div>
                    <div class="text-xs text-base-content/70">
                      Top fact: {entry["top_fact"] || entry[:top_fact]}
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

        <div class="card bg-base-100 border border-base-300 shadow-sm">
          <div class="card-body gap-4">
            <div class="text-sm font-semibold text-base-content/70">Compare Windows</div>
            <form
              id="dossier-compare-form"
              phx-change="change_compare"
              class="grid gap-4 md:grid-cols-2 xl:grid-cols-4"
            >
              <.input
                id="dossier-since"
                name="since"
                type="datetime-local"
                label="Baseline Since"
                value={@since}
              />
              <.input
                id="dossier-until"
                name="until"
                type="datetime-local"
                label="Baseline Until"
                value={@until}
              />
              <.input
                id="dossier-compare-since"
                name="compare_since"
                type="datetime-local"
                label="Compare Since"
                value={@compare_since}
              />
              <.input
                id="dossier-compare-until"
                name="compare_until"
                type="datetime-local"
                label="Compare Until"
                value={@compare_until}
              />
            </form>
            <div>
              <.button id="dossier-compare-submit" phx-click="compare_windows">
                Compare Period
              </.button>
            </div>

            <div :if={@comparison_result} class="space-y-4">
              <div class="rounded-box border border-base-300 bg-base-200 p-4">
                <div class="text-sm font-semibold text-base-content/70">Comparison Summary</div>
                <div id="dossier-compare-answer" class="mt-2 text-sm leading-6 text-base-content/90">
                  {@comparison_result.answer.content}
                </div>
              </div>

              <div class="grid gap-4 xl:grid-cols-2">
                <div class="rounded-box border border-base-300 bg-base-200 p-4">
                  <div class="text-sm font-semibold text-base-content/70">Entity Delta</div>
                  <.entity_delta_panel
                    id="dossier-entity-delta"
                    delta={@comparison_result.comparison.entity_delta}
                    tenant_subject_name={@tenant.subject_name}
                    baseline_window={%{since: @since, until: @until}}
                    comparison_window={%{since: @compare_since, until: @compare_until}}
                    origin_params={
                      history_origin_params(
                        @dossier,
                        @since,
                        @until,
                        @compare_since,
                        @compare_until
                      )
                    }
                  />
                </div>
                <div class="rounded-box border border-base-300 bg-base-200 p-4">
                  <div class="text-sm font-semibold text-base-content/70">Fact Delta</div>
                  <.fact_delta_panel
                    id="dossier-fact-delta"
                    delta={@comparison_result.comparison.fact_delta}
                    tenant_subject_name={@tenant.subject_name}
                    baseline_window={%{since: @since, until: @until}}
                    comparison_window={%{since: @compare_since, until: @compare_until}}
                    origin_params={
                      history_origin_params(
                        @dossier,
                        @since,
                        @until,
                        @compare_since,
                        @compare_until
                      )
                    }
                  />
                </div>
              </div>

              <div class="grid gap-4 xl:grid-cols-2">
                <div class="rounded-box border border-base-300 bg-base-200 p-4">
                  <div class="text-sm font-semibold text-base-content/70">Baseline Window</div>
                  <pre class="mt-2 whitespace-pre-wrap text-xs leading-6 text-base-content/80">{baseline_context(@comparison_result.comparison.context)}</pre>
                </div>
                <div class="rounded-box border border-base-300 bg-base-200 p-4">
                  <div class="text-sm font-semibold text-base-content/70">Comparison Window</div>
                  <pre class="mt-2 whitespace-pre-wrap text-xs leading-6 text-base-content/80">{comparison_context(@comparison_result.comparison.context)}</pre>
                </div>
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

  defp format_fact_time(nil), do: ""
  defp format_fact_time(""), do: ""
  defp format_fact_time(value), do: " · " <> to_string(value)

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

  defp compare_window_present?(compare_since, compare_until),
    do: compare_since not in [nil, ""] or compare_until not in [nil, ""]

  defp qa_question(%{type: "actor", focal: focal}) do
    handle = focal["handle"] || focal[:handle]
    "What does #{handle} know?"
  end

  defp qa_question(%{type: "channel", focal: focal}) do
    channel = focal["name"] || focal[:name]
    "What happened in ##{channel}?"
  end

  defp qa_question(%{type: "message", focal: focal}) do
    body = focal["body"] || focal[:body] || "this message"
    "What does this message imply? #{body}"
  end

  defp qa_compare_question(%{type: "actor", focal: focal}) do
    handle = focal["handle"] || focal[:handle]
    "What changed for #{handle} between these periods?"
  end

  defp qa_compare_question(%{type: "channel", focal: focal}) do
    channel = focal["name"] || focal[:name]
    "What changed in ##{channel} between these periods?"
  end

  defp qa_compare_question(%{type: "message"}),
    do: "What changed around this message between these periods?"

  defp qa_params(dossier, since, until, compare_since, compare_until, question) do
    %{}
    |> put_map_if_present("question", question)
    |> put_map_if_present("since", since)
    |> put_map_if_present("until", until)
    |> put_map_if_present("compare_since", compare_since)
    |> put_map_if_present("compare_until", compare_until)
    |> put_map_if_present("limit", qa_limit(dossier))
  end

  defp history_origin_params(dossier, since, until, compare_since, compare_until) do
    %{}
    |> put_map_if_present("origin_surface", "dossier")
    |> put_map_if_present("origin_node_kind", dossier.type)
    |> put_map_if_present("origin_node_id", dossier.focal["id"] || dossier.focal[:id])
    |> put_map_if_present("origin_since", since)
    |> put_map_if_present("origin_until", until)
    |> put_map_if_present("origin_compare_since", compare_since)
    |> put_map_if_present("origin_compare_until", compare_until)
  end

  defp qa_limit(%{summary: summary}) when is_map(summary) do
    summary[:message_count] || summary["message_count"] || 5
  end

  defp qa_limit(_dossier), do: 5

  defp put_map_if_present(map, _key, nil), do: map
  defp put_map_if_present(map, _key, ""), do: map
  defp put_map_if_present(map, key, value), do: Map.put(map, key, value)

  defp history_entity_params(window, entry, origin_params) do
    %{}
    |> put_map_if_present("entity_name", entry[:entity_name] || entry["entity_name"])
    |> put_map_if_present("entity_type", entry[:entity_type] || entry["entity_type"])
    |> put_map_if_present("since", window[:since] || window["since"])
    |> put_map_if_present("until", window[:until] || window["until"])
    |> Map.merge(origin_params)
  end

  defp history_fact_params(window, entry, origin_params) do
    %{}
    |> put_map_if_present("query", entry[:label] || entry["label"])
    |> put_map_if_present("since", window[:since] || window["since"])
    |> put_map_if_present("until", window[:until] || window["until"])
    |> Map.merge(origin_params)
  end

  defp graph_params(dossier, since, until, compare_since, compare_until) do
    %{}
    |> put_map_if_present("node_kind", dossier.type)
    |> put_map_if_present("node_id", dossier.focal["id"] || dossier.focal[:id])
    |> put_map_if_present("since", since)
    |> put_map_if_present("until", until)
    |> put_map_if_present("compare_since", compare_since)
    |> put_map_if_present("compare_until", compare_until)
  end

  attr(:id, :string, required: true)
  attr(:delta, :map, required: true)
  attr(:tenant_subject_name, :string, required: true)
  attr(:baseline_window, :map, required: true)
  attr(:comparison_window, :map, required: true)
  attr(:origin_params, :map, required: true)

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
            ~p"/control-plane/tenants/#{@tenant_subject_name}/history?#{history_entity_params(@comparison_window, entry, @origin_params)}"
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
            ~p"/control-plane/tenants/#{@tenant_subject_name}/history?#{history_entity_params(@baseline_window, entry, @origin_params)}"
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
  attr(:origin_params, :map, required: true)

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
            ~p"/control-plane/tenants/#{@tenant_subject_name}/history?#{history_fact_params(@comparison_window, entry, @origin_params)}"
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
            ~p"/control-plane/tenants/#{@tenant_subject_name}/history?#{history_fact_params(@baseline_window, entry, @origin_params)}"
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

  defp baseline_context(context) when is_binary(context) do
    context
    |> String.split("\n\nComparison Window:\n")
    |> hd()
  end

  defp comparison_context(context) when is_binary(context) do
    context
    |> String.split("\n\nComparison Window:\n")
    |> List.last()
  end

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
