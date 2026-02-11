defmodule ExNVRWeb.Navigation do
  @moduledoc false

  use ExNVRWeb, :live_view

  def on_mount(:set_current_path, _params, _session, socket) do
    {:cont, attach_hook(socket, :current_path, :handle_params, &set_current_path/3)}
  end

  defp set_current_path(_params, uri, socket) do
    {:cont, assign(socket, current_path: URI.parse(uri).path)}
  end
end
