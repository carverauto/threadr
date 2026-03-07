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
        receive_timeout: config[:timeout],
        json: request_body(config, messages)
      )

    case response.status do
      status when status in 200..299 ->
        response.body
        |> normalize_body()
        |> parse_success(config, request)

      status ->
        {:error, {:generation_request_failed, status, normalize_body(response.body)}}
    end
  rescue
    error ->
      {:error, {:generation_failed, Exception.message(error)}}
  end

  defp parse_success({:error, reason}, _config, _request) do
    {:error, {:unexpected_generation_response, reason}}
  end

  defp parse_success(body, config, request) when is_map(body) do
    case get_in(body, ["choices", Access.at(0), "message", "content"]) do
      content when is_binary(content) ->
        {:ok,
         %Result{
           content: content,
           model: body["model"] || config[:model],
           provider: config[:provider_name] || "chat_completions",
           metadata:
             Map.take(body, ["id", "usage", "system_fingerprint"])
             |> Map.put(
               "finish_reason",
               get_in(body, ["choices", Access.at(0), "finish_reason"])
             )
             |> Map.put("mode", request.mode)
             |> Map.put("context", request.context)
         }}

      _ ->
        {:error, {:unexpected_generation_response, body}}
    end
  end

  defp parse_success(body, _config, _request) do
    {:error, {:unexpected_generation_response, body}}
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

  defp request_body(config, messages) do
    %{
      model: config[:model],
      messages: messages
    }
    |> maybe_put(:temperature, config[:temperature])
    |> maybe_put(:max_tokens, config[:max_tokens])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_body(body) when is_map(body), do: body

  defp normalize_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      {:error, reason} -> {:error, {:invalid_json_response, reason, body}}
    end
  end

  defp normalize_body(body), do: body

  defp config(opts) do
    Application.get_env(:threadr, Threadr.ML, [])
    |> Keyword.fetch!(:generation)
    |> Keyword.merge(opts)
  end
end
