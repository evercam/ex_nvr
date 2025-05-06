defmodule ExNVRWeb.Navigation do
  use ExNVRWeb, :live_view

  def on_mount(:attach_hook, _params, _session, socket) do
    {:cont, attach_hook(socket, :current_path, :handle_params, &set_current_path/3)}
  end


  defp set_current_path(params, uri, socket) do
    {:cont, assign(socket, current_path: URI.parse(uri).path)}
  end
end
