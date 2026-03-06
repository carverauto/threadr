defmodule Mix.Tasks.Threadr.Generation.Complete do
  @shortdoc "Runs a prompt through the configured generation provider"

  use Mix.Task

  alias Threadr.ML.Generation

  @switches [prompt: :string, system_prompt: :string]

  @impl true
  def run(args) do
    {opts, _argv, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    prompt = fetch_required_string(opts, :prompt)
    Mix.Task.run("app.start")

    case Generation.complete(prompt, system_prompt: opts[:system_prompt]) do
      {:ok, result} ->
        Mix.shell().info("Generation complete")
        Mix.shell().info("provider: #{result.provider}")
        Mix.shell().info("model: #{result.model}")
        Mix.shell().info("content:\n#{result.content}")

      {:error, reason} ->
        Mix.raise("generation failed: #{inspect(reason)}")
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
