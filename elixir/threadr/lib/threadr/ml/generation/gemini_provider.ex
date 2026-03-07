defmodule Threadr.ML.Generation.GeminiProvider do
  @moduledoc """
  Native Google Gemini generateContent adapter.
  """

  @behaviour Threadr.ML.Generation.Provider

  alias Threadr.ML.Generation.{Request, Result}

  @impl true
  def complete(%Request{} = request, opts) do
    config = config(opts)
    endpoint = render_endpoint(config)

    response =
      Req.post!(
        endpoint,
        headers: [{"content-type", "application/json"}],
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

  defp render_endpoint(config) do
    base =
      config[:endpoint]
      |> String.replace("{model}", config[:model] || "")

    separator = if String.contains?(base, "?"), do: "&", else: "?"
    api_key = URI.encode_www_form(config[:api_key] || "")
    base <> "#{separator}key=#{api_key}"
  end

  defp request_body(config, request) do
    %{
      system_instruction:
        maybe_system_instruction(request.system_prompt || config[:system_prompt]),
      contents: [
        %{
          role: "user",
          parts: [%{text: request.prompt}]
        }
      ],
      generationConfig:
        %{}
        |> maybe_put(:temperature, config[:temperature])
        |> maybe_put(:maxOutputTokens, config[:max_tokens])
    }
    |> maybe_drop_nil(:system_instruction)
  end

  defp maybe_system_instruction(nil), do: nil
  defp maybe_system_instruction(""), do: nil
  defp maybe_system_instruction(prompt), do: %{parts: [%{text: prompt}]}

  defp parse_success({:error, reason}, _config, _request) do
    {:error, {:unexpected_generation_response, reason}}
  end

  defp parse_success(body, config, request) when is_map(body) do
    content =
      get_in(body, ["candidates", Access.at(0), "content", "parts"])
      |> case do
        parts when is_list(parts) ->
          Enum.find_value(parts, fn
            %{"text" => text} when is_binary(text) -> text
            _ -> nil
          end)

        _ ->
          nil
      end

    case content do
      text when is_binary(text) ->
        {:ok,
         %Result{
           content: text,
           model: config[:model],
           provider: "gemini",
           metadata:
             Map.take(body, ["usageMetadata", "modelVersion"])
             |> Map.put(
               "finish_reason",
               get_in(body, ["candidates", Access.at(0), "finishReason"])
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

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_drop_nil(map, key) do
    if is_nil(Map.get(map, key)), do: Map.delete(map, key), else: map
  end

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
