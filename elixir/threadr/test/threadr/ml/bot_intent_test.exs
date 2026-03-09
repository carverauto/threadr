defmodule Threadr.ML.BotIntentTest do
  use ExUnit.Case, async: true

  alias Threadr.ML.BotIntent

  test "classifies greetings as chat" do
    assert BotIntent.classify("hello") == :chat
    assert BotIntent.classify("how are you?") == :chat
  end

  test "classifies analyst questions as qa" do
    assert BotIntent.classify("who does sig talk with the most?") == :qa
    assert BotIntent.classify("what happened last week?") == :qa
  end
end
