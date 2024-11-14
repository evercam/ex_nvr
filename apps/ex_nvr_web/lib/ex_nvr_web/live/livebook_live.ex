defmodule ExNVRWeb.LivebookLive do
  use ExNVRWeb, :live_view

  def render(assigns) do
    ~H"""
    <iframe
      width="100%"
      height="100%"
      src={@src}
    />
    """
  end

  def mount(_, _, socket) do
    port = if String.to_existing_atom(System.get_env("EXNVR_ENABLE_HTTPS", "false")),
      do: "EXNVR_LB_HTTPS_PORT",
      else: "EXNVR_LB_HTTP_PORT"
      |> System.get_env("9100")
      |> String.to_integer()

    url =
      System.get_env("EXNVR_URL", "http://localhost:4000")
      |> URI.parse()
      |> Map.put(:port, port)
      |> URI.to_string()

    socket
    |> assign(src: url)
    |> then(&{:ok, &1})
  end
end
