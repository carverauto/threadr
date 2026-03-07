defmodule Threadr.ML.ExtractionTest do
  use ExUnit.Case, async: true

  alias Threadr.ML.Extraction

  test "extracts structured entities and facts through the provider boundary" do
    request =
      Threadr.ML.Extraction.Request.new(%{
        tenant_subject_name: "acme",
        message_id: "msg-1",
        body: "Alice told Bob that payroll access was limited on March 5."
      })

    assert {:ok, result} =
             Extraction.extract(
               request,
               provider: Threadr.TestExtractionProvider,
               model: "test-llm"
             )

    assert result.provider == "test"
    assert result.model == "test-llm"
    assert [%{entity_type: "person", name: "Alice"} | _] = result.entities

    assert [
             %{
               fact_type: "access_statement",
               subject: "Bob",
               predicate: "reported",
               object: "payroll access was limited"
             }
           ] = result.facts
  end

  test "returns a provider error when extraction is disabled" do
    request =
      Threadr.ML.Extraction.Request.new(%{
        tenant_subject_name: "acme",
        message_id: "msg-1",
        body: "Alice mentioned Bob."
      })

    assert {:error, :extraction_provider_not_configured} =
             Extraction.extract(request, provider: Threadr.ML.Extraction.NoopProvider)
  end
end
