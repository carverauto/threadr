defmodule Threadr.Messaging.Topology do
  @moduledoc """
  Central accessors for the rewrite's NATS JetStream topology.
  """

  alias Gnat.Jetstream.API.{Consumer, Stream}

  @config_key __MODULE__

  def connection_name do
    config!(:connection_name)
  end

  def connection_settings do
    config!(:connections)
  end

  def connection_retry_backoff do
    config!(:connection_retry_backoff)
  end

  def messaging_enabled? do
    config!(:messaging_enabled)
  end

  def pipeline_enabled? do
    config!(:pipeline_enabled)
  end

  def broadway_config do
    config!(:broadway)
  end

  def stream_name do
    config!(:stream_name)
  end

  def consumer_name do
    config!(:consumer_name)
  end

  def subjects do
    config!(:subjects)
  end

  def subject(key) do
    subjects()
    |> Map.fetch!(key)
  end

  def subject_for(key, tenant_subject_name) when is_binary(tenant_subject_name) do
    tenant_subject_name = validate_tenant_subject_name!(tenant_subject_name)
    suffix = subject(key)

    Enum.join(["threadr", "tenants", tenant_subject_name, suffix], ".")
  end

  def tenant_subject_name_from_subject(subject) when is_binary(subject) do
    case String.split(subject, ".") do
      ["threadr", "tenants", tenant_subject_name | _rest] ->
        {:ok, validate_tenant_subject_name!(tenant_subject_name)}

      _ ->
        {:error, {:invalid_tenant_subject, subject}}
    end
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  def event_subjects do
    [subject(:tenant_wildcard)]
  end

  def connection_supervisor_config do
    %{
      name: connection_name(),
      backoff_period: connection_retry_backoff(),
      connection_settings: connection_settings()
    }
  end

  def stream_spec do
    %Stream{name: stream_name(), subjects: event_subjects()}
  end

  def consumer_spec do
    %Consumer{
      stream_name: stream_name(),
      durable_name: consumer_name(),
      ack_policy: :explicit,
      replay_policy: :instant,
      deliver_policy: :all
    }
  end

  defp validate_tenant_subject_name!(tenant_subject_name) do
    if tenant_subject_name =~ ~r/^[A-Za-z0-9_-]+$/ do
      tenant_subject_name
    else
      raise ArgumentError,
            "tenant subject name must use only NATS-safe token characters: #{inspect(tenant_subject_name)}"
    end
  end

  defp config!(key) do
    case Application.get_env(:threadr, @config_key, []) do
      [] -> raise ArgumentError, "missing configuration for #{inspect(@config_key)}"
      config -> Keyword.fetch!(config, key)
    end
  end
end
