defmodule Threadr.ML.AnthropicProviderTest do
  use ExUnit.Case, async: true

  alias Threadr.ML.Generation.AnthropicProvider
  alias Threadr.ML.Generation.Request

  test "posts a native anthropic messages request" do
    bypass = Bypass.open()

    Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
      assert ["application/json" <> _rest] = Plug.Conn.get_req_header(conn, "content-type")
      assert ["test-api-key"] = Plug.Conn.get_req_header(conn, "x-api-key")
      assert ["2023-06-01"] = Plug.Conn.get_req_header(conn, "anthropic-version")

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      assert payload["model"] == "claude-3-5-sonnet-latest"
      assert payload["system"] == "Answer only from context"
      assert payload["temperature"] == 0.2
      assert payload["max_tokens"] == 256

      assert payload["messages"] == [
               %{
                 "role" => "user",
                 "content" => [
                   %{
                     "type" => "text",
                     "text" => "Context:\nAlice mentioned Bob.\n\nQuestion:\nWho did Alice mention?"
                   }
                 ]
               }
             ]

      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!(%{
          "id" => "msg_test_123",
          "model" => "claude-3-5-sonnet-20241022",
          "role" => "assistant",
          "stop_reason" => "end_turn",
          "usage" => %{"input_tokens" => 33, "output_tokens" => 8},
          "content" => [%{"type" => "text", "text" => "Alice mentioned Bob."}]
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
             AnthropicProvider.complete(
               request,
               endpoint: endpoint_url(bypass),
               api_key: "test-api-key",
               model: "claude-3-5-sonnet-latest",
               temperature: 0.2,
               max_tokens: 256,
               timeout: 5_000
             )

    assert result.content == "Alice mentioned Bob."
    assert result.model == "claude-3-5-sonnet-20241022"
    assert result.provider == "anthropic"
    assert result.metadata["id"] == "msg_test_123"
    assert result.metadata["stop_reason"] == "end_turn"
    assert result.metadata["usage"]["output_tokens"] == 8
  end

  defp endpoint_url(bypass), do: "http://localhost:#{bypass.port}/v1/messages"
end
