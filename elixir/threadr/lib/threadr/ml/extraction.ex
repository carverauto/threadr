defmodule Threadr.ML.Extraction do
  @moduledoc """
  Provider-neutral structured extraction over tenant-scoped chat messages.
  """

  alias Threadr.ML.ExtractionProviderOpts
  alias Threadr.ML.Extraction.Request
  alias Threadr.TenantData.Message

  def extract(%Request{} = request, opts \\ []) do
    provider = Keyword.get(opts, :provider, provider())
    provider.extract(request, provider_opts(opts))
  end

  def extract_message(%Message{} = message, tenant_subject_name, opts \\ []) do
    request =
      Request.new(%{
        tenant_subject_name: tenant_subject_name,
        message_id: message.id,
        body: message.body,
        observed_at: message.observed_at,
        context: %{
          "actor_id" => message.actor_id,
          "channel_id" => message.channel_id,
          "metadata" => message.metadata
        }
      })

    extract(request, opts)
  end

  defp provider do
    Application.get_env(:threadr, Threadr.ML, [])
    |> Keyword.fetch!(:extraction)
    |> Keyword.fetch!(:provider)
  end

  defp provider_opts(opts) do
    ExtractionProviderOpts.take_direct(opts)
  end
end
