defmodule Threadr.ControlPlane.Changes.NormalizeEmail do
  @moduledoc """
  Normalizes email addresses to lowercase for stable identity matching.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :email) do
      email when is_binary(email) ->
        Ash.Changeset.change_attribute(changeset, :email, String.downcase(String.trim(email)))

      _ ->
        changeset
    end
  end
end
