defmodule ThunderlineWeb.Router do
  use ThunderlineWeb, :router

  import Oban.Web.Router
  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :graphql do
    plug :load_from_bearer
    plug :set_actor, :user
    plug AshGraphql.Plug
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ThunderlineWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  scope "/", ThunderlineWeb do
    pipe_through :browser

    # Skip authentication for now - direct access to dashboard and wizard
    live_session :public_routes do
      live "/dashboard", DashboardLive
      live "/agents/new", AgentCreationWizardLive
    end

    post "/rpc/run", AshTypescriptRpcController, :run
    post "/rpc/validate", AshTypescriptRpcController, :validate
    get "/ash-typescript", PageController, :index
  end

  scope "/api/json" do
    pipe_through [:api]

    forward "/swaggerui", OpenApiSpex.Plug.SwaggerUI,
      path: "/api/json/open_api",
      default_model_expand_depth: 4

    forward "/", ThunderlineWeb.AshJsonApiRouter
  end

  scope "/gql" do
    pipe_through [:graphql]

    forward "/playground", Absinthe.Plug.GraphiQL,
      schema: Module.concat(["ThunderlineWeb.GraphqlSchema"]),
      socket: Module.concat(["ThunderlineWeb.GraphqlSocket"]),
      interface: :simple

    forward "/", Absinthe.Plug, schema: Module.concat(["ThunderlineWeb.GraphqlSchema"])
  end

  scope "/", ThunderlineWeb do
    pipe_through :browser

    # Redirect home to dashboard (skip auth for now)
    get "/", PageController, :redirect_to_dashboard
    auth_routes AuthController, Thunderline.Accounts.User, path: "/auth"
    sign_out_route AuthController

    # Remove these if you'd like to use your own authentication views
    sign_in_route register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{ThunderlineWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    ThunderlineWeb.AuthOverrides,
                    Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                  ]

    # Remove this if you do not want to use the reset password feature
    reset_route auth_routes_prefix: "/auth",
                overrides: [
                  ThunderlineWeb.AuthOverrides,
                  Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                ]

    # Remove this if you do not use the confirmation strategy
    confirm_route Thunderline.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [
        ThunderlineWeb.AuthOverrides,
        Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
      ]

    # Remove this if you do not use the magic link strategy.
    magic_sign_in_route(Thunderline.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [
        ThunderlineWeb.AuthOverrides,
        Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
      ]
    )
  end

  # File uploads API
  scope "/api", ThunderlineWeb do
    pipe_through :api

    post "/uploads", UploadController, :create
    get "/uploads/preview/:filename", UploadController, :preview
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:thunderline, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ThunderlineWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    scope "/" do
      pipe_through :browser

      oban_dashboard("/oban")
    end
  end

  if Application.compile_env(:thunderline, :dev_routes) do
    import AshAdmin.Router

    scope "/admin" do
      pipe_through :browser

      ash_admin "/"
    end
  end
end
