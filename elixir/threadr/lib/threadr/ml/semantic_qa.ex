defmodule Threadr.ML.SemanticQA do
  @moduledoc """
  Tenant-scoped semantic retrieval plus question answering over embedded messages.
  """

  import Ecto.Query
  import Pgvector.Ecto.Query

  alias Threadr.ControlPlane
  alias Threadr.ML.{Embeddings, Generation}
  alias Threadr.Repo

  @default_limit 5

  def answer_question(tenant_subject_name, question, opts \\ [])
      when is_binary(tenant_subject_name) and is_binary(question) do
    with {:ok, tenant} <-
           ControlPlane.get_tenant_by_subject_name(tenant_subject_name, context: %{system: true}),
         {:ok, matches, query_result} <-
           search_messages_in_schema(tenant.schema_name, question, opts),
         citations = build_citations(matches),
         {:ok, generation_result} <-
           Generation.answer_question(question, build_context(citations), generation_opts(opts)) do
      {:ok,
       %{
         tenant_subject_name: tenant.subject_name,
         tenant_schema: tenant.schema_name,
         question: question,
         query: query_result,
         matches: matches,
         citations: citations,
         context: build_context(citations),
         answer: generation_result
       }}
    end
  end

  def search_messages(tenant_subject_name, question, opts \\ [])
      when is_binary(tenant_subject_name) and is_binary(question) do
    with {:ok, tenant} <-
           ControlPlane.get_tenant_by_subject_name(tenant_subject_name, context: %{system: true}),
         {:ok, matches, query_result} <-
           search_messages_in_schema(tenant.schema_name, question, opts),
         citations = build_citations(matches) do
      {:ok,
       %{
         tenant_subject_name: tenant.subject_name,
         tenant_schema: tenant.schema_name,
         question: question,
         query: query_result,
         matches: matches,
         citations: citations,
         context: build_context(citations)
       }}
    end
  end

  def build_context(citations) when is_list(citations) do
    citations
    |> Enum.map(fn citation ->
      timestamp =
        case citation.observed_at do
          %DateTime{} = observed_at -> DateTime.to_iso8601(observed_at)
          value -> to_string(value)
        end

      "[#{citation.label}] [#{timestamp}] ##{citation.channel_name} #{citation.actor_handle}: #{citation.body}"
    end)
    |> Enum.join("\n\n")
  end

  defp search_messages_in_schema(tenant_schema, question, opts) do
    with {:ok, query_embedding} <- Embeddings.embed_query(question, embedding_opts(opts)) do
      {:ok, query_vector} = Ash.Vector.new(query_embedding.embedding)
      model = Keyword.get(opts, :embedding_model, default_embedding_model())
      limit = Keyword.get(opts, :limit, @default_limit)

      matches =
        from(me in "message_embeddings",
          join: m in "messages",
          on: m.id == me.message_id,
          join: a in "actors",
          on: a.id == m.actor_id,
          join: c in "channels",
          on: c.id == m.channel_id,
          where: me.model == ^model,
          order_by: cosine_distance(me.embedding, ^query_vector),
          limit: ^limit,
          select: %{
            message_id: m.id,
            external_id: m.external_id,
            body: m.body,
            observed_at: m.observed_at,
            actor_handle: a.handle,
            actor_display_name: a.display_name,
            channel_name: c.name,
            model: me.model,
            distance: cosine_distance(me.embedding, ^query_vector)
          }
        )
        |> Repo.all(prefix: tenant_schema)
        |> Enum.map(&normalize_match/1)

      case matches do
        [] ->
          {:error, :no_message_embeddings}

        _ ->
          {:ok, matches,
           %{
             model: model,
             provider: query_embedding.provider,
             metadata: Map.get(query_embedding, :metadata, %{})
           }}
      end
    end
  end

  defp normalize_match(match) do
    distance = normalize_distance(match.distance)

    match
    |> Map.update!(:message_id, &normalize_identifier/1)
    |> Map.update!(:external_id, &normalize_identifier/1)
    |> Map.put(:distance, distance)
    |> Map.put(:similarity, 1.0 - distance)
  end

  defp build_citations(matches) do
    matches
    |> Enum.with_index(1)
    |> Enum.map(fn {match, index} ->
      %{
        label: "C#{index}",
        rank: index,
        message_id: match.message_id,
        external_id: match.external_id,
        body: match.body,
        observed_at: match.observed_at,
        actor_handle: match.actor_handle,
        actor_display_name: match.actor_display_name,
        channel_name: match.channel_name,
        similarity: match.similarity
      }
    end)
  end

  defp normalize_distance(%Decimal{} = distance), do: Decimal.to_float(distance)
  defp normalize_distance(distance) when is_float(distance), do: distance
  defp normalize_distance(distance) when is_integer(distance), do: distance / 1

  defp normalize_identifier(nil), do: nil

  defp normalize_identifier(value) when is_binary(value) do
    if String.valid?(value) do
      value
    else
      case Ecto.UUID.load(value) do
        {:ok, uuid} -> uuid
        :error -> Base.encode16(value, case: :lower)
      end
    end
  end

  defp normalize_identifier(value), do: to_string(value)

  defp default_embedding_model do
    Application.get_env(:threadr, Threadr.ML, [])
    |> Keyword.fetch!(:embeddings)
    |> Keyword.fetch!(:model)
  end

  defp embedding_opts(opts) do
    provider =
      Keyword.get(
        opts,
        :embedding_provider,
        Application.get_env(:threadr, Threadr.ML, [])
        |> Keyword.fetch!(:embeddings)
        |> Keyword.fetch!(:provider)
      )

    opts
    |> Keyword.take([:embedding_model, :document_prefix, :query_prefix])
    |> Enum.reduce([], fn
      {:embedding_model, value}, acc -> Keyword.put(acc, :model, value)
      {key, value}, acc -> Keyword.put(acc, key, value)
    end)
    |> Keyword.put(:provider, provider)
  end

  defp generation_opts(opts) do
    provider =
      Keyword.get(
        opts,
        :generation_provider,
        Application.get_env(:threadr, Threadr.ML, [])
        |> Keyword.fetch!(:generation)
        |> Keyword.fetch!(:provider)
      )

    opts
    |> Keyword.take([
      :generation_model,
      :generation_endpoint,
      :generation_api_key,
      :generation_system_prompt,
      :generation_provider_name,
      :generation_temperature,
      :generation_max_tokens,
      :generation_timeout
    ])
    |> Enum.reduce([provider: provider], fn
      {:generation_model, value}, acc -> Keyword.put(acc, :model, value)
      {:generation_endpoint, value}, acc -> Keyword.put(acc, :endpoint, value)
      {:generation_api_key, value}, acc -> Keyword.put(acc, :api_key, value)
      {:generation_system_prompt, value}, acc -> Keyword.put(acc, :system_prompt, value)
      {:generation_provider_name, value}, acc -> Keyword.put(acc, :provider_name, value)
      {:generation_temperature, value}, acc -> Keyword.put(acc, :temperature, value)
      {:generation_max_tokens, value}, acc -> Keyword.put(acc, :max_tokens, value)
      {:generation_timeout, value}, acc -> Keyword.put(acc, :timeout, value)
    end)
  end
end
