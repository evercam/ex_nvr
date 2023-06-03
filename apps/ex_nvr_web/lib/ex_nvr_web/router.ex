defmodule ExNVRWeb.Router do
  use ExNVRWeb, :router

  import ExNVRWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {ExNVRWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :fetch_current_user
  end

  pipeline :api_require_authenticated_user do
    plug :require_authenticated_user, api: true
  end

  scope "/api", ExNVRWeb do
    pipe_through :api

    post "/users/login", API.UserSessionController, :login

    scope "/devices/:device_id" do
      pipe_through [:api_require_authenticated_user, ExNVRWeb.Plug.Device]

      get "/recordings", API.RecordingController, :index
      get "/recordings/:recording_id/blob", API.RecordingController, :blob

      get "/hls/index.m3u8", API.DeviceStreamingController, :hls_stream
      get "/hls/:segment_name", API.DeviceStreamingController, :hls_stream_segment
    end
  end

  if Application.compile_env(:ex_nvr_web, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", ExNVRWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{ExNVRWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/login", UserLoginLive, :new
      live "/users/register", UserRegistrationLive, :new
      live "/users/reset-password", UserForgotPasswordLive, :new
      live "/users/reset-password/:token", UserResetPasswordLive, :edit
    end

    post "/users/login", UserSessionController, :create
  end

  scope "/", ExNVRWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/", PageController, :home

    import Phoenix.LiveDashboard.Router
    live_dashboard "/live-dashboard", metrics: ExNVRWeb.Telemetry

    live_session :require_authenticated_user,
      on_mount: [{ExNVRWeb.UserAuth, :ensure_authenticated}] do
      live "/dashboard", DashboardLive, :new

      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm-email/:token", UserSettingsLive, :confirm_email
    end
  end

  scope "/", ExNVRWeb do
    pipe_through [:browser]

    delete "/users/logout", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{ExNVRWeb.UserAuth, :mount_current_user}] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end
end
