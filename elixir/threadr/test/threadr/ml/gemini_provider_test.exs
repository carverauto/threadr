defmodule Threadr.ML.GeminiProviderTest do
  use ExUnit.Case, async: true

  alias Threadr.ML.Generation.GeminiProvider
  alias Threadr.ML.Generation.Request

  test "posts a native gemini generateContent request" do
    bypass = Bypass.open()

    Bypass.expect_once(bypass, "POST", "/v1beta/models/gemini-2.5-pro:generateContent", fn conn ->
      assert conn.query_string == "key=test-api-key"
      assert ["application/json" <> _rest] = Plug.Conn.get_req_header(conn, "content-type")

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      assert payload["system_instruction"] == %{
               "parts" => [%{"text" => "Answer only from context"}]
             }

      assert payload["generationConfig"] == %{
               "temperature" => 0.1,
               "maxOutputTokens" => 192
             }

      assert payload["contents"] == [
               %{
                 "role" => "user",
                 "parts" => [%{"text" => "Context:\nAlice mentioned Bob.\n\nQuestion:\nWho did Alice mention?"}]
               }
             ]

      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!(%{
          "candidates" => [
            %{
              "finishReason" => "STOP",
              "content" => %{
                "parts" => [%{"text" => "Alice mentioned Bob."}]
              }
            }
          ],
          "usageMetadata" => %{"promptTokenCount" => 24, "candidatesTokenCount" => 6},
          "modelVersion" => "gemini-2.5-pro"
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
             GeminiProvider.complete(
               request,
               endpoint: "http://localhost:#{bypass.port}/v1beta/models/{model}:generateContent",
               api_key: "test-api-key",
               model: "gemini-2.5-pro",
               temperature: 0.1,
               max_tokens: 192,
               timeout: 5_000
             )

    assert result.content == "Alice mentioned Bob."
    assert result.model == "gemini-2.5-pro"
    assert result.provider == "gemini"
    assert result.metadata["finish_reason"] == "STOP"
    assert result.metadata["usageMetadata"]["candidatesTokenCount"] == 6
  end
end
