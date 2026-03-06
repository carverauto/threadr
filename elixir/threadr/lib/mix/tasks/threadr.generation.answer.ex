defmodule Mix.Tasks.Threadr.Generation.Answer do
  @shortdoc "Runs tenant-style QA through the configured generation provider"

  use Mix.Task

  alias Threadr.ML.Generation

  @switches [question: :string, context: :string, context_file: :string, system_prompt: :string]

  @impl true
  def run(args) do
    {opts, _argv, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    question = fetch_required_string(opts, :question)
    context = fetch_context(opts)

    Mix.Task.run("app.start")

    case Generation.answer_question(question, context, system_prompt: opts[:system_prompt]) do
      {:ok, result} ->
        Mix.shell().info("Generation answer complete")
        Mix.shell().info("provider: #{result.provider}")
        Mix.shell().info("model: #{result.model}")
        Mix.shell().info("answer:\n#{result.content}")

      {:error, reason} ->
        Mix.raise("generation answer failed: #{inspect(reason)}")
    end
  end

  defp fetch_context(opts) do
    case {opts[:context], opts[:context_file]} do
      {value, nil} when is_binary(value) and value != "" ->
        value

      {nil, path} when is_binary(path) and path != "" ->
        File.read!(path)

      {"", path} when is_binary(path) and path != "" ->
        File.read!(path)

      _ ->
        Mix.raise("missing required option --context or --context-file")
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
