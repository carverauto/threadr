defmodule ThreadrWeb.TenantQaLive.Index do
  use ThreadrWeb, :live_view

  alias Threadr.ControlPlane.Service

  @default_limit 5

  @impl true
  def mount(%{"subject_name" => subject_name}, _session, socket) do
    case Service.get_user_tenant_by_subject_name(socket.assigns.current_user, subject_name) do
      {:ok, tenant, membership} ->
        {:ok,
         socket
         |> assign(:tenant, tenant)
         |> assign(:membership_role, membership.role)
         |> assign(:question, "")
         |> assign(:limit, @default_limit)
         |> assign(:search_result, nil)
         |> assign(:answer_result, nil)}

      {:error, _reason} ->
        {:halt,
         socket
         |> put_flash(:error, "Tenant not found")
         |> push_navigate(to: ~p"/control-plane/tenants")}
    end
  end

  @impl true
  def handle_event("change", %{"question" => question, "limit" => limit}, socket) do
    {:noreply,
     socket
     |> assign(:question, question)
     |> assign(:limit, normalize_limit(limit))}
  end

  def handle_event("search", _params, socket) do
    case run_search(socket) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:search_result, result)
         |> assign(:answer_result, nil)
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
         |> assign(:answer_result, result)
         |> assign(:search_result, result)
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
              </form>

              <div class="flex flex-wrap gap-2">
                <.button id="tenant-qa-search" phx-click="search">Search Context</.button>
                <.button id="tenant-qa-answer" phx-click="answer" variant="primary">
                  Ask Tenant
                </.button>
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

        <div :if={@answer_result} class="card bg-base-100 border border-base-300 shadow-sm">
          <div class="card-body gap-3">
            <div class="flex items-center justify-between gap-4">
              <div>
                <div class="text-sm text-base-content/60">Answer</div>
                <div class="font-semibold">
                  {@answer_result.answer.provider} / {@answer_result.answer.model}
                </div>
              </div>
              <div class="text-xs text-base-content/60">
                {@answer_result.question}
              </div>
            </div>
            <div id="tenant-qa-answer-content" class="prose max-w-none text-base-content">
              <p>{@answer_result.answer.content}</p>
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
            </:col>
            <:col :let={match} label="Observed">
              {format_datetime(match.observed_at)}
            </:col>
            <:col :let={match} label="Similarity">
              {format_similarity(match.similarity)}
            </:col>
          </.table>
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
      Service.semantic_search_for_user(
        socket.assigns.current_user,
        socket.assigns.tenant.subject_name,
        question,
        limit: socket.assigns.limit
      )
      |> normalize_result_error()
    end
  end

  defp run_answer(socket) do
    question = String.trim(socket.assigns.question)

    if question == "" do
      {:error, "Question is required"}
    else
      Service.answer_tenant_question_for_user(
        socket.assigns.current_user,
        socket.assigns.tenant.subject_name,
        question,
        limit: socket.assigns.limit
      )
      |> normalize_result_error()
    end
  end

  defp normalize_result_error({:ok, result}), do: {:ok, result}

  defp normalize_result_error({:error, :no_message_embeddings}),
    do: {:error, "No tenant message embeddings available"}

  defp normalize_result_error({:error, :forbidden}),
    do: {:error, "You do not have access to that tenant"}

  defp normalize_result_error({:error, {:tenant_not_found, _}}), do: {:error, "Tenant not found"}

  defp normalize_result_error({:error, reason}),
    do: {:error, "Semantic QA failed: #{inspect(reason)}"}

  defp normalize_limit(limit) when is_integer(limit) and limit > 0, do: min(limit, 20)

  defp normalize_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {value, ""} when value > 0 -> min(value, 20)
      _ -> @default_limit
    end
  end

  defp normalize_limit(_limit), do: @default_limit

  defp context_text(%{answer_result: %{context: context}}) when is_binary(context), do: context
  defp context_text(%{search_result: %{context: context}}) when is_binary(context), do: context
  defp context_text(_assigns), do: "Run a search or question to load tenant context."

  defp match_rows(%{answer_result: %{matches: matches}}), do: matches
  defp match_rows(%{search_result: %{matches: matches}}), do: matches
  defp match_rows(_assigns), do: []

  defp citation_rows(%{answer_result: %{citations: citations}}), do: citations
  defp citation_rows(%{search_result: %{citations: citations}}), do: citations
  defp citation_rows(_assigns), do: []

  defp citation_label(match, assigns) do
    case Enum.find(citation_rows(assigns), &(&1.message_id == match.message_id)) do
      %{label: label} -> label
      _ -> "?"
    end
  end

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")

  defp format_datetime(%NaiveDateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp format_datetime(value), do: to_string(value)

  defp format_similarity(value) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: 4)

  defp format_similarity(value), do: to_string(value)
end
