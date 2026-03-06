defmodule Threadr.ControlPlane.Changes.ReportBotStatus do
  @moduledoc false

  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    target_status = Ash.Changeset.get_argument(changeset, :target_status)

    changeset
    |> ensure_observation_defaults()
    |> AshStateMachine.transition_state(target_status)
  end

  defp ensure_observation_defaults(changeset) do
    changeset
    |> ensure_attribute(:status_metadata, %{})
    |> ensure_attribute(:last_observed_at, DateTime.utc_now())
  end

  defp ensure_attribute(changeset, attribute, default) do
    if Map.has_key?(changeset.attributes, attribute) do
      changeset
    else
      Ash.Changeset.force_change_attribute(changeset, attribute, default)
    end
  end
end
