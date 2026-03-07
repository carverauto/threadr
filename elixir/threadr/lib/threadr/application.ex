defmodule Threadr.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        Threadr.Repo,
        Threadr.ControlPlane.BotOperationDispatcher,
        Threadr.ControlPlane.BotStatusObserver,
        Threadr.Messaging.Supervisor,
        Threadr.Ingest.Supervisor,
        {DNSCluster, query: Application.get_env(:threadr, :dns_cluster_query) || :ignore}
      ] ++ web_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Threadr.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp web_children do
    if Application.get_env(:threadr, :web_enabled, true) do
      [
        ThreadrWeb.Telemetry,
        {AshAuthentication.Supervisor, otp_app: :threadr},
        {Phoenix.PubSub, name: Threadr.PubSub},
        ThreadrWeb.Endpoint
      ]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ThreadrWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
