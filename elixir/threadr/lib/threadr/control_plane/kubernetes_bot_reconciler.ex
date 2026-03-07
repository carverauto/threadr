defmodule Threadr.ControlPlane.KubernetesBotReconciler do
  @moduledoc """
  Kubernetes reconciler for tenant bot workloads.
  """

  @behaviour Threadr.ControlPlane.BotReconciler

  alias Threadr.ControlPlane

  @impl true
  def reconcile(bot, operation) do
    with {:ok, tenant} <- ControlPlane.get_tenant(bot.tenant_id, context: %{system: true}),
         deployment_name <- deployment_name(bot, tenant),
         namespace <- tenant.kubernetes_namespace,
         generation <- bot.desired_generation + 1 do
      {:ok,
       %{
         bot_updates: %{
           deployment_name: deployment_name,
           desired_generation: generation
         },
         controller_contract: %{
           tenant_id: tenant.id,
           bot_id: bot.id,
           generation: generation,
           operation: operation.operation,
           deployment_name: deployment_name,
           namespace: namespace,
           contract: controller_contract(bot, tenant, deployment_name, namespace, generation)
         },
         operation_payload: %{
           "controller_contract" => %{
             "generation" => generation,
             "namespace" => namespace,
             "deployment_name" => deployment_name
           }
         }
       }}
    end
  end

  defp controller_contract(bot, tenant, deployment_name, namespace, generation) do
    config = Application.get_env(:threadr, __MODULE__, [])

    %{
      "apiVersion" => "cache.threadr.ai/v1alpha1",
      "kind" => "ThreadrBot",
      "metadata" => %{
        "name" => deployment_name,
        "namespace" => namespace,
        "labels" => labels(bot, tenant)
      },
      "spec" => %{
        "desiredState" => bot.desired_state,
        "platform" => bot.platform,
        "channels" => bot.channels,
        "controlPlane" => %{
          "tenantId" => tenant.id,
          "tenantSubject" => tenant.subject_name,
          "botId" => bot.id,
          "generation" => generation
        },
        "workload" => %{
          "deploymentName" => deployment_name,
          "containerName" => Keyword.get(config, :container_name, "threadr-bot"),
          "image" => container_image(bot, config),
          "replicas" => replicas(bot),
          "env" => env_vars(bot, tenant)
        }
      }
    }
  end

  defp container_image(bot, config) do
    Threadr.ControlPlane.BotConfig.image(bot.settings) || Keyword.fetch!(config, :default_image)
  end

  defp env_vars(bot, tenant) do
    base_env = [
      %{"name" => "THREADR_INGEST_ENABLED", "value" => "true"},
      %{"name" => "THREADR_BOT_ID", "value" => bot.id},
      %{"name" => "THREADR_TENANT_ID", "value" => tenant.id},
      %{"name" => "THREADR_TENANT_SUBJECT", "value" => tenant.subject_name},
      %{"name" => "THREADR_PLATFORM", "value" => bot.platform},
      %{"name" => "THREADR_CHANNELS", "value" => Jason.encode!(bot.channels)}
    ]

    settings_env =
      bot.settings
      |> Threadr.ControlPlane.BotConfig.env()
      |> Enum.map(fn {key, value} -> %{"name" => key, "value" => to_string(value)} end)

    base_env ++ settings_env
  end

  defp labels(bot, tenant) do
    %{
      "app.kubernetes.io/name" => "threadr-bot",
      "threadr.io/bot-id" => bot.id,
      "threadr.io/tenant-id" => tenant.id,
      "threadr.io/tenant-subject" => tenant.subject_name
    }
  end

  defp deployment_name(%{deployment_name: deployment_name}, _tenant)
       when is_binary(deployment_name) and byte_size(deployment_name) > 0,
       do: deployment_name

  defp deployment_name(bot, tenant) do
    [
      "threadr",
      dns_token(tenant.subject_name),
      dns_token(bot.name),
      short_id(bot.id)
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("-")
    |> String.slice(0, 63)
    |> String.trim("-")
  end

  defp dns_token(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9-]+/u, "-")
    |> String.replace(~r/-{2,}/u, "-")
    |> String.trim("-")
  end

  defp short_id(id) when is_binary(id) do
    id
    |> String.replace("-", "")
    |> String.slice(0, 8)
  end

  defp replicas(%{desired_state: "stopped"}), do: 0
  defp replicas(%{desired_state: "deleted"}), do: 0
  defp replicas(_bot), do: 1
end
