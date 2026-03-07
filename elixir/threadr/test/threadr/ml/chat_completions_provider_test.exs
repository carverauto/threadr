defmodule Threadr.ML.ChatCompletionsProviderTest do
  use ExUnit.Case, async: true

  alias Threadr.ML.Generation.ChatCompletionsProvider
  alias Threadr.ML.Generation.Request

  test "posts a provider-agnostic request to an OpenAI-compatible endpoint" do
    bypass = Bypass.open()

    Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
      assert ["application/json" <> _rest] = Plug.Conn.get_req_header(conn, "content-type")
      assert ["Bearer test-api-key"] = Plug.Conn.get_req_header(conn, "authorization")

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      assert payload["model"] == "gpt-4.1-mini"
      assert payload["temperature"] == 0.2
      assert payload["max_tokens"] == 256

      assert payload["messages"] == [
               %{"role" => "system", "content" => "Answer only from context"},
               %{
                 "role" => "user",
                 "content" =>
                   "Context:\nAlice mentioned Bob.\n\nQuestion:\nWho did Alice mention?"
               }
             ]

      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!(%{
          "id" => "chatcmpl-test-123",
          "model" => "gpt-4.1-mini-2026-03-01",
          "system_fingerprint" => "fp-test",
          "usage" => %{"prompt_tokens" => 42, "completion_tokens" => 7, "total_tokens" => 49},
          "choices" => [
            %{
              "index" => 0,
              "finish_reason" => "stop",
              "message" => %{"role" => "assistant", "content" => "Alice mentioned Bob."}
            }
          ]
        })
      )
    end)

    request =
      Request.new(%{
        prompt: "Context:\nAlice mentioned Bob.\n\nQuestion:\nWho did Alice mention?",
        system_prompt: "Answer only from context",
        context: %{"question" => "Who did Alice mention?"},
        mode: :qa
      })

    assert {:ok, result} =
             ChatCompletionsProvider.complete(
               request,
               endpoint: endpoint_url(bypass),
               api_key: "test-api-key",
               model: "gpt-4.1-mini",
               provider_name: "openai-compatible",
               temperature: 0.2,
               max_tokens: 256,
               timeout: 5_000
             )

    assert result.content == "Alice mentioned Bob."
    assert result.model == "gpt-4.1-mini-2026-03-01"
    assert result.provider == "openai-compatible"
    assert result.metadata["id"] == "chatcmpl-test-123"
    assert result.metadata["finish_reason"] == "stop"
    assert result.metadata["usage"]["total_tokens"] == 49
    assert result.metadata["mode"] == :qa
    assert result.metadata["context"]["question"] == "Who did Alice mention?"
  end

  test "returns an error tuple when the endpoint responds with an error" do
    bypass = Bypass.open()

    Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
      Plug.Conn.resp(conn, 429, Jason.encode!(%{"error" => %{"message" => "rate limited"}}))
    end)

    request = Request.new(%{prompt: "Hello"})

    assert {:error, {:generation_request_failed, 429, body}} =
             ChatCompletionsProvider.complete(
               request,
               endpoint: endpoint_url(bypass),
               model: "gpt-test",
               timeout: 5_000
             )

    assert body["error"]["message"] == "rate limited"
  end

  defp endpoint_url(bypass) do
    "http://localhost:#{bypass.port}/v1/chat/completions"
  end
end
