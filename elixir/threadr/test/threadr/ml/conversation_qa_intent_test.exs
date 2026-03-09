defmodule Threadr.ML.ConversationQAIntentTest do
  use ExUnit.Case, async: true

  alias Threadr.ML.ConversationQAIntent

  test "classifies paired actor talk questions" do
    assert {:ok, %{kind: :talked_with, actor_ref: "Alice", target_ref: "Bob"}} =
             ConversationQAIntent.classify("What did Alice and Bob talk about last week?")
  end

  test "classifies actor talk with target phrasing" do
    assert {:ok, %{kind: :talked_with, actor_ref: "alice", target_ref: "bob last week"}} =
             ConversationQAIntent.classify("what did alice talk about with bob last week?")
  end

  test "leaves actor-only questions alone" do
    assert {:error, :not_conversation_question} =
             ConversationQAIntent.classify("what does twatbot talk about?")
  end
end
