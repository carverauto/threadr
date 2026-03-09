defmodule Threadr.ML.ConversationSummaryQAIntentTest do
  use ExUnit.Case, async: true

  alias Threadr.ML.ConversationSummaryQAIntent

  test "classifies time-bounded conversation summary questions" do
    assert {:ok, %{kind: :time_bounded_summary}} =
             ConversationSummaryQAIntent.classify("What happened last week?")
  end

  test "leaves non-summary questions alone" do
    assert {:error, :not_conversation_summary_question} =
             ConversationSummaryQAIntent.classify("Who did Alice mention?")
  end
end
