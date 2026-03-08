defmodule Threadr.Repo.Migrations.GrantAgeAccessToDatabaseOwner do
  use Ecto.Migration

  def up do
    execute("""
    DO $$
    DECLARE
      database_owner name;
    BEGIN
      SELECT pg_catalog.pg_get_userbyid(datdba)
      INTO database_owner
      FROM pg_database
      WHERE datname = current_database();

      IF database_owner IS NULL THEN
        RAISE EXCEPTION 'unable to determine database owner for %', current_database();
      END IF;

      EXECUTE format('GRANT USAGE ON SCHEMA ag_catalog TO %I', database_owner);
      EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA ag_catalog TO %I', database_owner);
      EXECUTE format('GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA ag_catalog TO %I', database_owner);
      EXECUTE format(
        'ALTER ROLE %I IN DATABASE %I SET search_path = ag_catalog, "$user", public',
        database_owner,
        current_database()
      );
      EXECUTE format(
        'ALTER DEFAULT PRIVILEGES IN SCHEMA ag_catalog GRANT SELECT ON TABLES TO %I',
        database_owner
      );
      EXECUTE format(
        'ALTER DEFAULT PRIVILEGES IN SCHEMA ag_catalog GRANT EXECUTE ON FUNCTIONS TO %I',
        database_owner
      );
    END
    $$;
    """)
  end

  def down do
    execute("""
    DO $$
    DECLARE
      database_owner name;
    BEGIN
      SELECT pg_catalog.pg_get_userbyid(datdba)
      INTO database_owner
      FROM pg_database
      WHERE datname = current_database();

      IF database_owner IS NULL THEN
        RAISE EXCEPTION 'unable to determine database owner for %', current_database();
      END IF;

      EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA ag_catalog REVOKE SELECT ON TABLES FROM %I', database_owner);
      EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA ag_catalog REVOKE EXECUTE ON FUNCTIONS FROM %I', database_owner);
      EXECUTE format(
        'ALTER ROLE %I IN DATABASE %I RESET search_path',
        database_owner,
        current_database()
      );
      EXECUTE format('REVOKE SELECT ON ALL TABLES IN SCHEMA ag_catalog FROM %I', database_owner);
      EXECUTE format('REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA ag_catalog FROM %I', database_owner);
      EXECUTE format('REVOKE USAGE ON SCHEMA ag_catalog FROM %I', database_owner);
    END
    $$;
    """)
  end
end
