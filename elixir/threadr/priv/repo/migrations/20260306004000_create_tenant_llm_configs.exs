defmodule Threadr.Repo.Migrations.CreateTenantLlmConfigs do
  use Ecto.Migration

  def change do
    create table(:tenant_llm_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :use_system, :boolean, null: false, default: true
      add :provider_name, :string, null: false, default: "openai"
      add :endpoint, :text
      add :model, :string
      add :api_key, :text
      add :system_prompt, :text
      add :temperature, :float
      add :max_tokens, :integer
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tenant_llm_configs, [:tenant_id])
  end
end
