defmodule Threadr.ML.Generation.AnthropicProvider do
  @moduledoc """
  Native Anthropic Messages API adapter.
  """

  @behaviour Threadr.ML.Generation.Provider

  alias Threadr.ML.Generation.{Request, Result}

  @anthropic_version "2023-06-01"

  @impl true
  def complete(%Request{} = request, opts) do
    config = config(opts)

    response =
      Req.post!(
        config[:endpoint],
        headers: headers(config[:api_key]),
        receive_timeout: config[:timeout],
        json: request_body(config, request)
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

  defp headers(api_key) do
    [
      {"content-type", "application/json"},
      {"x-api-key", api_key || ""},
      {"anthropic-version", @anthropic_version}
    ]
  end

  defp request_body(config, request) do
    %{
      model: config[:model],
      system: request.system_prompt || config[:system_prompt],
      messages: [
        %{
          role: "user",
          content: [
            %{
              type: "text",
              text: request.prompt
            }
          ]
        }
      ]
    }
    |> maybe_put(:temperature, config[:temperature])
    |> maybe_put(:max_tokens, config[:max_tokens] || 1024)
  end

  defp parse_success({:error, reason}, _config, _request) do
    {:error, {:unexpected_generation_response, reason}}
  end

  defp parse_success(body, config, request) when is_map(body) do
    content =
      body
      |> Map.get("content", [])
      |> Enum.find_value(fn
        %{"type" => "text", "text" => text} when is_binary(text) -> text
        _ -> nil
      end)

    case content do
      text when is_binary(text) ->
        {:ok,
         %Result{
           content: text,
           model: body["model"] || config[:model],
           provider: "anthropic",
           metadata:
             Map.take(body, ["id", "role", "stop_reason", "stop_sequence", "usage"])
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
