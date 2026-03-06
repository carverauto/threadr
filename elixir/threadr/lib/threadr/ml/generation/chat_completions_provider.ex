defmodule Threadr.ML.Generation.ChatCompletionsProvider do
  @moduledoc """
  Generic chat-completions client that can target OpenAI-compatible endpoints.
  """

  @behaviour Threadr.ML.Generation.Provider

  alias Threadr.ML.Generation.{Request, Result}

  @impl true
  def complete(%Request{} = request, opts) do
    config = config(opts)

    messages =
      []
      |> maybe_add_system_message(request.system_prompt || config[:system_prompt])
      |> Kernel.++([%{role: "user", content: request.prompt}])

    headers =
      [{"content-type", "application/json"}]
      |> maybe_add_bearer_token(config[:api_key])

    response =
      Req.post!(
        config[:endpoint],
        headers: headers,
        json: %{
          model: config[:model],
          messages: messages
        }
      )

    case response.status do
      status when status in 200..299 ->
        parse_success(response.body, config, request)

      status ->
        {:error, {:generation_request_failed, status, response.body}}
    end
  rescue
    error ->
      {:error, {:generation_failed, Exception.message(error)}}
  end

  defp parse_success(body, config, request) when is_map(body) do
    case get_in(body, ["choices", Access.at(0), "message", "content"]) do
      content when is_binary(content) ->
        {:ok,
         %Result{
           content: content,
           model: config[:model],
           provider: "chat_completions",
           metadata:
             Map.take(body, ["id", "usage"])
             |> Map.put("mode", request.mode)
             |> Map.put("context", request.context)
         }}

      _ ->
        {:error, {:unexpected_generation_response, body}}
    end
  end

  defp maybe_add_system_message(messages, nil), do: messages
  defp maybe_add_system_message(messages, ""), do: messages

  defp maybe_add_system_message(messages, system_prompt) do
    messages ++ [%{role: "system", content: system_prompt}]
  end

  defp maybe_add_bearer_token(headers, nil), do: headers
  defp maybe_add_bearer_token(headers, ""), do: headers

  defp maybe_add_bearer_token(headers, api_key) do
    [{"authorization", "Bearer #{api_key}"} | headers]
  end

  defp config(opts) do
    Application.get_env(:threadr, Threadr.ML, [])
    |> Keyword.fetch!(:generation)
    |> Keyword.merge(opts)
  end
end
