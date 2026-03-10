defmodule Threadr.Repo.TenantMigrations.AddMessageTrigramIndexes do
  use Ecto.Migration

  def up do
    execute("""
    CREATE INDEX IF NOT EXISTS messages_body_trgm_idx
    ON #{prefix()}.messages
    USING gin (lower(body) gin_trgm_ops)
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS #{prefix()}.messages_body_trgm_idx")
  end
end
