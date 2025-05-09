defmodule NervesWeb.Sidebar do
  use ExNVRWeb, :live_view

  def on_mount(items, _params, _session, socket) do
    {:cont,
      attach_hook(socket, :sidebar_extra_items, :handle_params,
      fn (params, uri, socket) ->
        {:cont, assign(socket, sidebar_extra_items: items)}
      end)}
  end
end
