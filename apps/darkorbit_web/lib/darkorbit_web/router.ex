defmodule DarkorbitWeb.Router do
  use DarkorbitWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DarkorbitWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug DarkorbitWeb.GameAuth, :fetch_current_player
  end

  pipeline :require_authenticated_player do
    plug DarkorbitWeb.GameAuth, :require_authenticated_player
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api/native", DarkorbitWeb do
    pipe_through :api

    post "/login", NativeClientController, :login
    post "/refresh", NativeClientController, :refresh
    post "/logout", NativeClientController, :logout
  end

  scope "/", DarkorbitWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/helmet", HelmetController, :show
    get "/login", SessionController, :new
    post "/login", SessionController, :create
    get "/register", RegistrationController, :new
    post "/register", RegistrationController, :create
    get "/register/success", RegistrationController, :success
    get "/register/resend", RegistrationController, :resend_new
    post "/register/resend", RegistrationController, :resend
    get "/verify-account", RegistrationController, :verify
    post "/verify-account", RegistrationController, :confirm
    delete "/logout", SessionController, :delete
  end

  # The phone checks a saved HMD bearer credential without joining a pilot
  # channel. JSON API avoids exposing the credential in URL or browser session.
  scope "/", DarkorbitWeb do
    pipe_through :api

    post "/helmet/verify", HelmetController, :verify
    post "/helmet/pair", HelmetController, :pair
  end

  scope "/", DarkorbitWeb do
    pipe_through [:browser, :require_authenticated_player]

    get "/play", GameController, :show
    get "/equipment", EquipmentController, :show
    post "/equipment", EquipmentController, :update
    post "/equipment/activate", EquipmentController, :activate
  end

  # Other scopes may use custom stacks.
  # scope "/api", DarkorbitWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:darkorbit_web, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DarkorbitWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
