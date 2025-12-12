defmodule ExNVR.NervesWeb.ModemLive do
  use ExNVRWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="min-h-screen w-full p-8 bg-gray-50 dark:bg-gray-950 text-gray-900 dark:text-gray-100 transition-colors duration-300">
      <div class="max-w-[1400px] mx-auto">
        
        <!-- HEADER -->
        <div class="mb-8">
          <div class="flex items-center gap-3 mb-2">
            <div class="w-10 h-10 rounded-full bg-blue-500/20 dark:bg-blue-500/30 flex items-center justify-center">
              <svg class="w-6 h-6 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.111 16.404a5.5 5.5 0 017.778 0M12 20h.01m-7.08-7.071c3.904-3.905 10.236-3.905 14.141 0M1.394 9.393c5.857-5.857 15.355-5.857 21.213 0"></path>
              </svg>
            </div>
            <div>
              <h1 class="text-2xl font-bold text-gray-900 dark:text-white">Modem Status</h1>
              <p class="text-sm text-gray-500 dark:text-gray-400">Wireless Interface</p>
            </div>
          </div>
        </div>

        <!-- TOP STATUS BAR -->
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
          <!-- Connection Status -->
          <div class="bg-white dark:bg-gray-900 rounded-lg p-6 border border-gray-200 dark:border-gray-800">
            <div class="flex items-center justify-between">
              <div>
                <div class="flex items-center gap-2 mb-1">
                  <div :if={@modem_details.connection == "internet"}  class="w-2 h-2 bg-green-500 rounded-full animate-pulse"></div>
                  <span :if={@modem_details.connection == "internet"} class="text-green-500 font-semibold uppercase text-sm">CONNECTED</span>

                  <span :if={@modem_details.connection == "disconnected"} class="text-white font-semibold uppercase text-sm">Disconnected</span>
                </div>
                <p class="text-gray-600 dark:text-gray-400 text-sm">{@modem_details.provider} • {@modem_details.access_tech}</p>
              </div>
              <div class="text-right">
                <div class="text-3xl font-bold text-gray-900 dark:text-white">{@modem_details.signal_dbm} <span class="text-sm text-gray-500">dBm</span></div>
                <div class="text-xs text-gray-500 dark:text-gray-400 bottom-0">Signal Strength</div>
                <div class="flex gap-1 mt-2 justify-end items-end">
                  <%= for bar <- 1..4 do %>
                    <div
                    class={"w-1.5 rounded-sm #{if bar <= @modem_details.signal_bars, do: "bg-green-500", else: "bg-gray-300 dark:bg-gray-700"}"}
                    style={"height: #{bar * 4 + 4}px"}
                    >
                    </div>
                    <% end %>
                </div> 
              </div>
            </div>
          </div>

          <!-- IP & APN -->
          <div class="bg-white dark:bg-gray-900 rounded-lg p-6 border border-gray-200 dark:border-gray-800">
            <div class="flex justify-between items-center">
              <div>
                <div class="text-xs text-gray-500 dark:text-gray-400 uppercase mb-1">IP Address</div>
                <div class="text-xl font-mono font-semibold text-gray-900 dark:text-gray-100">{@modem_details.ip}/{@modem_details.mask}</div>
              </div>
              <div class="text-right">
                <div class="text-xs text-gray-500 dark:text-gray-400 uppercase mb-1">APN</div>
                <div class="text-xl font-semibold text-gray-900 dark:text-white">{@modem_details.apn}</div>
              </div>
            </div>
          </div>
        </div>

        <!-- MAIN GRID -->
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mb-6">
          
          <!-- Signal Information -->
          <div class="bg-white dark:bg-gray-900 rounded-lg p-6 border border-gray-200 dark:border-gray-800">
            <div class="flex items-center gap-2 mb-4">
              <svg class="w-5 h-5 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"></path>
              </svg>
              <h2 class="font-semibold text-gray-900 dark:text-white">Signal Information</h2>
            </div>
            <div class="space-y-3">
              <div class="flex justify-between items-center">
                <span class="text-sm text-gray-600 dark:text-gray-400">Strength</span>
                <span class="text-sm font-semibold text-gray-900 dark:text-white">{@modem_details.signal_dbm} dBm</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-sm text-gray-600 dark:text-gray-400">Bars</span>
                <span class="text-sm font-semibold text-gray-900 dark:text-white">{@modem_details.signal_bars}/4</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-sm text-gray-600 dark:text-gray-400">ASU</span>
                <span class="text-sm font-semibold text-gray-900 dark:text-white">{@modem_details.signal_asu}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-sm text-gray-600 dark:text-gray-400">Technology</span>
                <span class="text-sm font-semibold text-gray-900 dark:text-white">{@modem_details.access_tech}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-sm text-gray-600 dark:text-gray-400">Band</span>
                <span class="text-sm font-semibold text-gray-900 dark:text-white">{@modem_details.band}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-sm text-gray-600 dark:text-gray-400">Channel</span>
                <span class="text-sm font-semibold text-gray-900 dark:text-white">{@modem_details.channel}</span>
              </div>
            </div>
          </div>

          <!-- Network Configuration -->
          <div class="bg-white dark:bg-gray-900 rounded-lg p-6 border border-gray-200 dark:border-gray-800">
            <div class="flex items-center gap-2 mb-4">
              <svg class="w-5 h-5 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9"></path>
              </svg>
              <h2 class="font-semibold text-gray-900 dark:text-white">Network Configuration</h2>
            </div>
            <div class="space-y-3">
              <div class="flex justify-between items-center">
                <span class="text-sm text-gray-600 dark:text-gray-500">IP Address</span>
                <span class="text-sm font-mono font-semibold text-gray-900 dark:text-white">{@modem_details.ip}/{@modem_details.mask}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-sm text-gray-600 dark:text-gray-400">Subnet</span>
                <span class="text-sm font-mono font-semibold text-gray-900 dark:text-white">{@modem_details.subnet}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-sm text-gray-600 dark:text-gray-400">Router</span>
                <span class="text-sm font-mono font-semibold text-gray-900 dark:text-white">{@modem_details.router}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-sm text-gray-600 dark:text-gray-400">APN</span>
                <span class="text-sm font-semibold text-gray-900 dark:text-white">{@modem_details.apn}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-sm text-gray-600 dark:text-gray-400">Provider</span>
                <span class="text-sm font-semibold text-gray-900 dark:text-white">{@modem_details.provider}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-sm text-gray-600 dark:text-gray-400">Cell ID</span>
                <span class="text-sm font-mono font-semibold text-gray-900 dark:text-white">{@modem_details.cid}</span>
              </div>
            </div>
          </div>

          <!-- Device Information -->
          <div class="bg-white dark:bg-gray-900 rounded-lg p-6 border border-gray-200 dark:border-gray-800">
            <div class="flex items-center gap-2 mb-4">
              <svg class="w-5 h-5 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z"></path>
              </svg>
              <h2 class="font-semibold text-gray-900 dark:text-white">Device Information</h2>
            </div>
            <div class="space-y-3">
              <div class="flex justify-between items-center">
                <span class="text-sm text-gray-600 dark:text-gray-400">Manufacturer</span>
                <span class="text-sm font-semibold text-gray-900 dark:text-white">{@modem_details.manufacturer}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-sm text-gray-600 dark:text-gray-400">Model</span>
                <span class="text-sm font-semibold text-gray-900 dark:text-gray-100">{@modem_details.model}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-sm text-gray-600 dark:text-gray-400">Type</span>
                <span class="text-sm font-semibold text-gray-900 dark:text-white">{@modem_details.type}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-sm text-gray-600 dark:text-gray-400">Present</span>
                <span class="text-sm font-semibold text-green-500">{@modem_details.present}</span>
              </div>
            </div>
          </div>

        </div>

        <!-- BOTTOM GRID -->
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mb-6">
          
          <!-- Device Identifiers -->
          <div class="bg-white dark:bg-gray-900 rounded-lg p-6 border border-gray-200 dark:border-gray-800">
            <div class="flex items-center gap-2 mb-4">
              <svg class="w-5 h-5 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V8a2 2 0 00-2-2h-5m-4 0V5a2 2 0 114 0v1m-4 0a2 2 0 104 0m-5 8a2 2 0 100-4 2 2 0 000 4zm0 0c1.306 0 2.417.835 2.83 2M9 14a3.001 3.001 0 00-2.83 2M15 11h3m-3 4h2"></path>
              </svg>
              <h2 class="font-semibold text-gray-900 dark:text-white">Device Identifiers</h2>
            </div>
            <div class="space-y-3">
              <div class="flex justify-between items-center">
                <span class="text-sm text-gray-600 dark:text-gray-400">IMEI</span>
                <span class="text-sm font-mono font-semibold text-gray-900 dark:text-white">{@modem_details.imei}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-sm text-gray-600 dark:text-gray-400">ICCID</span>
                <span class="text-sm font-mono font-semibold text-gray-900 dark:text-white">{@modem_details.iccid}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-sm text-gray-600 dark:text-gray-400">IMEISV</span>
                <span class="text-sm font-mono font-semibold text-gray-900 dark:text-white">{@modem_details.imeisv}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-sm text-gray-600 dark:text-gray-400">MEID</span>
                <span class="text-sm font-mono font-semibold text-gray-900 dark:text-white">{@modem_details.meid}</span>
              </div>
            </div>
          </div>

          <!-- Connection Status -->
          <div class="bg-white dark:bg-gray-900 rounded-lg p-6 border border-gray-200 dark:border-gray-800">
            <div class="flex items-center gap-2 mb-4">
              <svg class="w-5 h-5 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"></path>
              </svg>
              <h2 class="font-semibold text-gray-900 dark:text-white">Connection Status</h2>
            </div>
            <div class="space-y-3">
              <div class="flex justify-between items-center">
                <span class="text-sm text-gray-600 dark:text-gray-400">Status</span>
                <span class="text-sm font-semibold text-gray-900 dark:text-gray-100">{@modem_details.status}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-sm text-gray-600 dark:text-gray-400">Connection</span>
                <span class="text-sm font-semibold text-gray-900 dark:text-white">{@modem_details.connection}</span>
              </div>
            </div>
          </div>

          <!-- Hardware -->
          <div class="bg-white dark:bg-gray-900 rounded-lg p-6 border border-gray-200 dark:border-gray-800">
            <div class="flex items-center gap-2 mb-4">
              <svg class="w-5 h-5 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z"></path>
              </svg>
              <h2 class="font-semibold text-gray-900 dark:text-white">Hardware</h2>
            </div>
            <div class="space-y-3">
              <div class="flex justify-between items-center">
                <span class="text-sm text-gray-600 dark:text-gray-400">Hardware Path</span>
                <span class="text-sm font-mono font-semibold text-gray-900 dark:text-white">{@modem_details.hw_path}</span>
              </div>
            </div>
          </div>

        </div>

        <!-- ACTION BUTTONS -->
        <div class="flex gap-3 justify-end">

          <button phx-click="refresh" class="px-6 py-3 bg-gray-900 hover:bg-gray-800 dark:bg-gray-100 dark:hover:bg-gray-200 text-white dark:text-gray-900 rounded-lg font-medium transition-colors flex items-center gap-2">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
            </svg>
            Refresh
          </button>

          <button phx-click="reboot" class="px-6 py-3 bg-red-600 hover:bg-red-700 dark:bg-red-700 dark:hover:bg-red-600 text-white rounded-lg font-medium transition-colors flex items-center gap-2">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
            </svg>
            Reboot Modem
          </button>

        </div>

      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, modem_details: get_modem_data())}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, assign(socket, modem_details: get_modem_data())}
  end

  def handle_event("reboot", _params, socket) do
    spawn(fn ->
      :timer.sleep(100)

      try do
        if function_exported?(Nerves.Runtime, :reboot, 0) do
          Nerves.Runtime.reboot()
        else
          :init.stop()
        end
      rescue
        _ -> :init.stop()
      end
    end)

    {:noreply, socket}
  end

  def get_modem_data do
    %{
      status: VintageNet.get(["interface", "wwan0", "state"]),
      present: VintageNet.get(["interface", "wwan0", "present"]),
      connection: VintageNet.get(["interface", "wwan0", "connection"]) |> to_string(),
      ip: dhcp_options_format("ip"),
      subnet: dhcp_options_format("subnet"),
      router: dhcp_options_format("router"),
      mask: VintageNet.get(["interface", "wwan0", "dhcp_options"]).mask,
      imei: VintageNet.get(["interface", "wwan0", "mobile", "imei"]),
      iccid: VintageNet.get(["interface", "wwan0", "mobile", "iccid"]),
      imeisv: VintageNet.get(["interface", "wwan0", "mobile", "imeisv_svn"]),
      meid: VintageNet.get(["interface", "wwan0", "mobile", "meid"]),
      manufacturer: VintageNet.get(["interface", "wwan0", "mobile", "manufacturer"]),
      model: VintageNet.get(["interface", "wwan0", "mobile", "model"]),
      hw_path: VintageNet.get(["interface", "wwan0", "hw_path"]),
      apn: VintageNet.get(["interface", "wwan0", "mobile", "apn"]),
      access_tech:
        VintageNet.get(["interface", "wwan0", "mobile", "access_technology"]) |> to_string(),
      band: VintageNet.get(["interface", "wwan0", "mobile", "band"]),
      channel: VintageNet.get(["interface", "wwan0", "mobile", "channel"]),
      cid: VintageNet.get(["interface", "wwan0", "mobile", "cid"]),
      signal_dbm: VintageNet.get(["interface", "wwan0", "mobile", "signal_dbm"]),
      signal_bars: VintageNet.get(["interface", "wwan0", "mobile", "signal_4bars"]),
      signal_asu: VintageNet.get(["interface", "wwan0", "mobile", "signal_asu"]),
      provider: VintageNet.get(["interface", "wwan0", "mobile", "provider"]),
      type: VintageNet.get(["interface", "wwan0", "type"])
    }
  end

  defp dhcp_options_format(option) do
    value =
      VintageNet.get(["interface", "wwan0", "dhcp_options"])
      |> Map.get(String.to_existing_atom(option))

    if is_list(value) do
      List.first(value)
    else
      value
    end
    |> VintageNet.IP.ip_to_string()
  end
end

