defmodule Threadr.ML.QAIntentTest do
  use ExUnit.Case, async: true

  alias Threadr.ML.QAIntent

  test "classifies actor talk questions with filler text" do
    assert {:ok, %{kind: :talks_about, actor_ref: "twatbot", target_ref: nil}} =
             QAIntent.classify("what kind of stupid shit does twatbot mostly talk about?")
  end

  test "classifies actor profile questions" do
    assert {:ok, %{kind: :knows_about, actor_ref: "me", target_ref: nil}} =
             QAIntent.classify("what do you know about me?")
  end

  test "classifies targeted actor questions" do
    assert {:ok, %{kind: :says_about, actor_ref: "sig", target_ref: "leku"}} =
             QAIntent.classify("what has sig been saying about leku?")
  end

  test "leaves paired-actor phrasing to generic qa" do
    assert {:error, :not_actor_question} =
             QAIntent.classify("what do hyralak and sig mostly talk about?")
  end
end
