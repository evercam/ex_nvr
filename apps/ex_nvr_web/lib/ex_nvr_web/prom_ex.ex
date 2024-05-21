defmodule ExNVRWeb.PromEx do
  @moduledoc false

  use PromEx, otp_app: :ex_nvr_web

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      Plugins.Application,
      Plugins.Beam,
      ExNVRWeb.PromEx.Device,
      ExNVRWeb.PromEx.Recording,
      ExNVRWeb.PromEx.DeviceStream
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "t4C1gkoPQfzLdYMc",
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"}
    ]
  end
end
