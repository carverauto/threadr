defmodule Threadr.ControlPlane.Changes.NormalizeAndValidateBotConfig do
  @moduledoc false

  use Ash.Resource.Change

  alias Ash.Error.Changes.InvalidAttribute
  alias Threadr.ControlPlane.BotConfig

  @impl true
  def change(changeset, _opts, _context) do
    platform = Ash.Changeset.get_attribute(changeset, :platform)
    channels = Ash.Changeset.get_attribute(changeset, :channels)
    settings = Ash.Changeset.get_attribute(changeset, :settings)

    with {:ok, %{platform: platform, channels: channels, settings: settings}} <-
           BotConfig.normalize_and_validate(platform, channels, settings) do
      changeset
      |> Ash.Changeset.force_change_attribute(:platform, platform)
      |> Ash.Changeset.force_change_attribute(:channels, channels)
      |> Ash.Changeset.force_change_attribute(:settings, settings)
    else
      {:error, {field, message}} ->
        Ash.Changeset.add_error(
          changeset,
          InvalidAttribute.exception(field: field, message: message)
        )
    end
  end
end
