defmodule Threadr.ML.GraphRAG do
  @moduledoc """
  Tenant-scoped graph-aware retrieval and summarization on top of semantic matches
  plus Apache AGE neighborhood context.
  """

  alias Threadr.ControlPlane

  alias Threadr.ML.{
    ChannelLabel,
    Generation,
    GenerationProviderOpts,
    QARequest,
    SemanticQA,
    SummaryRequest
  }

  alias Threadr.TenantData.Graph

  @default_graph_message_limit 5

  def answer_question(tenant_subject_name, %QARequest{} = request)
      when is_binary(tenant_subject_name) do
    with {:ok, retrieval} <-
           retrieve_context(
             tenant_subject_name,
             request.question,
             QARequest.to_runtime_opts(request)
           ),
         {:ok, answer} <-
           Generation.answer_question(
             request.question,
             retrieval.context,
             generation_opts(
               QARequest.to_runtime_opts(request),
               context: %{
                 "question" => request.question,
                 "semantic_citations" => Enum.map(retrieval.semantic.citations, & &1.label),
                 "graph_citations" => Enum.map(retrieval.graph.citations, & &1.label)
               }
             )
           ) do
      {:ok,
       %{
         tenant_subject_name: retrieval.tenant_subject_name,
         tenant_schema: retrieval.tenant_schema,
         question: request.question,
         semantic: retrieval.semantic,
         graph: retrieval.graph,
         context: retrieval.context,
         answer: answer
       }}
    end
  end

  def summarize_topic(tenant_subject_name, %SummaryRequest{} = request)
      when is_binary(tenant_subject_name) do
    with {:ok, retrieval} <-
           retrieve_context(
             tenant_subject_name,
             request.topic,
             SummaryRequest.to_runtime_opts(request)
           ),
         prompt <- summary_prompt(request.topic, retrieval.context),
         {:ok, summary} <-
           Generation.summarize(
             prompt,
             generation_opts(
               SummaryRequest.to_runtime_opts(request),
               context: %{
                 "topic" => request.topic,
                 "semantic_citations" => Enum.map(retrieval.semantic.citations, & &1.label),
                 "graph_citations" => Enum.map(retrieval.graph.citations, & &1.label)
               },
               system_prompt:
                 "Summarize the tenant activity relevant to the topic using only the supplied evidence. Cite labels like [C1] or [G1] when useful."
             )
           ) do
      {:ok,
       %{
         tenant_subject_name: retrieval.tenant_subject_name,
         tenant_schema: retrieval.tenant_schema,
         topic: request.topic,
         semantic: retrieval.semantic,
         graph: retrieval.graph,
         context: retrieval.context,
         summary: summary
       }}
    end
  end

  def retrieve_context(tenant_subject_name, question, opts \\ [])
      when is_binary(tenant_subject_name) and is_binary(question) do
    with {:ok, tenant} <-
           ControlPlane.get_tenant_by_subject_name(tenant_subject_name, context: %{system: true}),
         {:ok, semantic} <-
           SemanticQA.search_messages(tenant.subject_name, question, opts),
         {:ok, graph_neighborhood} <-
           Graph.neighborhood(
             Enum.map(semantic.matches, & &1.message_id),
             tenant.schema_name,
             graph_message_limit:
               Keyword.get(opts, :graph_message_limit, @default_graph_message_limit)
           ) do
      graph = build_graph_result(graph_neighborhood)

      {:ok,
       %{
         tenant_subject_name: tenant.subject_name,
         tenant_schema: tenant.schema_name,
         question: question,
         semantic: semantic,
         graph: graph,
         context: build_context(semantic, graph)
       }}
    end
  end

  def build_context(semantic, graph) do
    [
      "Semantic Evidence:\n" <> semantic.context,
      "Graph Context:\n" <> build_graph_context(graph)
    ]
    |> Enum.join("\n\n")
  end

  def build_graph_context(graph) do
    sections =
      [
        actor_section(graph.actors),
        relationship_section(graph.relationships),
        related_message_section(graph.citations)
      ]
      |> Enum.reject(&(&1 == nil or &1 == ""))

    if sections == [] do
      "No graph neighborhood context available."
    else
      Enum.join(sections, "\n\n")
    end
  end

  defp build_graph_result(graph_neighborhood) do
    citations =
      graph_neighborhood.messages
      |> Enum.with_index(1)
      |> Enum.map(fn {message, index} ->
        Map.put(message, :label, "G#{index}")
      end)

    %{
      actors: graph_neighborhood.actors,
      relationships: graph_neighborhood.relationships,
      related_messages: graph_neighborhood.messages,
      citations: citations,
      context: nil
    }
    |> then(fn graph -> Map.put(graph, :context, build_graph_context(graph)) end)
  end

  defp actor_section([]), do: nil

  defp actor_section(actors) do
    lines =
      actors
      |> Enum.map(fn actor ->
        handle = actor.display_name || actor.handle || actor.actor_id
        "- #{handle} (#{actor.role})"
      end)

    "Actors:\n" <> Enum.join(lines, "\n")
  end

  defp relationship_section([]), do: nil

  defp relationship_section(relationships) do
    lines =
      relationships
      |> Enum.map(fn relationship ->
        weight =
          case relationship.weight do
            nil -> ""
            value -> " weight=#{value}"
          end

        "- #{relationship.from_actor_handle} #{relationship.relationship_type} #{relationship.to_actor_handle}#{weight}"
      end)

    "Relationships:\n" <> Enum.join(lines, "\n")
  end

  defp related_message_section([]), do: nil

  defp related_message_section(citations) do
    lines =
      citations
      |> Enum.map(fn citation ->
        timestamp =
          case citation.observed_at do
            nil -> "unknown"
            value -> to_string(value)
          end

        "- [#{citation.label}] [#{timestamp}] #{ChannelLabel.format(citation.channel_name)} #{citation.actor_handle}: #{citation.body}"
      end)

    "Related Messages:\n" <> Enum.join(lines, "\n")
  end

  defp summary_prompt(topic, context) do
    """
    Topic:
    #{topic}

    Evidence:
    #{context}
    """
  end

  defp generation_opts(opts, extra) do
    GenerationProviderOpts.from_prefixed(opts, extra)
  end
end
