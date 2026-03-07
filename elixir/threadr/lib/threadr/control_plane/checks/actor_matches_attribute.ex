defmodule Threadr.ControlPlane.Checks.ActorMatchesAttribute do
  @moduledoc """
  Authorizes when the configured subject attribute matches the actor id.
  """

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(opts) do
    "actor id matches #{inspect(Keyword.fetch!(opts, :field))}"
  end

  @impl true
  def match?(%{id: actor_id}, %{subject: %Ash.Changeset{} = changeset}, opts)
      when is_binary(actor_id) do
    field = Keyword.fetch!(opts, :field)

    value =
      changeset.attributes[field] ||
        Map.get(changeset.arguments, field) ||
        Map.get(changeset.data, field)

    actor_id == value
  end

  def match?(%{id: actor_id}, %{subject: subject}, opts)
      when is_binary(actor_id) and is_map(subject) do
    actor_id == Map.get(subject, Keyword.fetch!(opts, :field))
  end

  def match?(_, _, _), do: false
end
