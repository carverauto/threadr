defmodule Threadr.Repo.Migrations.AddBotStatusObservationFields do
  use Ecto.Migration

  def change do
    alter table(:bots) do
      add :status_reason, :string
      add :status_metadata, :map, null: false, default: %{}
      add :last_observed_at, :utc_datetime_usec
    end
  end
end
