defmodule Threadr.ControlPlane.KubernetesReqClient do
  @moduledoc """
  Minimal Kubernetes API client for Deployment apply and delete operations.
  """

  @behaviour Threadr.ControlPlane.KubernetesClient

  @service_account_token "/var/run/secrets/kubernetes.io/serviceaccount/token"
  @default_scheme "https"

  @impl true
  def apply_deployment(namespace, name, manifest) do
    request =
      request()
      |> Req.merge(
        method: :patch,
        url: deployment_url(namespace, name),
        headers: [{"content-type", "application/apply-patch+yaml"}],
        params: [fieldManager: "threadr", force: true],
        body: Jason.encode!(manifest)
      )

    case Req.request(request) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, Map.merge(%{"namespace" => namespace, "name" => name}, stringify_map(body))}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:kubernetes_apply_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def delete_deployment(namespace, name) do
    request =
      request()
      |> Req.merge(method: :delete, url: deployment_url(namespace, name))

    case Req.request(request) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 or status == 404 ->
        {:ok, Map.merge(%{"namespace" => namespace, "name" => name}, stringify_map(body))}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:kubernetes_delete_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def get_deployment(namespace, name) do
    request =
      request()
      |> Req.merge(method: :get, url: deployment_url(namespace, name))

    case Req.request(request) do
      {:ok, %Req.Response{status: 404}} ->
        {:ok, nil}

      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, stringify_map(body)}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:kubernetes_get_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request do
    config = Application.get_env(:threadr, __MODULE__, [])

    Req.new(
      base_url: base_url(config),
      auth: {:bearer, bearer_token(config)},
      receive_timeout: Keyword.get(config, :receive_timeout, 15_000),
      connect_options: [transport_opts: transport_opts(config)]
    )
  end

  defp deployment_url(namespace, name) do
    "/apis/apps/v1/namespaces/#{namespace}/deployments/#{name}"
  end

  defp base_url(config) do
    Keyword.get_lazy(config, :base_url, fn ->
      host = System.get_env("KUBERNETES_SERVICE_HOST") || "kubernetes.default.svc"
      port = System.get_env("KUBERNETES_SERVICE_PORT") || "443"
      "#{Keyword.get(config, :scheme, @default_scheme)}://#{host}:#{port}"
    end)
  end

  defp bearer_token(config) do
    Keyword.get_lazy(config, :bearer_token, fn ->
      @service_account_token
      |> File.read!()
      |> String.trim()
    end)
  end

  defp transport_opts(config) do
    case Keyword.get(config, :cacertfile) do
      nil -> []
      cacertfile -> [cacertfile: cacertfile]
    end
  end

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp stringify_map(_), do: %{}
end
