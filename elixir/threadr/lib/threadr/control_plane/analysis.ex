defmodule Threadr.ControlPlane.Analysis do
  @moduledoc """
  Analyst-facing retrieval, comparison, and QA flows behind the control-plane boundary.
  """

  import Ecto.Query

  alias Threadr.{HistoryRequest, TimeWindow}
  alias Threadr.ControlPlane.Service

  alias Threadr.ML.{
    EmbeddingProviderOpts,
    GraphRAG,
    QAOrchestrator,
    QARequest,
    RequestRuntimeOpts,
    SummaryRequest
  }

  alias Threadr.Repo
  alias Threadr.TenantData.MessageEmbedding

  @embedding_catch_up_limit 25

  def semantic_search_for_user(%{id: _user_id} = user, subject_name, %QARequest{} = request)
      when is_binary(subject_name) do
    runtime_opts = QARequest.to_runtime_opts(request)

    with {:ok, tenant, _membership} <-
           Service.get_user_tenant_by_subject_name(
             user,
             subject_name,
             semantic_ash_opts(runtime_opts)
           ),
         :ok <- ensure_recent_message_embeddings(tenant, runtime_opts),
         {:ok, result} <-
           Threadr.ML.SemanticQA.search_messages(
             tenant.subject_name,
             request.question,
             runtime_opts
           ) do
      {:ok, result}
    else
      {:error, reason} -> {:error, normalize_tenant_access_error(reason, subject_name)}
    end
  end

  def qa_embedding_status_for_user(%{id: _user_id} = user, subject_name, opts \\ [])
      when is_binary(subject_name) and is_list(opts) do
    with {:ok, tenant, _membership} <-
           Service.get_user_tenant_by_subject_name(
             user,
             subject_name,
             semantic_ash_opts(opts)
           ) do
      {:ok, qa_embedding_status(tenant, opts)}
    else
      {:error, reason} -> {:error, normalize_tenant_access_error(reason, subject_name)}
    end
  end

  def answer_tenant_question_for_user(
        %{id: _user_id} = user,
        subject_name,
        %QARequest{} = request
      )
      when is_binary(subject_name) do
    with {:ok, tenant, _membership} <-
           Service.get_user_tenant_by_subject_name(
             user,
             subject_name,
             semantic_ash_opts(QARequest.to_runtime_opts(request))
           ),
         {:ok, runtime_opts} <-
           tenant_generation_runtime_opts(tenant, QARequest.to_runtime_opts(request)),
         request = QARequest.merge_runtime_opts(request, runtime_opts),
         {:ok, result} <- answer_tenant_question_runtime(tenant, request) do
      {:ok, result}
    else
      {:error, reason} -> {:error, normalize_tenant_access_error(reason, subject_name)}
    end
  end

  def answer_tenant_question_for_bot(subject_name, %QARequest{} = request)
      when is_binary(subject_name) do
    with {:ok, tenant} <- get_tenant_by_subject_name_system(subject_name, []),
         {:ok, runtime_opts} <-
           tenant_generation_runtime_opts(tenant, QARequest.to_runtime_opts(request)),
         request = QARequest.merge_runtime_opts(request, runtime_opts) do
      answer_tenant_question_runtime(tenant, request)
    else
      {:error, reason} -> {:error, normalize_tenant_access_error(reason, subject_name)}
    end
  end

  def compare_tenant_question_windows_for_user(
        %{id: _user_id} = user,
        subject_name,
        %QARequest{} = request,
        %TimeWindow{} = comparison_window
      )
      when is_binary(subject_name) do
    runtime_opts = QARequest.to_runtime_opts(request)
    baseline_window = TimeWindow.from_opts(runtime_opts)

    with {:ok, tenant, _membership} <-
           Service.get_user_tenant_by_subject_name(
             user,
             subject_name,
             semantic_ash_opts(runtime_opts)
           ),
         {:ok, resolved_runtime_opts} <-
           tenant_generation_runtime_opts(tenant, runtime_opts),
         {:ok, result} <-
           Threadr.ML.SemanticQA.compare_windows(
             tenant.subject_name,
             request.question,
             TimeWindow.to_map(baseline_window),
             TimeWindow.to_map(comparison_window),
             resolved_runtime_opts
           ) do
      {:ok, result}
    else
      {:error, reason} -> {:error, normalize_tenant_access_error(reason, subject_name)}
    end
  end

  def answer_tenant_graph_question_for_user(
        %{id: _user_id} = user,
        subject_name,
        %QARequest{} = request
      )
      when is_binary(subject_name) do
    runtime_opts = QARequest.to_runtime_opts(request)

    with {:ok, tenant, _membership} <-
           Service.get_user_tenant_by_subject_name(
             user,
             subject_name,
             semantic_ash_opts(runtime_opts)
           ),
         {:ok, resolved_runtime_opts} <-
           tenant_generation_runtime_opts(tenant, runtime_opts),
         request = QARequest.merge_runtime_opts(request, resolved_runtime_opts),
         {:ok, result} <- GraphRAG.answer_question(tenant.subject_name, request) do
      {:ok, result}
    else
      {:error, reason} -> {:error, normalize_tenant_access_error(reason, subject_name)}
    end
  end

  def summarize_tenant_topic_for_user(
        %{id: _user_id} = user,
        subject_name,
        %SummaryRequest{} = request
      )
      when is_binary(subject_name) do
    runtime_opts = SummaryRequest.to_runtime_opts(request)

    with {:ok, tenant, _membership} <-
           Service.get_user_tenant_by_subject_name(
             user,
             subject_name,
             semantic_ash_opts(runtime_opts)
           ),
         {:ok, resolved_runtime_opts} <-
           tenant_generation_runtime_opts(tenant, runtime_opts),
         request = SummaryRequest.merge_runtime_opts(request, resolved_runtime_opts),
         {:ok, result} <- GraphRAG.summarize_topic(tenant.subject_name, request) do
      {:ok, result}
    else
      {:error, reason} -> {:error, normalize_tenant_access_error(reason, subject_name)}
    end
  end

  def list_tenant_messages_for_user(
        %{id: _user_id} = user,
        subject_name,
        %HistoryRequest{} = request
      )
      when is_binary(subject_name) do
    ash_opts = request |> HistoryRequest.ash_opts() |> semantic_ash_opts()

    with {:ok, tenant, membership} <-
           Service.get_user_tenant_by_subject_name(user, subject_name, ash_opts),
         {:ok, listing} <-
           Threadr.TenantData.History.list_messages(
             tenant.schema_name,
             HistoryRequest.to_runtime_opts(request)
           ) do
      {:ok, Map.merge(%{tenant: tenant, membership: membership}, listing)}
    else
      {:error, reason} -> {:error, normalize_tenant_access_error(reason, subject_name)}
    end
  end

  def compare_tenant_history_windows_for_user(
        %{id: _user_id} = user,
        subject_name,
        %HistoryRequest{} = request
      )
      when is_binary(subject_name) do
    ash_opts = request |> HistoryRequest.ash_opts() |> semantic_ash_opts()

    with {:ok, tenant, membership} <-
           Service.get_user_tenant_by_subject_name(user, subject_name, ash_opts),
         {:ok, runtime_opts} <-
           tenant_generation_runtime_opts(
             tenant,
             semantic_runtime_opts(HistoryRequest.ash_opts(request))
           ),
         {:ok, comparison} <-
           Threadr.TenantData.History.compare_windows(
             tenant.schema_name,
             HistoryRequest.to_runtime_opts(request),
             HistoryRequest.to_comparison_runtime_opts(request)
           ),
         {:ok, answer} <-
           Threadr.ML.Generation.complete(
             """
             Compare the baseline and comparison history windows for this tenant.
             Explain what changed in activity, participants, channels, and extracted facts using only the provided context.

             #{comparison.context}
             """,
             runtime_opts
           ) do
      {:ok,
       %{
         tenant: tenant,
         membership: membership,
         comparison: comparison,
         answer: answer
       }}
    else
      {:error, reason} -> {:error, normalize_tenant_access_error(reason, subject_name)}
    end
  end

  def get_tenant_dossier_for_user(
        %{id: _user_id} = user,
        subject_name,
        node_kind,
        node_id,
        opts \\ []
      )
      when is_binary(subject_name) and is_binary(node_kind) and is_binary(node_id) do
    with {:ok, tenant, membership} <-
           Service.get_user_tenant_by_subject_name(user, subject_name, semantic_ash_opts(opts)),
         {:ok, dossier} <-
           Threadr.TenantData.GraphInspector.describe_node(node_id, node_kind, tenant.schema_name) do
      {:ok, %{tenant: tenant, membership: membership, dossier: dossier}}
    else
      {:error, :not_found} -> {:error, {:resource_not_found, node_kind, node_id}}
      {:error, reason} -> {:error, normalize_tenant_access_error(reason, subject_name)}
    end
  end

  def compare_tenant_dossier_windows_for_user(
        %{id: _user_id} = user,
        subject_name,
        node_kind,
        node_id,
        %TimeWindow{} = baseline_window,
        %TimeWindow{} = comparison_window
      )
      when is_binary(subject_name) and is_binary(node_kind) and is_binary(node_id) do
    opts = TimeWindow.to_keyword(baseline_window)

    with {:ok, tenant, membership} <-
           Service.get_user_tenant_by_subject_name(user, subject_name, semantic_ash_opts(opts)),
         {:ok, runtime_opts} <-
           tenant_generation_runtime_opts(tenant, semantic_runtime_opts(opts)),
         {:ok, comparison} <-
           Threadr.TenantData.GraphInspector.compare_node_windows(
             node_id,
             node_kind,
             tenant.schema_name,
             TimeWindow.to_map(baseline_window),
             TimeWindow.to_map(comparison_window)
           ),
         {:ok, answer} <-
           Threadr.ML.Generation.complete(
             """
             Compare the baseline and comparison dossier windows for this #{node_kind}.
             Explain what changed in relationships, activity, and extracted facts using only the provided context.

             #{comparison.context}
             """,
             runtime_opts
           ) do
      {:ok,
       %{
         tenant: tenant,
         membership: membership,
         comparison: comparison,
         answer: answer
       }}
    else
      {:error, :not_found} -> {:error, {:resource_not_found, node_kind, node_id}}
      {:error, reason} -> {:error, normalize_tenant_access_error(reason, subject_name)}
    end
  end

  def generation_runtime_opts_for_tenant_subject(subject_name, opts \\ [])
      when is_binary(subject_name) do
    with {:ok, tenant} <-
           Threadr.ControlPlane.get_tenant_by_subject_name(
             subject_name,
             generation_ash_opts(opts)
           ) do
      tenant_generation_runtime_opts(tenant, semantic_runtime_opts(opts))
    else
      {:error, reason} -> {:error, normalize_tenant_access_error(reason, subject_name)}
    end
  end

  defp get_tenant_by_subject_name_system(subject_name, opts) do
    case Threadr.ControlPlane.get_tenant_by_subject_name(subject_name, system_ash_opts(opts)) do
      {:ok, tenant} -> {:ok, tenant}
      {:error, error} -> {:error, normalize_tenant_access_error(error, subject_name)}
    end
  end

  defp tenant_generation_runtime_opts(tenant, runtime_opts) do
    with {:ok, system_config} <- fetch_system_llm_config(context: %{system: true}),
         {:ok, tenant_config} <- fetch_tenant_llm_config(tenant.id, context: %{system: true}) do
      resolved_opts =
        []
        |> merge_generation_runtime_opts(build_system_generation_runtime_opts(system_config))
        |> merge_generation_runtime_opts(build_tenant_generation_runtime_opts(tenant_config))
        |> Keyword.merge(runtime_opts)

      {:ok, resolved_opts}
    end
  end

  defp answer_tenant_question_runtime(tenant, %QARequest{} = request) do
    QAOrchestrator.answer_question(
      tenant,
      request,
      ensure_embeddings: &ensure_recent_message_embeddings/2
    )
  end

  defp ensure_recent_message_embeddings(tenant, %QARequest{} = request) do
    ensure_recent_message_embeddings(tenant, QARequest.to_runtime_opts(request))
  end

  defp ensure_recent_message_embeddings(tenant, runtime_opts) when is_list(runtime_opts) do
    model = embedding_model(runtime_opts)

    provider =
      Keyword.get(
        runtime_opts,
        :embedding_provider,
        Application.get_env(:threadr, Threadr.ML, [])
        |> Keyword.fetch!(:embeddings)
        |> Keyword.fetch!(:provider)
      )

    missing_messages =
      from(m in "messages",
        left_join: me in "message_embeddings",
        on: me.message_id == m.id and me.model == ^model,
        where: is_nil(me.id),
        order_by: [desc: m.observed_at],
        limit: ^@embedding_catch_up_limit,
        select: %{id: m.id, body: m.body}
      )
      |> Repo.all(prefix: tenant.schema_name)

    Enum.each(missing_messages, fn message ->
      if is_binary(message.body) and String.trim(message.body) != "" do
        case provider.embed_document(
               message.body,
               EmbeddingProviderOpts.from_prefixed(runtime_opts, model: model)
             ) do
          {:ok, embedding_result} ->
            persist_message_embedding(tenant.schema_name, message.id, model, embedding_result)

          {:error, _reason} ->
            :ok
        end
      end
    end)

    :ok
  end

  defp qa_embedding_status(tenant, runtime_opts) do
    model = embedding_model(runtime_opts)

    total_messages =
      from(m in "messages",
        where: not is_nil(m.body) and m.body != "",
        select: count(m.id)
      )
      |> Repo.one(prefix: tenant.schema_name)

    embedded_messages =
      from(m in "messages",
        join: me in "message_embeddings",
        on: me.message_id == m.id and me.model == ^model,
        where: not is_nil(m.body) and m.body != "",
        select: count(m.id, :distinct)
      )
      |> Repo.one(prefix: tenant.schema_name)

    latest_unembedded_observed_at =
      from(m in "messages",
        left_join: me in "message_embeddings",
        on: me.message_id == m.id and me.model == ^model,
        where: not is_nil(m.body) and m.body != "" and is_nil(me.id),
        order_by: [desc: m.observed_at],
        limit: 1,
        select: m.observed_at
      )
      |> Repo.one(prefix: tenant.schema_name)

    missing_messages = max(total_messages - embedded_messages, 0)

    %{
      tenant_subject_name: tenant.subject_name,
      tenant_schema: tenant.schema_name,
      embedding_model: model,
      total_messages: total_messages,
      embedded_messages: embedded_messages,
      missing_messages: missing_messages,
      coverage_percent: coverage_percent(embedded_messages, total_messages),
      latest_unembedded_observed_at: latest_unembedded_observed_at,
      status: qa_embedding_status_label(total_messages, missing_messages)
    }
  end

  defp persist_message_embedding(tenant_schema, message_id, model, embedding_result) do
    MessageEmbedding
    |> Ash.Changeset.for_create(
      :create,
      %{
        message_id: message_id,
        model: model,
        dimensions: length(embedding_result.embedding),
        embedding: embedding_result.embedding,
        metadata: Map.get(embedding_result, :metadata, %{})
      },
      tenant: tenant_schema
    )
    |> Ash.create()
    |> case do
      {:ok, _embedding} -> :ok
      {:error, _reason} -> :ok
    end
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

  defp fetch_tenant_llm_config(tenant_id, opts) do
    case Threadr.ControlPlane.get_tenant_llm_config(tenant_id, opts) do
      {:ok, config} ->
        {:ok, config}

      {:error, %Ash.Error.Invalid{errors: errors}} = error ->
        if Enum.any?(errors, &match?(%Ash.Error.Query.NotFound{}, &1)) do
          {:ok, nil}
        else
          error
        end

      error ->
        error
    end
  end

  defp embedding_model(runtime_opts) do
    Keyword.get(
      runtime_opts,
      :embedding_model,
      Application.get_env(:threadr, Threadr.ML, [])
      |> Keyword.fetch!(:embeddings)
      |> Keyword.fetch!(:model)
    )
  end

  defp coverage_percent(_embedded_messages, 0), do: 100

  defp coverage_percent(embedded_messages, total_messages) do
    embedded_messages
    |> Kernel./(total_messages)
    |> Kernel.*(100)
    |> Float.round(1)
  end

  defp qa_embedding_status_label(0, _missing_messages), do: :empty
  defp qa_embedding_status_label(_total_messages, 0), do: :ready
  defp qa_embedding_status_label(_total_messages, _missing_messages), do: :catching_up

  defp fetch_system_llm_config(opts) do
    case Threadr.ControlPlane.get_system_llm_config("default", opts) do
      {:ok, config} ->
        {:ok, config}

      {:error, %Ash.Error.Invalid{errors: errors}} = error ->
        if Enum.any?(errors, &match?(%Ash.Error.Query.NotFound{}, &1)) do
          {:ok, nil}
        else
          error
        end

      error ->
        error
    end
  end

  defp build_system_generation_runtime_opts(nil), do: []

  defp build_system_generation_runtime_opts(config) do
    provider = resolve_generation_provider!(config.provider_name)

    []
    |> put_runtime_opt(:generation_provider, provider)
    |> put_runtime_opt(:generation_provider_name, config.provider_name)
    |> put_runtime_opt(
      :generation_endpoint,
      config.endpoint ||
        Threadr.ML.Generation.ProviderResolver.default_endpoint(config.provider_name)
    )
    |> put_runtime_opt(:generation_model, config.model)
    |> put_runtime_opt(:generation_api_key, config.api_key)
    |> put_runtime_opt(:generation_system_prompt, config.system_prompt)
    |> put_runtime_opt(:generation_temperature, config.temperature)
    |> put_runtime_opt(:generation_max_tokens, config.max_tokens)
  end

  defp build_tenant_generation_runtime_opts(nil), do: []
  defp build_tenant_generation_runtime_opts(%{use_system: true}), do: []

  defp build_tenant_generation_runtime_opts(config) do
    build_system_generation_runtime_opts(config)
  end

  defp merge_generation_runtime_opts(opts, []), do: opts
  defp merge_generation_runtime_opts(opts, other), do: Keyword.merge(opts, other)

  defp put_runtime_opt(opts, _key, nil), do: opts
  defp put_runtime_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp resolve_generation_provider!(provider_name) do
    case Threadr.ML.Generation.ProviderResolver.resolve(provider_name) do
      {:ok, provider} ->
        provider

      {:error, _reason} ->
        raise ArgumentError, "unsupported generation provider #{inspect(provider_name)}"
    end
  end

  defp semantic_ash_opts(opts) do
    RequestRuntimeOpts.drop(
      opts,
      [
        :query,
        :actor_handle,
        :channel_name,
        :compare_since,
        :compare_until
      ] ++ RequestRuntimeOpts.qa_keys()
    )
  end

  defp semantic_runtime_opts(opts) do
    RequestRuntimeOpts.take(opts, RequestRuntimeOpts.qa_keys())
  end

  defp generation_ash_opts(opts) do
    opts
    |> system_ash_opts()
    |> Keyword.drop([
      :provider,
      :provider_name,
      :endpoint,
      :model,
      :api_key,
      :system_prompt,
      :temperature,
      :max_tokens,
      :timeout,
      :generation_provider
    ])
    |> semantic_ash_opts()
  end

  defp system_ash_opts(opts) do
    opts
    |> Keyword.drop([:owner_user, :actor, :context])
    |> Keyword.put(:context, %{system: true})
  end
end
