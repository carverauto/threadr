defmodule Threadr.Messaging.Smoke do
  @moduledoc """
  Helpers for verifying tenant-scoped JetStream publish and Broadway ingest locally.
  """

  import Ash.Expr
  require Ash.Query

  alias Threadr.ControlPlane
  alias Threadr.ControlPlane.Service
  alias Threadr.Events.{ChatMessage, Envelope}
  alias Threadr.Messaging.{Publisher, Topology}
  alias Threadr.TenantData.{Message, MessageMention, Relationship}

  @default_tenant_name "Threadr Smoke Tenant"
  @default_platform "discord"
  @default_channel "ops"
  @default_actor "smoke-bot"
  @default_mentions ["observer"]
  @default_timeout_ms 5_000
  @default_poll_interval_ms 250
  @relationship_type "MENTIONED"

  def run(opts \\ []) do
    tenant = ensure_tenant!(opts)
    mentions = normalize_mentions(Keyword.get(opts, :mentions, @default_mentions))
    external_id = Keyword.get(opts, :external_id, Ecto.UUID.generate())
    body = Keyword.get(opts, :body, default_body(mentions))

    envelope =
      Envelope.new(
        ChatMessage.from_map(%{
          platform: Keyword.get(opts, :platform, @default_platform),
          channel: Keyword.get(opts, :channel, @default_channel),
          actor: Keyword.get(opts, :actor, @default_actor),
          body: body,
          mentions: mentions,
          observed_at: DateTime.utc_now(),
          raw: %{"text" => body}
        }),
        "chat.message",
        Topology.subject_for(:chat_messages, tenant.subject_name),
        %{id: external_id}
      )

    started_at = System.monotonic_time(:millisecond)
    :ok = Publisher.publish(envelope)

    result =
      await_graph_persistence(
        tenant.schema_name,
        external_id,
        length(mentions),
        Keyword.get(opts, :timeout_ms, @default_timeout_ms),
        Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms)
      )

    %{
      tenant_id: tenant.id,
      tenant_subject_name: tenant.subject_name,
      tenant_schema: tenant.schema_name,
      external_id: external_id,
      elapsed_ms: System.monotonic_time(:millisecond) - started_at,
      body: body,
      mentions: mentions,
      result: result
    }
  end

  defp ensure_tenant!(opts) do
    tenant_name =
      opts
      |> Keyword.get(:tenant_name, @default_tenant_name)
      |> normalize_required_string(:tenant_name)

    normalized_attrs =
      %{name: tenant_name}
      |> maybe_put(:slug, normalize_optional_string(Keyword.get(opts, :tenant_slug)))
      |> maybe_put(:schema_name, normalize_optional_string(Keyword.get(opts, :tenant_schema)))
      |> maybe_put(
        :subject_name,
        normalize_optional_string(Keyword.get(opts, :tenant_subject_name))
      )
      |> Service.normalize_tenant_attrs()

    case ControlPlane.get_tenant_by_subject_name(
           normalized_attrs.subject_name,
           context: %{system: true}
         ) do
      {:ok, tenant} when not is_nil(tenant) ->
        tenant

      _ ->
        case Service.create_tenant(normalized_attrs) do
          {:ok, tenant} -> tenant
          {:error, reason} -> raise "failed to provision smoke tenant: #{inspect(reason)}"
        end
    end
  end

  defp await_graph_persistence(
         schema_name,
         external_id,
         mention_count,
         timeout_ms,
         poll_interval_ms
       ) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    do_await_graph_persistence(
      schema_name,
      external_id,
      mention_count,
      deadline,
      poll_interval_ms
    )
  end

  defp do_await_graph_persistence(
         schema_name,
         external_id,
         mention_count,
         deadline,
         poll_interval_ms
       ) do
    case fetch_graph(schema_name, external_id) do
      nil ->
        if System.monotonic_time(:millisecond) >= deadline do
          raise "timed out waiting for message #{external_id} in tenant schema #{schema_name}"
        end

        Process.sleep(poll_interval_ms)

        do_await_graph_persistence(
          schema_name,
          external_id,
          mention_count,
          deadline,
          poll_interval_ms
        )

      graph ->
        if graph.mention_count >= mention_count and graph.relationship_count >= mention_count do
          graph
        else
          if System.monotonic_time(:millisecond) >= deadline do
            raise(
              "timed out waiting for message graph completion #{external_id} in tenant schema #{schema_name}"
            )
          end

          Process.sleep(poll_interval_ms)

          do_await_graph_persistence(
            schema_name,
            external_id,
            mention_count,
            deadline,
            poll_interval_ms
          )
        end
    end
  end

  def fetch_graph!(schema_name, external_id) do
    fetch_graph(schema_name, external_id) ||
      raise("message #{external_id} not found in tenant schema #{schema_name}")
  end

  defp fetch_graph(schema_name, external_id) do
    query =
      Message
      |> Ash.Query.filter(expr(external_id == ^external_id))

    case Ash.read_one!(query, tenant: schema_name) do
      nil ->
        nil

      message ->
        relationships = fetch_relationships(schema_name, message.id)

        %{
          message: message,
          mention_count: count_mentions(schema_name, message.id),
          relationship_count: length(relationships),
          relationships: relationships
        }
    end
  end

  defp count_mentions(schema_name, message_id) do
    query =
      MessageMention
      |> Ash.Query.filter(expr(message_id == ^message_id))

    query
    |> Ash.read!(tenant: schema_name)
    |> length()
  end

  defp fetch_relationships(schema_name, message_id) do
    query =
      Relationship
      |> Ash.Query.filter(
        expr(source_message_id == ^message_id and relationship_type == ^@relationship_type)
      )

    Ash.read!(query, tenant: schema_name)
  end

  defp normalize_mentions(mentions) when is_list(mentions) do
    mentions
    |> Enum.map(&normalize_required_string(&1, :mention))
    |> Enum.uniq()
  end

  defp normalize_mentions(mentions) when is_binary(mentions) do
    mentions
    |> String.split(",", trim: true)
    |> normalize_mentions()
  end

  defp default_body([]), do: "threadr smoke message"

  defp default_body(mentions) do
    handles =
      mentions
      |> Enum.map(&("@" <> &1))
      |> Enum.join(" ")

    "threadr smoke message " <> handles
  end

  defp maybe_put(attrs, _key, nil), do: attrs
  defp maybe_put(attrs, key, value), do: Map.put(attrs, key, value)

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_required_string(value, key) when is_binary(value) do
    case normalize_optional_string(value) do
      nil -> raise ArgumentError, "expected #{inspect(key)} to be a non-empty string"
      trimmed -> trimmed
    end
  end
end
