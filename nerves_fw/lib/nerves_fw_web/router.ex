defmodule NervesWeb.Router do
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
    plug :accepts, ["json", "jpg", "mp4"]
    plug :fetch_session
    plug :fetch_current_user
  end

  pipeline :api_require_authenticated_user do
    plug :require_authenticated_user, api: true
  end

  pipeline :reverse_proxy do
    plug ExNVRWeb.Plug.ProxyAllow
    plug ExNVRWeb.Plug.ProxyPathRewriter
  end

  scope "/" do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [
        {ExNVRWeb.UserAuth, :ensure_authenticated},
        {ExNVRWeb.Navigation, :attach_hook},
        {NervesWeb.Sidebar, [
          %{
            label: "My New Item",
            href: "/test",
            icon: "hero-cube",
            position: [group: 1, index: 0]
          }
        ]}
      ] do
      live "/test", NervesWeb.TestLive, :index
    end

    forward "/", ExNVRWeb.Router
  end
end
