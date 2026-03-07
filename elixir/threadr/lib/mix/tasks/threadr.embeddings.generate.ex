defmodule Mix.Tasks.Threadr.Embeddings.Generate do
  @shortdoc "Generates and publishes a local embedding for a tenant message"

  use Mix.Task

  alias Threadr.ControlPlane
  alias Threadr.ML.Embeddings

  @switches [tenant_subject: :string, message_id: :string]

  @impl true
  def run(args) do
    {opts, _argv, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    tenant_subject = fetch_required_string(opts, :tenant_subject)
    message_id = fetch_required_string(opts, :message_id)

    Mix.Task.run("app.start")
    Mix.Task.run("threadr.nats.setup")

    {:ok, tenant} =
      ControlPlane.get_tenant_by_subject_name(tenant_subject, context: %{system: true})

    {:ok, envelope} =
      Embeddings.generate_for_message_id(message_id, tenant.subject_name, tenant.schema_name)

    Mix.shell().info("Published local embedding result")
    Mix.shell().info("tenant_subject: #{tenant.subject_name}")
    Mix.shell().info("message_id: #{message_id}")
    Mix.shell().info("event_id: #{envelope.id}")
  end

  defp fetch_required_string(opts, key) do
    case opts[key] do
      value when is_binary(value) and value != "" ->
        value

      _ ->
        Mix.raise("missing required option --#{key |> to_string() |> String.replace("_", "-")}")
    end
  end
end
