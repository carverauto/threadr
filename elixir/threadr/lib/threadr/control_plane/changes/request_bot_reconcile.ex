defmodule Threadr.ControlPlane.Changes.RequestBotReconcile do
  @moduledoc false

  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.force_change_attribute(:status_reason, "reconcile_requested")
    |> Ash.Changeset.force_change_attribute(:status_metadata, %{})
    |> Ash.Changeset.force_change_attribute(:last_observed_at, nil)
    |> AshStateMachine.transition_state(:reconciling)
  end
end
