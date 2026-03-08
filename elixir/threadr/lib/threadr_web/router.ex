defmodule ThreadrWeb.Router do
  use ThreadrWeb, :router
  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {ThreadrWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:load_from_session)
  end

  pipeline :api do
    plug(:accepts, ["json"])
    plug(:load_from_bearer)

    plug(AshAuthentication.Strategy.ApiKey.Plug,
      resource: Threadr.ControlPlane.User,
      required?: false
    )

    plug(:set_actor, :user)
    plug(ThreadrWeb.Plugs.TrackApiKeyUsage)
  end

  pipeline :control_plane_machine_api do
    plug(:accepts, ["json"])
    plug(ThreadrWeb.Plugs.RequireControlPlaneToken)
  end

  pipeline :internal_metrics do
    plug(:accepts, ["txt", "text", "json"])
  end

  scope "/", ThreadrWeb do
    pipe_through(:browser)

    get("/", PageController, :home)
    auth_routes(AuthController, Threadr.ControlPlane.User, path: "/auth")
    sign_out_route(AuthController)

    sign_in_route(
      register_path: "/register",
      auth_routes_prefix: "/auth",
      on_mount: [{ThreadrWeb.LiveUserAuth, :live_no_user}]
    )

    ash_authentication_live_session :password_settings_routes,
      on_mount: [{ThreadrWeb.LiveUserAuth, :live_user_required}] do
      live("/settings/password", PasswordSettingsLive.Index, :index)
    end

    ash_authentication_live_session :authenticated_routes,
      on_mount: [
        {ThreadrWeb.LiveUserAuth, :live_user_required},
        {ThreadrWeb.LiveUserAuth, :password_rotation_required}
      ] do
      live("/bots", TenantBotLive.Index, :index)
      live("/control-plane/admin/llm", SystemLlmSettingsLive.Index, :index)
      live("/control-plane/tenants", TenantLive.Index, :index)
      live("/control-plane/tenants/:subject_name/bots", TenantBotLive.Index, :index)
      live("/control-plane/tenants/:subject_name/history", TenantHistoryLive.Index, :index)
      live("/control-plane/tenants/:subject_name/qa", TenantQaLive.Index, :index)
      live("/control-plane/tenants/:subject_name/graph", TenantGraphLive.Index, :index)

      live(
        "/control-plane/tenants/:subject_name/dossiers/:node_kind/:node_id",
        TenantDossierLive.Show,
        :show
      )

      live("/control-plane/tenants/:subject_name/llm", TenantLlmSettingsLive.Index, :index)
      live("/settings/api-keys", ApiKeyLive.Index, :index)
    end
  end

  scope "/health", ThreadrWeb do
    pipe_through(:api)

    get("/live", HealthController, :live)
    get("/ready", HealthController, :ready)
  end

  scope "/", ThreadrWeb do
    pipe_through(:internal_metrics)

    get("/metrics", MetricsController, :show)
  end

  scope "/api/control-plane", ThreadrWeb do
    pipe_through(:api)

    get("/tenants", TenantController, :index)
    post("/tenants/:subject_name/migrate", TenantController, :migrate)
  end

  scope "/api/control-plane", ThreadrWeb do
    pipe_through(:control_plane_machine_api)

    get("/bot-contracts", BotControllerContractController, :index)
    get("/tenants/:subject_name/bots/:id/contract", BotControllerContractController, :show)
    post("/tenants/:subject_name/bots/:id/status", BotStatusController, :update)
  end

  scope "/api/v1", ThreadrWeb.Api.V1 do
    pipe_through(:api)

    get("/me", MeController, :show)
    get("/bot-platforms", BotPlatformController, :index)
    get("/tenants", TenantController, :index)
    post("/tenants", TenantController, :create)
    post("/tenants/:subject_name/migrate", TenantController, :migrate)
    get("/tenants/:subject_name/history", HistoryController, :index)
    post("/tenants/:subject_name/history/compare", HistoryController, :compare)
    get("/tenants/:subject_name/bots", BotController, :index)
    post("/tenants/:subject_name/bots", BotController, :create)
    patch("/tenants/:subject_name/bots/:id", BotController, :update)
    delete("/tenants/:subject_name/bots/:id", BotController, :delete)
    get("/tenants/:subject_name/dossiers/:node_kind/:node_id", DossierController, :show)

    post(
      "/tenants/:subject_name/dossiers/:node_kind/:node_id/compare",
      DossierController,
      :compare
    )

    post("/tenants/:subject_name/qa/search", QaController, :search)
    post("/tenants/:subject_name/qa/answer", QaController, :answer)
    post("/tenants/:subject_name/qa/compare", QaController, :compare)
    post("/tenants/:subject_name/qa/graph-answer", QaController, :graph_answer)
    post("/tenants/:subject_name/qa/summarize", QaController, :summarize)
    get("/tenants/:subject_name/memberships", MembershipController, :index)
    post("/tenants/:subject_name/memberships", MembershipController, :create)
    patch("/tenants/:subject_name/memberships/:id", MembershipController, :update)
    delete("/tenants/:subject_name/memberships/:id", MembershipController, :delete)
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:threadr, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: ThreadrWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end
end
