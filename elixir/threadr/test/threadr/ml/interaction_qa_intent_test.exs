defmodule Threadr.ML.InteractionQAIntentTest do
  use ExUnit.Case, async: true

  alias Threadr.ML.InteractionQAIntent

  test "classifies named actor interaction questions" do
    assert {:ok, %{kind: :interaction_partners, actor_ref: "sig"}} =
             InteractionQAIntent.classify("who does sig talk with the most?")
  end

  test "classifies self-reference interaction questions" do
    assert {:ok, %{kind: :interaction_partners, actor_ref: "I"}} =
             InteractionQAIntent.classify("who do I mostly talk with?")
  end

  test "rejects non interaction questions" do
    assert {:error, :not_interaction_question} = InteractionQAIntent.classify("what happened?")
  end
end
