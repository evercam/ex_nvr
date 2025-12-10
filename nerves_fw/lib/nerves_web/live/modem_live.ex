defmodule ExNVR.NervesWeb.ModemLive do
  use ExNVRWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="p-8 w-full max-w-[1500px] mx-auto transition-colors duration-300
      bg-white text-gray-900 dark:bg-gray-900 dark:text-gray-100">

      <!-- TOP GRID -->
      <div class="grid grid-cols-1 md:grid-cols-4 gap-8">

        <!-- SIM CARD -->
        <div>
          <h2 class="font-semibold text-lg mb-4">Modem</h2>
          <div class="text-sm space-y-2">
            <div class="flex justify-between">
              <span>Modem Model</span><span class="font-semibold">{@modem_details.model}</span>
            </div>

            <div class="flex justify-between">
              <span>Modem Present</span><span class="font-semibold">{@modem_details.present}</span>
            </div>

            <div class="flex justify-between">
              <span>State</span><span class="font-semibold">{@modem_details.status}</span>
            </div>
            <div class="flex justify-between">
              <span>Provider</span><span class="font-semibold">{@modem_details.provider}</span>
            </div>
            <div class="flex justify-between">
              <span>IMEI</span><span class="font-semibold">{@modem_details.imei}</span>
            </div>
            <div class="flex justify-between">
              <span>iccid</span><span class="font-semibold">{@modem_details.iccid}</span>
            </div>
            <div class="flex justify-between">
              <span>Manufacturer</span><span class="font-semibold">{@modem_details.manufacturer}</span>
            </div>
            <div class="flex justify-between gap-4">
              <span>hw_path</span><span class="font-semibold">{@modem_details.hw_path}</span>
            </div>



          </div>
        </div>

        <!-- CONNECTION -->
        <div>
          <h2 class="font-semibold text-lg mb-4">Connection</h2>
          <div class="text-sm space-y-2">

            <div class="flex justify-between">
              <span>Data connection state</span>
              <span class="bg-green-600 text-white rounded-md px-3 py-0.5 text-xs">{@modem_details.connection}</span>
            </div>
      <div class="flex justify-between">
              <span>Apn</span>
              <span class="font-semibold">{@modem_details.apn}</span>
            </div>


            <div class="flex justify-between">
              <span>Network Band</span>
              <span class="font-semibold">{@modem_details.band}</span>
            </div>

            <div class="flex justify-between">
              <span>Network</span><span class="font-semibold">{@modem_details.access_tech}</span>
            </div>

            <div class="flex justify-between">
              <span>Router</span><span class="font-semibold">{@modem_details.router}</span>
            </div>

            <div class="flex justify-between">
              <span>IP address</span><span class="font-semibold">{@modem_details.ip}</span>
            </div>
          </div>
        </div>

        <!-- Network Config -->
        <div>
          <h2 class="font-semibold text-lg mb-4">Network Config</h2>
          <div class="text-sm space-y-2">
            <div class="flex justify-between">
              <span>Provider</span><span class="font-semibold">{@modem_details.provider}</span>
            </div>
            <div class="flex justify-between">
              <span>Channel</span><span class="font-semibold">{@modem_details.channel}</span>
            </div>
            <div class="flex justify-between">
              <span>Cid</span><span class="font-semibold">{@modem_details.cid}</span>
            </div>
            <div class="flex justify-between">
              <span>Interface Type</span><span class="font-semibold">{@modem_details.type}</span>
            </div>
          </div>
        </div>

        <!-- sign Info -->
        <div>
          <h2 class="font-semibold text-lg mb-4">Signal Info</h2>
          <div class="text-sm space-y-2">
            <div class="flex justify-between">
              <span>Signal dbm</span><span class="font-semibold">{@modem_details.signal_dbm}</span>
            </div>
            <div class="flex justify-between">
              <span>Signal bars</span><span class="font-semibold">{@modem_details.signal_bars}</span>
            </div>
            <div class="flex justify-between">
              <span>Signal asu</span><span class="font-semibold">{@modem_details.signal_asu}</span>
            </div>
          </div>
        </div>
      </div>

      <div class="border-t my-10 border-gray-300 dark:border-gray-700"></div>

      <!-- BANDS -->
      <div class="mt-6 flex justify-end">
        <button class="bg-blue-600 text-white px-5 py-2 rounded hover:bg-blue-700
          dark:bg-blue-700 dark:hover:bg-blue-600 transition-colors">
          Restart connection
        </button>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, modem_details: get_modem_data())}
  end

  # Smaller signal bars
  def signal_bar_class(bars, bar) do
    height = bar * 5

    if bar <= bars do
      "w-1 h-#{height} bg-green-500 rounded-md"
    else
      "w-1 h-#{height} bg-gray-300 rounded-md"
    end
  end

  def get_modem_data do
    %{
      status: VintageNet.get(["interface", "wwan0", "state"]),
      present: VintageNet.get(["interface", "wwan0", "present"]),
      connection: VintageNet.get(["interface", "wwan0", "connection"]) |> to_string(),
      ip: dhcp_options_format("ip"),
      subnet: dhcp_options_format("subnet"),
      router: dhcp_options_format("router"),
      #   dns: dhcp_options_format("dns"),
      # mask: dhcp_options_format("mask"),
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
      |> IO.inspect(label: "this is working")

    if is_list(value) do
      List.first(value)
    else
      value
    end
    |> VintageNet.IP.ip_to_string()
  end

  def provider do
    VintageNet.get(["interface", "wwan0", "mobile", "provider"])
  end
end
