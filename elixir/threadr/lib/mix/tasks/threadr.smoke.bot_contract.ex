defmodule Mix.Tasks.Threadr.Smoke.BotContract do
  @shortdoc "Provisions a control-plane bot and emits a ThreadrBot contract"
  @moduledoc """
  Creates a smoke tenant and bot through the control plane, then drains the
  reconciliation outbox so the machine-authenticated contract feed exposes a
  real `ThreadrBot` document for operator integration testing.

  Examples:

      mix threadr.smoke.bot_contract
      mix threadr.smoke.bot_contract --tenant-name "Acme Threat Intel" --bot-name irc-main
  """

  use Mix.Task

  alias Threadr.ControlPlane.Smoke

  @switches [
    tenant_name: :string,
    tenant_subject: :string,
    bot_name: :string,
    platform: :string,
    channel: :string
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    %{tenant: tenant, bot: bot, contract: contract} = Smoke.provision_bot_contract!(opts)

    Mix.shell().info("Threadr control-plane bot contract is ready")
    Mix.shell().info("tenant_subject: #{tenant.subject_name}")
    Mix.shell().info("bot_id: #{bot.id}")
    Mix.shell().info("deployment_name: #{contract.deployment_name}")

    Mix.shell().info(
      "contract_url: /api/control-plane/tenants/#{tenant.subject_name}/bots/#{bot.id}/contract"
    )
  end
end
