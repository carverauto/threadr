defmodule Threadr.ReleaseTasks do
  @moduledoc """
  Release-safe operational entrypoints for install-time bootstrap work.
  """

  alias Ecto.Migrator
  alias Threadr.ControlPlane.Service

  @otp_app :threadr

  def migrate do
    load_app()
    start_supporting_apps()

    for repo <- repos() do
      start_repo(repo)
      Migrator.run(repo, migrations_path(repo), :up, all: true)
    end

    IO.puts("migrations complete")
    :ok
  end

  def bootstrap_operator_admin_from_env do
    bootstrap_operator_admin(
      email: required_env!("THREADR_BOOTSTRAP_ADMIN_EMAIL"),
      name: System.get_env("THREADR_BOOTSTRAP_ADMIN_NAME"),
      password: required_env!("THREADR_BOOTSTRAP_ADMIN_PASSWORD")
    )
  end

  def bootstrap_operator_admin(opts) when is_list(opts) do
    load_app()
    start_supporting_apps()
    start_repos()

    email =
      opts
      |> Keyword.fetch!(:email)
      |> to_string()
      |> String.trim()

    name =
      opts
      |> Keyword.get(:name)
      |> normalize_blank()

    password =
      opts
      |> Keyword.fetch!(:password)
      |> to_string()
      |> String.trim()

    case Service.bootstrap_operator_admin(%{email: email, name: name, password: password}) do
      {:ok, user, _password} ->
        IO.puts("bootstrap operator admin created: #{user.email}")
        :ok

      {:error, :operator_admin_already_bootstrapped} ->
        IO.puts("bootstrap operator admin skipped: operator admin already exists")
        :ok

      {:error, reason} ->
        raise "bootstrap operator admin failed: #{inspect(reason)}"
    end
  end

  defp load_app do
    Application.load(@otp_app)
  end

  defp repos do
    Application.fetch_env!(@otp_app, :ecto_repos)
  end

  defp start_supporting_apps do
    for app <- [
          :crypto,
          :ssl,
          :postgrex,
          :ecto_sql,
          :ash,
          :ash_postgres,
          :ash_authentication,
          :bcrypt_elixir
        ] do
      case Application.ensure_all_started(app) do
        {:ok, _started} -> :ok
        {:error, {:already_started, _app}} -> :ok
        {:error, reason} -> raise "failed to start dependency #{inspect(app)}: #{inspect(reason)}"
      end
    end
  end

  defp start_repos do
    Enum.each(repos(), &start_repo/1)
  end

  defp start_repo(repo) do
    case repo.start_link(pool_size: 2) do
      {:ok, _pid} ->
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, reason} ->
        raise "failed to start repo #{inspect(repo)}: #{inspect(reason)}"
    end
  end

  defp migrations_path(repo) do
    case repo do
      Threadr.Repo -> Application.app_dir(@otp_app, "priv/repo/migrations")
      _other -> raise "unsupported repo for release migrations: #{inspect(repo)}"
    end
  end

  defp required_env!(name) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" ->
        value

      _ ->
        raise "missing required environment variable #{name}"
    end
  end

  defp normalize_blank(nil), do: nil

  defp normalize_blank(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
