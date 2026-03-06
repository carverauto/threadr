defmodule Threadr.Repo.Migrations.CreateSystemLlmConfigs do
  use Ecto.Migration

  def change do
    create table(:system_llm_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :scope, :string, null: false, default: "default"
      add :provider_name, :string, null: false, default: "openai"
      add :endpoint, :text
      add :model, :string
      add :api_key, :text
      add :system_prompt, :text
      add :temperature, :float
      add :max_tokens, :integer

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:system_llm_configs, [:scope])
  end
end
