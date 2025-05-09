defmodule NervesWeb.ExampleLive do
  use ExNVRWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    settings =
      ExNVR.Nerves.SystemSettings.get_settings()
      |> Map.from_struct()

    {:ok, assign(socket, settings: settings)}
  end

  def render(assigns) do
    ~H"""
    <div class="grow text-white e-mx-32 e-py-10">
      <h2>Example</h2>
      <h3 class="mb-4">System Settings</h3>
       <table class="min-w-full table-auto border border-zinc-700 text-sm">
        <thead class="bg-zinc-800 text-left">
          <tr>
            <th class="px-4 py-2 border-b border-zinc-600">Setting</th>
            <th class="px-4 py-2 border-b border-zinc-600">Value</th>
          </tr>
        </thead>
        <tbody>
          <%= for {key, value} <- @settings do %>
            <tr class="odd:bg-zinc-900 even:bg-zinc-800">
              <td class="px-4 py-2 border-b border-zinc-700 font-semibold">
                <%= to_string(key) |> String.replace("_", " ") |> String.capitalize() %>
              </td>
              <td class="px-4 py-2 border-b border-zinc-700">
                <%= inspect(format(key, value)) %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  def format(key, value) do
    case key do
      :router_username -> value
      :router_password -> "••••••••"
      _ -> value
    end
  end
end
