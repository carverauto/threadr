defmodule Threadr.Repo.Migrations.EnableThreadrExtensions do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS age")
    execute("CREATE EXTENSION IF NOT EXISTS vector")
    execute("CREATE EXTENSION IF NOT EXISTS timescaledb")

    execute("""
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_search') THEN
        CREATE EXTENSION IF NOT EXISTS pg_search;
      ELSE
        RAISE NOTICE 'pg_search extension is not available in this PostgreSQL image';
      END IF;
    END
    $$;
    """)
  end

  def down do
    execute("DROP EXTENSION IF EXISTS pg_search")
    execute("DROP EXTENSION IF EXISTS timescaledb")
    execute("DROP EXTENSION IF EXISTS vector")
    execute("DROP EXTENSION IF EXISTS age")
  end
end
