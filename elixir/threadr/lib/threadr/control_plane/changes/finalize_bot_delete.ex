defmodule Threadr.ControlPlane.Changes.FinalizeBotDelete do
  @moduledoc false

  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    changeset
    |> ensure_attribute(:status_reason, "deployment_deleted")
    |> ensure_attribute(:status_metadata, %{})
    |> ensure_attribute(:last_observed_at, DateTime.utc_now())
    |> AshStateMachine.transition_state(:deleted)
  end

  defp ensure_attribute(changeset, attribute, default) do
    if Map.has_key?(changeset.attributes, attribute) do
      changeset
    else
      Ash.Changeset.force_change_attribute(changeset, attribute, default)
    end
  end
end
