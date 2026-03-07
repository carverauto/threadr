defmodule Threadr.ControlPlane.Token do
  @moduledoc """
  AshAuthentication token storage for session and sign-in tokens.
  """

  use Ash.Resource,
    domain: Threadr.ControlPlane,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication.TokenResource]

  postgres do
    table "tokens"
    repo Threadr.Repo
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    bypass context_equals(:system, true) do
      authorize_if always()
    end
  end
end
