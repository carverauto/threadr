defmodule ThreadrWeb.TenantQaLive.Index do
  use ThreadrWeb, :live_view

  alias Threadr.ControlPlane.{Analysis, Service}
  alias Threadr.ML.{QARequest, SummaryRequest}
  alias Threadr.TimeWindow

  @default_limit 5

  @impl true
  def mount(%{"subject_name" => subject_name}, _session, socket) do
    case Service.get_user_tenant_by_subject_name(socket.assigns.current_user, subject_name) do
      {:ok, tenant, membership} ->
        {:ok,
         socket
         |> assign(:tenant, tenant)
         |> assign(:membership_role, membership.role)
         |> assign(
           :qa_embedding_status,
           fetch_qa_embedding_status(socket.assigns.current_user, tenant)
         )
         |> assign(:question, "")
         |> assign(:limit, @default_limit)
         |> assign(:since, "")
         |> assign(:until, "")
         |> assign(:compare_since, "")
         |> assign(:compare_until, "")
         |> assign(:search_result, nil)
         |> assign(:answer_result, nil)
         |> assign(:comparison_result, nil)
         |> assign(:graph_answer_result, nil)
         |> assign(:summary_result, nil)}

      {:error, _reason} ->
        {:halt,
         socket
         |> put_flash(:error, "Tenant not found")
         |> push_navigate(to: ~p"/control-plane/tenants")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:question, normalize_blank(Map.get(params, "question", socket.assigns.question)))
     |> assign(:limit, normalize_limit(Map.get(params, "limit", socket.assigns.limit)))
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
  def handle_event("change", %{"question" => question, "limit" => limit} = params, socket) do
    {:noreply,
     socket
     |> assign(:question, question)
     |> assign(:limit, normalize_limit(limit))
     |> assign(:since, normalize_blank(Map.get(params, "since")))
     |> assign(:until, normalize_blank(Map.get(params, "until")))
     |> assign(:compare_since, normalize_blank(Map.get(params, "compare_since")))
     |> assign(:compare_until, normalize_blank(Map.get(params, "compare_until")))}
  end

  def handle_event("search", _params, socket) do
    case run_search(socket) do
      {:ok, result} ->
        {:noreply,
         socket
         |> refresh_qa_embedding_status()
         |> assign(:search_result, result)
         |> assign(:answer_result, nil)
         |> assign(:comparison_result, nil)
         |> assign(:graph_answer_result, nil)
         |> assign(:summary_result, nil)
         |> clear_flash()}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("answer", _params, socket) do
    case run_answer(socket) do
      {:ok, result} ->
        {:noreply,
         socket
         |> refresh_qa_embedding_status()
         |> assign(:answer_result, result)
         |> assign(:search_result, result)
         |> assign(:comparison_result, nil)
         |> assign(:graph_answer_result, nil)
         |> assign(:summary_result, nil)
         |> clear_flash()}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("graph_answer", _params, socket) do
    case run_graph_answer(socket) do
      {:ok, result} ->
        {:noreply,
         socket
         |> refresh_qa_embedding_status()
         |> assign(:graph_answer_result, result)
         |> assign(:search_result, result.semantic)
         |> assign(:answer_result, nil)
         |> assign(:comparison_result, nil)
         |> assign(:summary_result, nil)
         |> clear_flash()}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("summarize", _params, socket) do
    case run_summary(socket) do
      {:ok, result} ->
        {:noreply,
         socket
         |> refresh_qa_embedding_status()
         |> assign(:summary_result, result)
         |> assign(:search_result, result.semantic)
         |> assign(:answer_result, nil)
         |> assign(:comparison_result, nil)
         |> assign(:graph_answer_result, nil)
         |> clear_flash()}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("compare", _params, socket) do
    case run_compare(socket) do
      {:ok, result} ->
        {:noreply,
         socket
         |> refresh_qa_embedding_status()
         |> assign(:comparison_result, result)
         |> assign(:search_result, nil)
         |> assign(:answer_result, nil)
         |> assign(:graph_answer_result, nil)
         |> assign(:summary_result, nil)
         |> clear_flash()}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="space-y-6">
        <.header>
          Tenant QA Workspace
          <:subtitle>
            Search embedded tenant messages and ask grounded questions against retrieved context.
          </:subtitle>
          <:actions>
            <div class="flex gap-2">
              <.button navigate={~p"/control-plane/tenants"}>Tenants</.button>
              <.button navigate={~p"/control-plane/tenants/#{@tenant.subject_name}/history"}>
                History
              </.button>
              <.button navigate={
                ~p"/control-plane/tenants/#{@tenant.subject_name}/graph?#{graph_focus_params(nil, nil, %{since: @since, until: @until, compare_since: @compare_since, compare_until: @compare_until})}"
              }>
                Graph
              </.button>
              <.button
                :if={Service.manager_role?(@membership_role)}
                navigate={~p"/control-plane/tenants/#{@tenant.subject_name}/llm"}
              >
                LLM Settings
              </.button>
              <.button navigate={~p"/settings/api-keys"}>API Keys</.button>
            </div>
          </:actions>
        </.header>

        <div class="grid gap-4 lg:grid-cols-[1.4fr_1fr]">
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

              <div class="rounded-box border border-base-300 bg-base-200 px-4 py-3">
                <div class="flex items-center justify-between gap-4">
                  <div>
                    <div class="text-sm font-semibold text-base-content/70">QA Embeddings</div>
                    <div class="text-xs text-base-content/60">
                      {qa_embedding_summary(@qa_embedding_status)}
                    </div>
                  </div>
                  <span class={qa_embedding_badge_class(@qa_embedding_status)}>
                    {qa_embedding_label(@qa_embedding_status)}
                  </span>
                </div>
                <div class="mt-2 text-xs text-base-content/60">
                  {qa_embedding_detail(@qa_embedding_status)}
                </div>
                <div
                  :if={qa_embedding_timestamp(@qa_embedding_status)}
                  class="mt-1 text-xs text-base-content/50"
                >
                  Latest missing message: {format_datetime(
                    qa_embedding_timestamp(@qa_embedding_status)
                  )}
                </div>
              </div>

              <form id="tenant-qa-form" phx-change="change" class="space-y-4">
                <.input
                  id="tenant-qa-question"
                  name="question"
                  label="Question"
                  value={@question}
                  placeholder="What does Alice know about Bob?"
                />

                <.input
                  id="tenant-qa-limit"
                  name="limit"
                  type="number"
                  min="1"
                  max="20"
                  label="Retrieved Messages"
                  value={@limit}
                />

                <div class="grid gap-4 md:grid-cols-2">
                  <.input
                    id="tenant-qa-since"
                    name="since"
                    type="datetime-local"
                    label="Since"
                    value={@since}
                  />
                  <.input
                    id="tenant-qa-until"
                    name="until"
                    type="datetime-local"
                    label="Until"
                    value={@until}
                  />
                </div>

                <div class="grid gap-4 md:grid-cols-2">
                  <.input
                    id="tenant-qa-compare-since"
                    name="compare_since"
                    type="datetime-local"
                    label="Compare Since"
                    value={@compare_since}
                  />
                  <.input
                    id="tenant-qa-compare-until"
                    name="compare_until"
                    type="datetime-local"
                    label="Compare Until"
                    value={@compare_until}
                  />
                </div>
              </form>

              <div class="flex flex-wrap gap-2">
                <.button id="tenant-qa-search" phx-click="search">Search Context</.button>
                <.button id="tenant-qa-answer" phx-click="answer" variant="primary">
                  Ask Tenant
                </.button>
                <.button id="tenant-qa-compare" phx-click="compare" variant="primary">
                  Compare Windows
                </.button>
                <.button id="tenant-qa-graph-answer" phx-click="graph_answer" variant="primary">
                  Ask Graph
                </.button>
                <.button id="tenant-qa-summarize" phx-click="summarize">Summarize Topic</.button>
              </div>
            </div>
          </div>

          <div class="card bg-base-200 shadow-sm">
            <div class="card-body">
              <div class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
                Retrieved Context
              </div>
              <pre class="whitespace-pre-wrap text-sm leading-6 text-base-content/80">{context_text(assigns)}</pre>
            </div>
          </div>
        </div>

        <div
          :if={@comparison_result}
          class="card bg-base-100 border border-base-300 shadow-sm"
        >
          <div class="card-body gap-4">
            <div class="flex items-center justify-between gap-4">
              <div>
                <div class="text-sm text-base-content/60">Window Comparison</div>
                <div class="font-semibold">
                  {@comparison_result.answer.provider} / {@comparison_result.answer.model}
                </div>
              </div>
              <div class="text-xs text-base-content/60">{@comparison_result.question}</div>
            </div>
            <div id="tenant-qa-compare-content" class="prose max-w-none text-base-content">
              <p>{@comparison_result.answer.content}</p>
            </div>

            <div class="grid gap-4 xl:grid-cols-2">
              <div class="rounded-box border border-base-300 bg-base-200 p-4">
                <div class="text-sm font-semibold text-base-content/70">Entity Delta</div>
                <.entity_delta_panel
                  id="tenant-qa-entity-delta"
                  delta={@comparison_result.entity_delta}
                  tenant_subject_name={@tenant.subject_name}
                  baseline_window={%{since: @since, until: @until}}
                  comparison_window={%{since: @compare_since, until: @compare_until}}
                  origin_params={
                    history_origin_params(
                      @question,
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
                  id="tenant-qa-fact-delta"
                  delta={@comparison_result.fact_delta}
                  tenant_subject_name={@tenant.subject_name}
                  baseline_window={%{since: @since, until: @until}}
                  comparison_window={%{since: @compare_since, until: @compare_until}}
                  origin_params={
                    history_origin_params(
                      @question,
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
                <pre class="mt-2 whitespace-pre-wrap text-xs leading-6 text-base-content/80">{@comparison_result.baseline.context}</pre>
              </div>
              <div class="rounded-box border border-base-300 bg-base-200 p-4">
                <div class="text-sm font-semibold text-base-content/70">Comparison Window</div>
                <pre class="mt-2 whitespace-pre-wrap text-xs leading-6 text-base-content/80">{@comparison_result.comparison.context}</pre>
              </div>
            </div>
          </div>
        </div>

        <div
          :if={active_generation_result(assigns)}
          class="card bg-base-100 border border-base-300 shadow-sm"
        >
          <div class="card-body gap-3">
            <div class="flex items-center justify-between gap-4">
              <div>
                <div class="text-sm text-base-content/60">{active_generation_title(assigns)}</div>
                <div class="font-semibold">
                  {active_generation(assigns).provider} / {active_generation(assigns).model}
                </div>
              </div>
              <div class="text-xs text-base-content/60">
                {active_generation_prompt(assigns)}
              </div>
            </div>
            <div id="tenant-qa-answer-content" class="prose max-w-none text-base-content">
              <p>{active_generation(assigns).content}</p>
            </div>
            <div :if={citation_rows(assigns) != []} class="space-y-2">
              <div class="text-sm font-semibold text-base-content/70">Citations</div>
              <div class="space-y-2">
                <div
                  :for={citation <- citation_rows(assigns)}
                  id={"tenant-qa-citation-#{citation.rank}"}
                  class="rounded-box border border-base-300 bg-base-200 px-4 py-3 text-sm"
                >
                  <div class="flex items-center justify-between gap-3">
                    <span class="badge badge-outline">{citation.label}</span>
                    <span class="text-xs text-base-content/60">
                      {format_datetime(citation.observed_at)}
                    </span>
                  </div>
                  <div class="mt-2 font-medium">{citation.body}</div>
                  <div class="mt-1 text-xs text-base-content/60">
                    <span>{"#" <> to_string(citation.channel_name)}</span>
                    <span>{citation.actor_handle}</span>
                    <span :if={is_float(citation.similarity)}>
                      - similarity {format_similarity(citation.similarity)}
                    </span>
                  </div>
                  <div class="mt-2 flex flex-wrap gap-2">
                    <.link
                      navigate={
                        ~p"/control-plane/tenants/#{@tenant.subject_name}/graph?#{graph_focus_params("message", citation.message_id, %{since: @since, until: @until, compare_since: @compare_since, compare_until: @compare_until})}"
                      }
                      class="btn btn-ghost btn-xs"
                    >
                      Message in Graph
                    </.link>
                    <.link
                      :if={Map.get(citation, :actor_id)}
                      navigate={
                        ~p"/control-plane/tenants/#{@tenant.subject_name}/graph?#{graph_focus_params("actor", citation.actor_id, %{since: @since, until: @until, compare_since: @compare_since, compare_until: @compare_until})}"
                      }
                      class="btn btn-ghost btn-xs"
                    >
                      Actor in Graph
                    </.link>
                    <.link
                      :if={Map.get(citation, :channel_id)}
                      navigate={
                        ~p"/control-plane/tenants/#{@tenant.subject_name}/graph?#{graph_focus_params("channel", citation.channel_id, %{since: @since, until: @until, compare_since: @compare_since, compare_until: @compare_until})}"
                      }
                      class="btn btn-ghost btn-xs"
                    >
                      Channel in Graph
                    </.link>
                  </div>
                  <div
                    :if={Map.get(citation, :extracted_entities, []) != []}
                    class="mt-2 flex flex-wrap gap-2"
                  >
                    <span
                      :for={entity <- Map.get(citation, :extracted_entities, [])}
                      class="badge badge-outline badge-sm"
                    >
                      {entity.entity_type}: {entity.canonical_name || entity.name}
                    </span>
                  </div>
                  <div :if={Map.get(citation, :extracted_facts, []) != []} class="mt-2 space-y-1">
                    <div
                      :for={fact <- Map.get(citation, :extracted_facts, [])}
                      class="rounded-box bg-base-100 px-3 py-2 text-xs text-base-content/80"
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
              </div>
            </div>
            <div
              :if={graph_citation_rows(assigns) != []}
              class="space-y-2 border-t border-base-300 pt-4"
            >
              <div class="text-sm font-semibold text-base-content/70">Graph Context</div>
              <pre class="whitespace-pre-wrap text-sm leading-6 text-base-content/80">{graph_context_text(assigns)}</pre>
              <div class="space-y-2">
                <div
                  :for={citation <- graph_citation_rows(assigns)}
                  id={"tenant-qa-graph-citation-#{citation.label}"}
                  class="rounded-box border border-base-300 bg-base-200 px-4 py-3 text-sm"
                >
                  <div class="flex items-center justify-between gap-3">
                    <span class="badge badge-outline">{citation.label}</span>
                    <span class="text-xs text-base-content/60">
                      {format_datetime(citation.observed_at)}
                    </span>
                  </div>
                  <div class="mt-2 font-medium">{citation.body}</div>
                  <div class="mt-1 text-xs text-base-content/60">
                    <span>{"#" <> to_string(citation.channel_name)}</span>
                    <span>{citation.actor_handle}</span>
                  </div>
                  <div class="mt-2 flex flex-wrap gap-2">
                    <.link
                      navigate={
                        ~p"/control-plane/tenants/#{@tenant.subject_name}/graph?#{graph_focus_params("message", citation.message_id, %{since: @since, until: @until, compare_since: @compare_since, compare_until: @compare_until})}"
                      }
                      class="btn btn-ghost btn-xs"
                    >
                      Message in Graph
                    </.link>
                    <.link
                      :if={Map.get(citation, :actor_id)}
                      navigate={
                        ~p"/control-plane/tenants/#{@tenant.subject_name}/graph?#{graph_focus_params("actor", citation.actor_id, %{since: @since, until: @until, compare_since: @compare_since, compare_until: @compare_until})}"
                      }
                      class="btn btn-ghost btn-xs"
                    >
                      Actor in Graph
                    </.link>
                    <.link
                      :if={Map.get(citation, :channel_id)}
                      navigate={
                        ~p"/control-plane/tenants/#{@tenant.subject_name}/graph?#{graph_focus_params("channel", citation.channel_id, %{since: @since, until: @until, compare_since: @compare_since, compare_until: @compare_until})}"
                      }
                      class="btn btn-ghost btn-xs"
                    >
                      Channel in Graph
                    </.link>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
          <.table
            id="tenant-qa-matches"
            rows={match_rows(assigns)}
            row_id={&"tenant-qa-match-#{&1.message_id}"}
          >
            <:col :let={match} label="Message">
              <div class="flex items-center gap-2">
                <span class="badge badge-outline">{citation_label(match, assigns)}</span>
                <div class="font-medium">{match.body}</div>
              </div>
              <div class="text-xs text-base-content/60">{match.external_id || match.message_id}</div>
            </:col>
            <:col :let={match} label="Actor">
              <div>{match.actor_handle}</div>
              <div class="text-xs text-base-content/60">{match.channel_name}</div>
              <div class="mt-2 flex flex-wrap gap-2">
                <.link
                  :if={Map.get(match, :actor_id)}
                  navigate={
                    ~p"/control-plane/tenants/#{@tenant.subject_name}/graph?#{graph_focus_params("actor", Map.get(match, :actor_id), %{since: @since, until: @until, compare_since: @compare_since, compare_until: @compare_until})}"
                  }
                  class="btn btn-ghost btn-xs"
                >
                  Actor in Graph
                </.link>
                <.link
                  :if={Map.get(match, :channel_id)}
                  navigate={
                    ~p"/control-plane/tenants/#{@tenant.subject_name}/graph?#{graph_focus_params("channel", Map.get(match, :channel_id), %{since: @since, until: @until, compare_since: @compare_since, compare_until: @compare_until})}"
                  }
                  class="btn btn-ghost btn-xs"
                >
                  Channel in Graph
                </.link>
              </div>
            </:col>
            <:col :let={match} label="Observed">
              {format_datetime(match.observed_at)}
            </:col>
            <:col :let={match} label="Similarity">
              {format_similarity(Map.get(match, :similarity))}
            </:col>
          </.table>
        </div>

        <div
          :if={qa_facts_over_time(assigns) != []}
          class="card bg-base-100 border border-base-300 shadow-sm"
        >
          <div class="card-body">
            <div class="text-sm font-semibold text-base-content/70">Facts Over Time</div>
            <div class="space-y-2">
              <div
                :for={entry <- qa_facts_over_time(assigns)}
                class="rounded-box border border-base-300 bg-base-200 px-4 py-3 text-sm"
              >
                <div class="flex items-center justify-between gap-3">
                  <div class="font-medium">{entry.day}</div>
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
      </section>
    </Layouts.app>
    """
  end

  defp run_search(socket) do
    question = String.trim(socket.assigns.question)

    if question == "" do
      {:error, "Question is required"}
    else
      Analysis.semantic_search_for_user(
        socket.assigns.current_user,
        socket.assigns.tenant.subject_name,
        qa_request(socket, question)
      )
      |> normalize_result_error()
    end
  end

  defp run_answer(socket) do
    question = String.trim(socket.assigns.question)

    if question == "" do
      {:error, "Question is required"}
    else
      Analysis.answer_tenant_question_for_user(
        socket.assigns.current_user,
        socket.assigns.tenant.subject_name,
        qa_request(socket, question)
      )
      |> normalize_result_error()
    end
  end

  defp run_compare(socket) do
    question = String.trim(socket.assigns.question)

    cond do
      question == "" ->
        {:error, "Question is required"}

      parse_naive_datetime(socket.assigns.compare_since) == nil and
          parse_naive_datetime(socket.assigns.compare_until) == nil ->
        {:error, "Comparison window is required"}

      true ->
        request = qa_request(socket, question)
        comparison_window = compare_window(socket)

        Analysis.compare_tenant_question_windows_for_user(
          socket.assigns.current_user,
          socket.assigns.tenant.subject_name,
          request,
          comparison_window
        )
        |> normalize_result_error()
    end
  end

  defp run_graph_answer(socket) do
    question = String.trim(socket.assigns.question)

    if question == "" do
      {:error, "Question is required"}
    else
      Analysis.answer_tenant_graph_question_for_user(
        socket.assigns.current_user,
        socket.assigns.tenant.subject_name,
        qa_request(socket, question)
      )
      |> normalize_result_error()
    end
  end

  defp run_summary(socket) do
    topic = String.trim(socket.assigns.question)

    if topic == "" do
      {:error, "Question is required"}
    else
      Analysis.summarize_tenant_topic_for_user(
        socket.assigns.current_user,
        socket.assigns.tenant.subject_name,
        summary_request(socket, topic)
      )
      |> normalize_result_error()
    end
  end

  defp normalize_result_error({:ok, result}), do: {:ok, result}

  defp normalize_result_error({:error, :no_message_embeddings}),
    do: {:error, "No tenant message embeddings available"}

  defp normalize_result_error({:error, :forbidden}),
    do: {:error, "You do not have access to that tenant"}

  defp normalize_result_error({:error, :generation_provider_not_configured}),
    do: {:error, "No LLM is configured. Use tenant LLM settings or the system provider."}

  defp normalize_result_error({:error, {:tenant_not_found, _}}), do: {:error, "Tenant not found"}

  defp normalize_result_error({:error, reason}),
    do: {:error, "Semantic QA failed: #{inspect(reason)}"}

  defp refresh_qa_embedding_status(socket) do
    assign(
      socket,
      :qa_embedding_status,
      fetch_qa_embedding_status(socket.assigns.current_user, socket.assigns.tenant)
    )
  end

  defp fetch_qa_embedding_status(user, tenant) do
    case Analysis.qa_embedding_status_for_user(user, tenant.subject_name) do
      {:ok, status} -> status
      {:error, _reason} -> nil
    end
  end

  defp qa_request(socket, question) do
    QARequest.new(question, :user,
      limit: socket.assigns.limit,
      since: parse_naive_datetime(socket.assigns.since),
      until: parse_naive_datetime(socket.assigns.until)
    )
  end

  defp compare_window(socket) do
    TimeWindow.new(
      since: parse_naive_datetime(socket.assigns.compare_since),
      until: parse_naive_datetime(socket.assigns.compare_until)
    )
  end

  defp summary_request(socket, topic) do
    SummaryRequest.new(topic,
      limit: socket.assigns.limit,
      since: parse_naive_datetime(socket.assigns.since),
      until: parse_naive_datetime(socket.assigns.until)
    )
  end

  defp normalize_limit(limit) when is_integer(limit) and limit > 0, do: min(limit, 20)

  defp normalize_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {value, ""} when value > 0 -> min(value, 20)
      _ -> @default_limit
    end
  end

  defp normalize_limit(_limit), do: @default_limit

  defp normalize_blank(nil), do: ""
  defp normalize_blank(value), do: value |> to_string() |> String.trim()

  defp put_map_if_present(map, _key, nil), do: map
  defp put_map_if_present(map, _key, ""), do: map
  defp put_map_if_present(map, key, value), do: Map.put(map, key, value)

  defp history_origin_params(question, since, until, compare_since, compare_until) do
    %{}
    |> put_map_if_present("origin_surface", "qa")
    |> put_map_if_present("origin_question", question)
    |> put_map_if_present("origin_since", since)
    |> put_map_if_present("origin_until", until)
    |> put_map_if_present("origin_compare_since", compare_since)
    |> put_map_if_present("origin_compare_until", compare_until)
  end

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

  defp graph_focus_params(node_kind, node_id, window) do
    %{}
    |> put_map_if_present("node_kind", node_kind)
    |> put_map_if_present("node_id", node_id)
    |> put_map_if_present("since", window[:since] || window["since"])
    |> put_map_if_present("until", window[:until] || window["until"])
    |> put_map_if_present("compare_since", window[:compare_since] || window["compare_since"])
    |> put_map_if_present("compare_until", window[:compare_until] || window["compare_until"])
  end

  defp parse_naive_datetime(""), do: nil
  defp parse_naive_datetime(nil), do: nil

  defp parse_naive_datetime(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, datetime} -> datetime
      _ -> nil
    end
  end

  defp context_text(%{answer_result: %{context: context}}) when is_binary(context), do: context

  defp context_text(%{graph_answer_result: %{context: context}}) when is_binary(context),
    do: context

  defp context_text(%{summary_result: %{context: context}}) when is_binary(context), do: context
  defp context_text(%{search_result: %{context: context}}) when is_binary(context), do: context
  defp context_text(_assigns), do: "Run a search or question to load tenant context."

  defp match_rows(%{answer_result: %{matches: matches}}), do: matches
  defp match_rows(%{graph_answer_result: %{semantic: %{matches: matches}}}), do: matches
  defp match_rows(%{summary_result: %{semantic: %{matches: matches}}}), do: matches
  defp match_rows(%{search_result: %{matches: matches}}), do: matches
  defp match_rows(_assigns), do: []

  defp citation_rows(%{answer_result: %{citations: citations}}), do: citations
  defp citation_rows(%{graph_answer_result: %{semantic: %{citations: citations}}}), do: citations
  defp citation_rows(%{summary_result: %{semantic: %{citations: citations}}}), do: citations
  defp citation_rows(%{search_result: %{citations: citations}}), do: citations
  defp citation_rows(_assigns), do: []

  defp graph_citation_rows(%{graph_answer_result: %{graph: %{citations: citations}}}),
    do: citations

  defp graph_citation_rows(%{summary_result: %{graph: %{citations: citations}}}), do: citations
  defp graph_citation_rows(_assigns), do: []

  defp qa_facts_over_time(%{answer_result: %{facts_over_time: entries}}), do: entries
  defp qa_facts_over_time(%{search_result: %{facts_over_time: entries}}), do: entries
  defp qa_facts_over_time(_assigns), do: []

  defp graph_context_text(%{graph_answer_result: %{graph: %{context: context}}})
       when is_binary(context),
       do: context

  defp graph_context_text(%{summary_result: %{graph: %{context: context}}})
       when is_binary(context),
       do: context

  defp graph_context_text(_assigns), do: "No graph neighborhood context available."

  defp citation_label(match, assigns) do
    case Enum.find(citation_rows(assigns), &(&1.message_id == match.message_id)) do
      %{label: label} -> label
      _ -> "?"
    end
  end

  defp active_generation_result(%{summary_result: result}) when not is_nil(result), do: result

  defp active_generation_result(%{graph_answer_result: result}) when not is_nil(result),
    do: result

  defp active_generation_result(%{answer_result: result}) when not is_nil(result), do: result
  defp active_generation_result(_assigns), do: nil

  defp active_generation(%{summary_result: %{summary: summary}}), do: summary
  defp active_generation(%{graph_answer_result: %{answer: answer}}), do: answer
  defp active_generation(%{answer_result: %{answer: answer}}), do: answer

  defp active_generation_title(%{summary_result: %{}}), do: "Summary"
  defp active_generation_title(%{graph_answer_result: %{}}), do: "Graph Answer"
  defp active_generation_title(%{answer_result: %{}}), do: "Answer"

  defp active_generation_prompt(%{summary_result: %{topic: topic}}), do: topic
  defp active_generation_prompt(%{graph_answer_result: %{question: question}}), do: question
  defp active_generation_prompt(%{answer_result: %{question: question}}), do: question

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")

  defp format_datetime(%NaiveDateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp format_datetime(value), do: to_string(value)

  defp format_similarity(value) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: 4)

  defp format_similarity(value), do: to_string(value)

  defp qa_embedding_label(%{status: :ready}), do: "ready"
  defp qa_embedding_label(%{status: :catching_up}), do: "catching up"
  defp qa_embedding_label(%{status: :empty}), do: "empty"
  defp qa_embedding_label(_status), do: "unknown"

  defp qa_embedding_badge_class(%{status: :ready}), do: "badge badge-success"
  defp qa_embedding_badge_class(%{status: :catching_up}), do: "badge badge-warning"
  defp qa_embedding_badge_class(%{status: :empty}), do: "badge badge-outline"
  defp qa_embedding_badge_class(_status), do: "badge badge-neutral"

  defp qa_embedding_summary(%{
         embedded_messages: embedded,
         total_messages: total,
         coverage_percent: pct
       }) do
    "#{embedded} / #{total} embedded (#{pct}%)"
  end

  defp qa_embedding_summary(_status), do: "Embedding status unavailable"

  defp qa_embedding_detail(%{status: :ready, embedding_model: model}) do
    "All retained messages are embedded for #{model}."
  end

  defp qa_embedding_detail(%{
         status: :catching_up,
         missing_messages: missing,
         embedding_model: model
       }) do
    "#{missing} retained messages still need embeddings for #{model}."
  end

  defp qa_embedding_detail(%{status: :empty}) do
    "No retained tenant messages are currently available for QA."
  end

  defp qa_embedding_detail(_status), do: "Embedding status unavailable"

  defp qa_embedding_timestamp(%{latest_unembedded_observed_at: %DateTime{} = observed_at}),
    do: observed_at

  defp qa_embedding_timestamp(%{latest_unembedded_observed_at: %NaiveDateTime{} = observed_at}),
    do: observed_at

  defp qa_embedding_timestamp(_status), do: nil

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
end
