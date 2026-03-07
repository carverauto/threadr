defmodule Threadr.Repo.Migrations.MakeUserNameNullable do
  use Ecto.Migration

  def change do
    alter table(:users) do
      modify :name, :text, null: true
    end
  end
end
