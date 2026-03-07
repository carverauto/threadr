defmodule Threadr.ControlPlane.Changes.BeginBotDelete do
  @moduledoc false

  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    changeset
    |> ensure_attribute(:status_reason, "delete_requested")
    |> ensure_attribute(:status_metadata, %{})
    |> Ash.Changeset.force_change_attribute(:last_observed_at, nil)
    |> AshStateMachine.transition_state(:deleting)
  end

  defp ensure_attribute(changeset, attribute, default) do
    if Map.has_key?(changeset.attributes, attribute) do
      changeset
    else
      Ash.Changeset.force_change_attribute(changeset, attribute, default)
    end
  end
end
