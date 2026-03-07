defmodule Threadr.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ThreadrWeb.Telemetry,
      Threadr.Repo,
      {AshAuthentication.Supervisor, otp_app: :threadr},
      Threadr.ControlPlane.BotOperationDispatcher,
      Threadr.ControlPlane.BotStatusObserver,
      Threadr.Messaging.Supervisor,
      Threadr.Ingest.Supervisor,
      {DNSCluster, query: Application.get_env(:threadr, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Threadr.PubSub},
      # Start a worker by calling: Threadr.Worker.start_link(arg)
      # {Threadr.Worker, arg},
      # Start to serve requests, typically the last entry
      ThreadrWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Threadr.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ThreadrWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
