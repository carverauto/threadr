defmodule Threadr.ML.Generation do
  @moduledoc """
  General-purpose prompt completion boundary for QA and summarization flows.
  """

  alias Threadr.ML.Generation.Request

  def complete(prompt_or_request, opts \\ [])

  def complete(prompt, opts) when is_binary(prompt) do
    request =
      Request.new(%{
        prompt: prompt,
        system_prompt: Keyword.get(opts, :system_prompt),
        context: Keyword.get(opts, :context, %{}),
        mode: Keyword.get(opts, :mode, :qa)
      })

    complete(request, opts)
  end

  def complete(%Request{} = request, opts) do
    provider = Keyword.get(opts, :provider, provider())
    provider.complete(request, provider_opts(opts))
  end

  def summarize(text, opts \\ []) when is_binary(text) do
    system_prompt =
      Keyword.get(
        opts,
        :system_prompt,
        "Summarize the provided tenant conversation faithfully and concisely."
      )

    complete(
      text,
      opts
      |> Keyword.put(:mode, :summarization)
      |> Keyword.put(:system_prompt, system_prompt)
    )
  end

  def answer_question(question, context, opts \\ [])
      when is_binary(question) and is_binary(context) do
    system_prompt =
      Keyword.get(
        opts,
        :system_prompt,
        "Answer the user's question using only the supplied context. Say when the context is insufficient."
      )

    prompt = """
    Context:
    #{context}

    Question:
    #{question}
    """

    complete(
      prompt,
      opts
      |> Keyword.put(:mode, :qa)
      |> Keyword.put(:system_prompt, system_prompt)
      |> Keyword.put(:context, %{"question" => question})
    )
  end

  defp provider do
    Application.get_env(:threadr, Threadr.ML, [])
    |> Keyword.fetch!(:generation)
    |> Keyword.fetch!(:provider)
  end

  defp provider_opts(opts) do
    Keyword.take(
      opts,
      [
        :endpoint,
        :model,
        :api_key,
        :system_prompt,
        :provider_name,
        :temperature,
        :max_tokens,
        :timeout
      ]
    )
  end
end
