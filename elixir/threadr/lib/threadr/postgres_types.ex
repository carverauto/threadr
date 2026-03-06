Postgrex.Types.define(
  Threadr.PostgresTypes,
  [AshPostgres.Extensions.Vector] ++ Ecto.Adapters.Postgres.extensions(),
  []
)
