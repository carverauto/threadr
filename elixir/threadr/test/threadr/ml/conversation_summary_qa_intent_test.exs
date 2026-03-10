defmodule Threadr.ML.ConversationSummaryQAIntentTest do
  use ExUnit.Case, async: true

  alias Threadr.ML.ConversationSummaryQAIntent

  test "classifies time-bounded conversation summary questions" do
    assert {:ok, %{kind: :time_bounded_summary, time_scope: :last_week}} =
             ConversationSummaryQAIntent.classify("What happened last week?")
  end

  test "classifies recap requests for the current channel" do
    assert {:ok, %{kind: :time_bounded_summary, time_scope: :today, scope_current_channel: true}} =
             ConversationSummaryQAIntent.classify(
               "can you recap the channel discussions for today please"
             )
  end

  test "classifies topic summaries for a named channel today" do
    assert {:ok, %{kind: :time_bounded_summary, time_scope: :today, scope_current_channel: true}} =
             ConversationSummaryQAIntent.classify(
               "summarize the topics from todays chats in #!chases"
             )
  end

  test "classifies recap requests phrased around conversations" do
    assert {:ok, %{kind: :time_bounded_summary, time_scope: :today, scope_current_channel: true}} =
             ConversationSummaryQAIntent.classify("recap todays conversations from #!chases")
  end

  test "leaves non-summary questions alone" do
    assert {:error, :not_conversation_summary_question} =
             ConversationSummaryQAIntent.classify("Who did Alice mention?")
  end

  test "does not classify actor-specific happened questions as summaries" do
    assert {:error, :not_conversation_summary_question} =
             ConversationSummaryQAIntent.classify("What happened to leku?")
  end
end
