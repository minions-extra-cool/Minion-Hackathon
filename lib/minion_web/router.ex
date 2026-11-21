defmodule MinionWeb.Router do
  use MinionWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MinionWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MinionWeb do
    pipe_through :browser

    live "/", DashboardLive
    live "/unmatched", UnmatchedLive
    live "/alerts/:id", AlertLive
    live "/rules", RulesLive
    live "/rules/new", RuleEditorLive, :new
    live "/rules/:id", RuleEditorLive, :edit
    live "/gateway", FakeGatewayLive
  end

  scope "/ingest", MinionWeb do
    post "/:source", IngestController, :create
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:minion, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MinionWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  scope "/fake-gateway", MinionWeb do
    pipe_through :api

    post "/messages", FakeGatewayController, :create
    put "/status", FakeGatewayController, :update_status
  end
end
