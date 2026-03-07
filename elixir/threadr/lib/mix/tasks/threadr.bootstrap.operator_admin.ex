defmodule Mix.Tasks.Threadr.Bootstrap.OperatorAdmin do
  @shortdoc "Creates the first operator-admin account and emits bootstrap credentials"

  use Mix.Task

  alias Threadr.ControlPlane.Service

  @switches [
    email: :string,
    name: :string,
    password: :string,
    secret_name: :string,
    namespace: :string
  ]

  @impl true
  def run(args) do
    {opts, _argv, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    email =
      case opts[:email] do
        value when is_binary(value) and value != "" -> value
        _ -> Mix.raise("missing required option --email")
      end

    Mix.Task.run("app.start")

    case Service.bootstrap_operator_admin(%{
           email: email,
           name: opts[:name],
           password: opts[:password]
         }) do
      {:ok, user, password} ->
        Mix.shell().info("Bootstrap operator admin created")
        Mix.shell().info("email: #{user.email}")
        Mix.shell().info("must_rotate_password: #{user.must_rotate_password}")
        Mix.shell().info("password: #{password}")

        if secret_name = opts[:secret_name] do
          Mix.shell().info("")
          Mix.shell().info(secret_yaml(secret_name, opts[:namespace], user.email, password))
        end

      {:error, :operator_admin_already_bootstrapped} ->
        Mix.shell().info("Operator admin bootstrap skipped: an operator admin already exists")

      {:error, reason} ->
        Mix.raise("operator admin bootstrap failed: #{inspect(reason)}")
    end
  end

  defp secret_yaml(secret_name, namespace, email, password) do
    namespace_line =
      if is_binary(namespace) and namespace != "" do
        "  namespace: #{namespace}\n"
      else
        ""
      end

    """
    apiVersion: v1
    kind: Secret
    metadata:
      name: #{secret_name}
    #{namespace_line}type: Opaque
    stringData:
      email: #{email}
      password: #{password}
    """
  end
end
