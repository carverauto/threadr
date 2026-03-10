defmodule Threadr.Repo do
  use AshPostgres.Repo, otp_app: :threadr, warn_on_missing_ash_functions?: false

  import Ecto.Query

  def installed_extensions do
    ["age", "vector", "timescaledb", "pg_search", "pg_trgm", "citext"]
  end

  def min_pg_version do
    Version.parse!("16.0.0")
  end

  def tenant_migrations_path do
    Application.app_dir(:threadr, "priv/repo/tenant_migrations")
  end

  def all_tenants do
    all(from(tenant in "tenants", select: tenant.schema_name))
  end
end
