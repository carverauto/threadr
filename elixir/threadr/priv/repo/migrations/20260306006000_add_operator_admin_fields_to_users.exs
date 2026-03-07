defmodule Threadr.Repo.Migrations.AddOperatorAdminFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :is_operator_admin, :boolean, null: false, default: false
      add :must_rotate_password, :boolean, null: false, default: false
    end
  end
end
