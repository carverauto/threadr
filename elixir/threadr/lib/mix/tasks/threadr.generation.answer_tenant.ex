defmodule Mix.Tasks.Threadr.Generation.AnswerTenant do
  @shortdoc "Retrieves tenant message context and answers a question through the configured generation provider"

  use Mix.Task

  alias Threadr.ML.SemanticQA

  @switches [tenant_subject: :string, question: :string, limit: :integer]

  @impl true
  def run(args) do
    {opts, _argv, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    tenant_subject = fetch_required_string(opts, :tenant_subject)
    question = fetch_required_string(opts, :question)

    Mix.Task.run("app.start")

    case SemanticQA.answer_question(tenant_subject, question, limit: opts[:limit] || 5) do
      {:ok, result} ->
        Mix.shell().info("Tenant semantic QA complete")
        Mix.shell().info("tenant_subject: #{result.tenant_subject_name}")
        Mix.shell().info("retrieved_messages: #{length(result.matches)}")
        Mix.shell().info("generation_provider: #{result.answer.provider}")
        Mix.shell().info("generation_model: #{result.answer.model}")
        Mix.shell().info("answer:\n#{result.answer.content}")

      {:error, reason} ->
        Mix.raise("tenant semantic QA failed: #{inspect(reason)}")
    end
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
