defmodule Threadr.ML.BotIntentTest do
  use ExUnit.Case, async: true

  alias Threadr.ML.BotIntent

  test "classifies greetings as chat" do
    assert BotIntent.classify("hello") == :chat
    assert BotIntent.classify("how are you?") == :chat
  end

  test "classifies general knowledge definitions as chat" do
    assert BotIntent.classify("what is the ISIS salute?") == :chat
    assert BotIntent.classify("define AES") == :chat
  end

  test "defaults arbitrary pasted or open-ended prompts to chat" do
    assert BotIntent.classify("here is a weird post, tell me what you think") == :chat
    assert BotIntent.classify("i'm pasting this here, help me make sense of it") == :chat
  end

  test "classifies analyst questions as qa" do
    assert BotIntent.classify("who does sig talk with the most?") == :qa
    assert BotIntent.classify("what happened last week?") == :qa
    assert BotIntent.classify("what did sig and eefer-- talk about today?") == :qa
    assert BotIntent.classify("who has mentioned 1488?") == :qa
    assert BotIntent.classify("what were people talking about today in this channel?") == :qa
  end
end
