defmodule ExNVRWeb.Components.Health do
  @moduledoc """
  Stateless components and presentation helpers for the system health dashboard.

  Imported by `ExNVRWeb.HealthDashboardLive` so its template can use them as
  `<.panel>`, `<.sparkline>`, etc. without qualification.
  """

  use ExNVRWeb, :html

  ## Layout primitives

  attr :title, :string, required: true
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def panel(assigns) do
    ~H"""
    <section class={"bg-white dark:bg-gray-800 shadow-sm rounded-lg p-4 border border-gray-200 dark:border-gray-700 #{@class}"}>
      <h2 class="text-lg font-medium mb-3">{@title}</h2>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, default: nil

  def kv(assigns) do
    ~H"""
    <div class="flex justify-between gap-2 text-sm py-0.5">
      <span class="text-gray-500 dark:text-gray-400">{@label}</span>
      <span class="font-mono text-right break-all">{display(@value)}</span>
    </div>
    """
  end

  def empty(assigns) do
    ~H"""
    <div class="text-sm text-gray-500 dark:text-gray-400 italic">No data</div>
    """
  end

  ## CPU

  attr :usage, :list, default: []

  def core_grid(%{usage: []} = assigns) do
    ~H"""
    <div class="text-xs text-gray-400 dark:text-gray-500 italic">
      collecting…
    </div>
    """
  end

  def core_grid(assigns) do
    cores =
      assigns.usage
      |> Enum.with_index()
      |> Enum.map(fn {pct, idx} ->
        clamped = pct |> max(0) |> min(100)

        %{
          index: idx,
          pct: clamped,
          hue: 120.0 - clamped * 1.2,
          label: "Core #{idx}: #{:erlang.float_to_binary(clamped / 1, decimals: 0)}%"
        }
      end)

    assigns = assign(assigns, :cores, cores)

    ~H"""
    <div class="flex flex-wrap gap-1.5">
      <div
        :for={core <- @cores}
        title={core.label}
        class="relative w-3 h-8 rounded-sm overflow-hidden bg-gray-200 dark:bg-gray-700"
      >
        <div
          class="absolute bottom-0 left-0 right-0 transition-[height,background-color] duration-500"
          style={"height: #{core.pct}%; background-color: hsl(#{core.hue}, 70%, 45%);"}
        >
        </div>
      </div>
    </div>
    """
  end

  ## Memory

  attr :memory, :any, default: nil

  def memory_section(%{memory: nil} = assigns) do
    ~H"""
    <.empty />
    """
  end

  def memory_section(assigns) do
    mem = assigns.memory
    total = mem[:total_memory] || mem[:system_total_memory] || 0
    available = mem[:available_memory] || mem[:free_memory] || 0
    used = max(total - available, 0)
    pct = if total > 0, do: used * 100 / total, else: 0

    assigns =
      assigns
      |> assign(:total, total)
      |> assign(:used, used)
      |> assign(:pct, pct)
      |> assign(:buffered, mem[:buffered_memory])
      |> assign(:cached, mem[:cached_memory])

    ~H"""
    <div class="mb-2 flex justify-between text-sm">
      <span>{format_bytes(@used)} used</span>
      <span>{format_bytes(@total)} total</span>
    </div>
    <div class="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2.5">
      <div class={"#{bar_color(@pct, 80, 95)} h-2.5 rounded-full"} style={"width: #{@pct}%"}></div>
    </div>
    <div class="mt-3 grid grid-cols-2 gap-x-3 text-sm">
      <.kv :if={@buffered} label="Buffered" value={format_bytes(@buffered)} />
      <.kv :if={@cached} label="Cached" value={format_bytes(@cached)} />
    </div>
    """
  end

  ## Storage

  attr :blocks, :list, default: []

  def storage_section(%{blocks: []} = assigns) do
    ~H"""
    <.empty />
    """
  end

  def storage_section(assigns) do
    ~H"""
    <.table id="storage" rows={@blocks}>
      <:col :let={b} label="Name">{block_name(b)}</:col>
      <:col :let={b} label="Mount">{block_fs_field(b, :mountpoint) || "—"}</:col>
      <:col :let={b} label="Type">{block_fs_field(b, :type) || "—"}</:col>
      <:col :let={b} label="Size">{format_bytes(block_size_bytes(b))}</:col>
      <:col :let={b} label="Used">{usage_cell(b)}</:col>
    </.table>
    """
  end

  ## Network

  attr :router, :any, default: nil
  attr :netbird, :any, default: nil

  def network_section(%{router: nil, netbird: nil} = assigns) do
    ~H"""
    <.empty />
    """
  end

  def network_section(assigns) do
    ~H"""
    <div :if={@router}>
      <h3 class="font-medium mb-1">Router</h3>
      <.kv
        :for={{k, v} <- router_rows(@router)}
        label={to_string(k)}
        value={inspect_short(v)}
      />
    </div>
    <div :if={@netbird}>
      <h3 class="font-medium mt-3 mb-1">Netbird</h3>
      <.netbird_rows netbird={@netbird} />
    </div>
    """
  end

  attr :netbird, :any, default: nil

  # `netbird status --json` returns a large tree (all events, per-peer public
  # keys, ICE candidates, DNS servers, …). For the health page we surface only
  # a curated connection summary plus a compact per-peer list.
  def netbird_rows(%{netbird: netbird} = assigns) when is_map(netbird) do
    assigns =
      assigns
      |> assign(:summary, netbird_summary(netbird))
      |> assign(:peers, netbird_peers(netbird))

    ~H"""
    <.kv :for={{label, value} <- @summary} label={label} value={value} />

    <div :if={@peers != []} class="mt-3">
      <h4 class="text-xs font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400 mb-1">
        Peers
      </h4>
      <div class="space-y-0.5">
        <div
          :for={peer <- @peers}
          class="flex items-center justify-between gap-2 py-0.5 text-sm"
          title={peer.status}
        >
          <span class="flex items-center gap-1.5 min-w-0">
            <span class={["h-2 w-2 rounded-full shrink-0", netbird_peer_dot(peer.status)]}></span>
            <span class="truncate">{peer.name}</span>
          </span>
          <span class="flex items-center gap-2 shrink-0 font-mono text-xs text-gray-500 dark:text-gray-400">
            <span>{peer.type}</span>
            <span>{peer.latency}</span>
          </span>
        </div>
      </div>
    </div>
    """
  end

  def netbird_rows(assigns) do
    ~H"""
    <.empty />
    """
  end

  defp netbird_summary(netbird) do
    [
      {"Status", netbird["daemonStatus"]},
      {"Version", netbird["daemonVersion"]},
      {"FQDN", netbird["fqdn"]},
      {"NetBird IP", netbird["netbirdIp"]},
      {"Management", netbird_connection(netbird["management"])},
      {"Signal", netbird_connection(netbird["signal"])},
      {"Peers", netbird_ratio(netbird["peers"])},
      {"Relays", netbird_ratio(netbird["relays"])}
    ]
    |> Enum.reject(fn {_label, value} -> value in [nil, ""] end)
  end

  defp netbird_connection(%{"connected" => true}), do: "Connected"
  defp netbird_connection(%{"connected" => false}), do: "Disconnected"
  defp netbird_connection(_), do: nil

  defp netbird_ratio(%{"connected" => n, "total" => total}), do: "#{n}/#{total}"
  defp netbird_ratio(%{"available" => n, "total" => total}), do: "#{n}/#{total}"
  defp netbird_ratio(_), do: nil

  defp netbird_peers(%{"peers" => %{"details" => details}}) when is_list(details) do
    details
    |> Enum.map(fn peer ->
      %{
        name: netbird_peer_name(peer["fqdn"]),
        status: peer["status"],
        type: peer["connectionType"],
        latency: netbird_latency(peer["latency"])
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp netbird_peers(_), do: []

  defp netbird_peer_name(fqdn) when is_binary(fqdn), do: fqdn |> String.split(".") |> hd()
  defp netbird_peer_name(_), do: "—"

  # netbird reports latency in nanoseconds; 0 means "not measured".
  defp netbird_latency(ns) when is_number(ns) and ns > 0,
    do: "#{:erlang.float_to_binary(ns / 1_000_000, decimals: 1)} ms"

  defp netbird_latency(_), do: "—"

  defp netbird_peer_dot("Connected"), do: "bg-green-500"
  defp netbird_peer_dot("Connecting"), do: "bg-yellow-500"
  defp netbird_peer_dot(_), do: "bg-gray-400"

  ## Overall health summary

  attr :results, :list, required: true

  def health_summary(%{results: []} = assigns) do
    ~H""
  end

  def health_summary(assigns) do
    overall = ExNVR.HealthReport.overall(assigns.results)
    assigns = assign(assigns, overall: overall, label: health_overall_label(overall))

    ~H"""
    <section class="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-4">
      <div class="flex items-center justify-between mb-3">
        <h2 class="text-lg font-semibold">System status</h2>
        <span class={[
          "inline-flex items-center gap-1.5 px-2 py-0.5 rounded text-xs font-semibold",
          health_status_classes(@overall)
        ]}>
          <span class={["h-2 w-2 rounded-full", health_dot_class(@overall)]}></span>
          {@label}
        </span>
      </div>
      <ul class="space-y-1.5 text-sm">
        <li :for={check <- @results} class="flex items-start gap-2">
          <span
            class={["mt-1 h-2 w-2 rounded-full shrink-0", health_dot_class(check.status)]}
            title={Atom.to_string(check.status)}
          ></span>
          <div class="flex-1 min-w-0">
            <div class="font-medium">{check.label}</div>
            <div
              :if={check.detail}
              class="text-xs text-gray-500 dark:text-gray-400 truncate"
              title={check.detail}
            >
              {check.detail}
            </div>
          </div>
        </li>
      </ul>
    </section>
    """
  end

  defp health_overall_label(:ok), do: "Healthy"
  defp health_overall_label(:failing), do: "Failing"
  defp health_overall_label(:insufficient_data), do: "Unknown"

  defp health_status_classes(:ok),
    do: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200"

  defp health_status_classes(:failing),
    do: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"

  defp health_status_classes(:insufficient_data),
    do: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200"

  defp health_dot_class(:ok), do: "bg-green-500"
  defp health_dot_class(:failing), do: "bg-red-500"
  defp health_dot_class(:insufficient_data), do: "bg-yellow-500"

  ## Recording-health badge

  attr :state, :atom, required: true

  def recording_badge(assigns) do
    {label, classes} = recording_badge_attrs(assigns.state)
    assigns = assign(assigns, label: label, classes: classes)

    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 px-2 py-0.5 rounded text-xs font-semibold",
      @classes
    ]}>
      <span class={["h-2 w-2 rounded-full", device_state_class(@state)]}></span>
      {@label}
    </span>
    """
  end

  defp recording_badge_attrs(:recording),
    do: {"Recording", "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200"}

  defp recording_badge_attrs(:streaming),
    do: {"Live", "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200"}

  defp recording_badge_attrs(:failed),
    do: {"Failed", "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"}

  defp recording_badge_attrs(:stopped),
    do: {"Stopped", "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200"}

  defp recording_badge_attrs(other),
    do: {to_string(other || "—"), "bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-200"}

  ## Solar charger

  attr :solar, :any, required: true

  def solar_section(assigns) do
    ~H"""
    <.kv label="Vendor" value={Map.get(@solar, :pid) || "—"} />
    <.kv label="Serial" value={Map.get(@solar, :serial_number)} />
    <.kv label="Firmware" value={Map.get(@solar, :fw)} />
    <.kv label="Battery" value={mv_to_v(Map.get(@solar, :v))} />
    <.kv label="Current" value={ma_to_a(Map.get(@solar, :i))} />
    <.kv label="Panel V" value={mv_to_v(Map.get(@solar, :vpv))} />
    <.kv label="Panel W" value={solar_panel_power(@solar)} />
    <.kv :if={Map.get(@solar, :soc)} label="SoC" value={"#{Map.get(@solar, :soc)}%"} />
    """
  end

  ## UPS

  attr :ups, :any, required: true

  def ups_section(assigns) do
    ~H"""
    <.ups_row label="AC power" ok={@ups[:ac_ok]} good="Online" bad="On battery" tone={:warn} />
    <.ups_row label="Battery" ok={!@ups[:low_battery]} good="OK" bad="Low" tone={:danger} />
    """
  end

  attr :label, :string, required: true
  attr :ok, :boolean, required: true
  attr :good, :string, required: true
  attr :bad, :string, required: true
  attr :tone, :atom, default: :danger

  def ups_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-2 text-sm py-0.5">
      <span class="text-gray-500 dark:text-gray-400">{@label}</span>
      <span class={[
        "inline-flex items-center gap-1.5 px-2 py-0.5 rounded text-xs font-semibold",
        ups_badge_class(@ok, @tone)
      ]}>
        <span class={["h-2 w-2 rounded-full", ups_dot_class(@ok, @tone)]}></span>
        {if @ok, do: @good, else: @bad}
      </span>
    </div>
    """
  end

  defp ups_badge_class(true, _),
    do: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200"

  defp ups_badge_class(_, :warn),
    do: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200"

  defp ups_badge_class(_, _), do: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"

  defp ups_dot_class(true, _), do: "bg-green-500"
  defp ups_dot_class(_, :warn), do: "bg-yellow-500"
  defp ups_dot_class(_, _), do: "bg-red-500"

  ## Fan

  attr :fan, :any, required: true

  def fan_section(assigns) do
    ~H"""
    <.kv label="Internal temp" value={format_temp(Map.get(@fan, :internal_temp))} />
    <.kv label="External temp" value={format_temp(Map.get(@fan, :external_temp))} />
    <.kv label="Speed" value={format_rpm(Map.get(@fan, :speed))} />
    """
  end

  ## Cameras

  attr :devices, :list, default: []
  attr :history, :map, default: %{}

  def camera_grid(%{devices: []} = assigns) do
    ~H"""
    <div class="text-sm text-gray-500 dark:text-gray-400 italic">
      No camera devices configured.
    </div>
    """
  end

  def camera_grid(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-3 gap-4">
      <.camera_card
        :for={device <- @devices}
        device={device}
        history={Map.get(@history, device[:id] || device.id, %{})}
      />
    </div>
    """
  end

  attr :device, :map, required: true
  attr :history, :map, default: %{}

  def camera_card(assigns) do
    streams =
      (assigns.device[:stream_stats] || %{})
      |> Enum.map(fn {name, track} -> {name, track_summary(track)} end)
      |> Enum.filter(fn {_, summary} -> summary != nil end)

    state = assigns.device[:state]
    streaming? = state in [:recording, :streaming]
    device_id = assigns.device[:id] || assigns.device.id

    assigns =
      assigns
      |> assign(:streams, streams)
      |> assign(:state, state)
      |> assign(:name, assigns.device[:name])
      |> assign(:type, assigns.device[:type])
      |> assign(:streaming?, streaming?)
      |> assign(:stream_url, "/api/devices/#{device_id}/hls/index.m3u8?stream=high")
      |> assign(:dom_id, "camera-preview-#{device_id}")

    ~H"""
    <section class="bg-white dark:bg-gray-800 shadow-sm rounded-lg p-4 border border-gray-200 dark:border-gray-700">
      <header class="flex items-start justify-between mb-3">
        <div>
          <h3 class="text-lg font-medium truncate">{@name}</h3>
          <div class="text-xs text-gray-500 dark:text-gray-400 uppercase tracking-wide">
            {@type}
          </div>
        </div>
        <.recording_badge state={@state} />
      </header>

      <div class="aspect-video bg-gray-100 dark:bg-gray-900 rounded mb-3 overflow-hidden flex items-center justify-center">
        <video
          :if={@streaming?}
          id={@dom_id}
          phx-hook="CameraPreview"
          phx-update="ignore"
          data-stream-url={@stream_url}
          autoplay
          muted
          playsinline
          class="w-full h-full object-contain"
        />
        <p :if={not @streaming?} class="text-xs text-gray-500 dark:text-gray-400">
          {preview_placeholder(@state)}
        </p>
      </div>

      <%= if @streams == [] do %>
        <div class="text-sm text-gray-400 dark:text-gray-500 italic">
          Pipeline not reporting streams yet.
        </div>
      <% else %>
        <div class="space-y-3">
          <.stream_block
            :for={{name, summary} <- @streams}
            name={name}
            summary={summary}
            history={Map.get(@history, name, %{})}
          />
        </div>
      <% end %>
    </section>
    """
  end

  defp preview_placeholder(:stopped), do: "Device stopped"
  defp preview_placeholder(:failed), do: "Device failed"
  defp preview_placeholder(_), do: "No live stream"

  attr :name, :any, required: true
  attr :summary, :map, required: true
  attr :history, :map, default: %{}

  def stream_block(assigns) do
    ~H"""
    <div class="border-t border-gray-100 dark:border-gray-700 pt-3 first:border-t-0 first:pt-0">
      <div class="flex flex-wrap items-center gap-x-2 gap-y-1 mb-2">
        <span class="inline-flex items-center px-1.5 py-0.5 rounded bg-blue-50 text-blue-700 dark:bg-blue-900/40 dark:text-blue-200 text-xs font-semibold uppercase tracking-wide">
          {stream_label(@name)}
        </span>
        <span :if={@summary.encoding} class="font-mono text-xs uppercase">
          {@summary.encoding}
        </span>
        <span :if={@summary.resolution} class="font-mono text-xs">
          {@summary.resolution}
        </span>
        <span :if={@summary.profile} class="text-xs text-gray-500 dark:text-gray-400">
          {@summary.profile}
        </span>
      </div>

      <div class="grid grid-cols-2 gap-x-3 gap-y-1 text-sm">
        <.kv label="Bitrate" value={format_bitrate(latest(@history[:bitrate]))} />
        <.kv label="FPS" value={format_fps(latest(@history[:fps]))} />
        <.kv label="GOP" value={@summary.gop} />
        <.kv label="Frames" value={format_int(@summary.frames)} />
        <.kv label="Bytes" value={format_bytes(@summary.bytes)} />
      </div>

      <div class="mt-2 space-y-1.5">
        <.sparkline
          :if={(@history[:bitrate] || []) != []}
          samples={@history[:bitrate]}
          label="Bitrate"
          format={:bitrate}
        />
        <.sparkline
          :if={(@history[:fps] || []) != []}
          samples={@history[:fps]}
          label="FPS"
        />
      </div>
    </div>
    """
  end

  ## Sparkline

  attr :samples, :list, default: []
  attr :label, :string, default: nil
  attr :width, :integer, default: 240
  attr :height, :integer, default: 32
  attr :class, :string, default: ""

  attr :format, :atom,
    default: :number,
    values: [:number, :bytes, :percent, :watt, :bitrate, :millivolt]

  def sparkline(%{samples: samples} = assigns) when length(samples) < 2 do
    ~H"""
    <div class={[
      "rounded-md px-2 py-1.5",
      "bg-gray-50 dark:bg-gray-900/40 border border-gray-100 dark:border-gray-700/50",
      @class
    ]}>
      <div class="flex items-baseline justify-between gap-2">
        <span :if={@label} class="text-xs text-gray-500 dark:text-gray-400">{@label}</span>
        <span class="text-xs text-gray-400 dark:text-gray-500 italic ml-auto">
          collecting…
        </span>
      </div>
    </div>
    """
  end

  def sparkline(assigns) do
    {points, last, min_v, max_v} =
      sparkline_points(assigns.samples, assigns.width, assigns.height)

    assigns =
      assigns
      |> assign(:points, points)
      |> assign(:last, last)
      |> assign(:min_v, min_v)
      |> assign(:max_v, max_v)

    ~H"""
    <div class={[
      "rounded-md px-2 py-1.5",
      "bg-gray-50 dark:bg-gray-900/40 border border-gray-100 dark:border-gray-700/50",
      @class
    ]}>
      <div class="flex items-baseline justify-between gap-2 mb-1">
        <span :if={@label} class="text-xs text-gray-500 dark:text-gray-400 truncate">
          {@label}
        </span>
        <div class="flex items-baseline gap-2 ml-auto shrink-0">
          <span class="text-[10px] font-mono text-gray-400 dark:text-gray-500">
            {format_sparkline_value(@min_v, @format)}–{format_sparkline_value(@max_v, @format)}
          </span>
          <span class="text-sm font-mono font-medium text-gray-900 dark:text-gray-100">
            {format_sparkline_value(@last, @format)}
          </span>
        </div>
      </div>
      <svg
        viewBox={"0 0 #{@width} #{@height}"}
        width="100%"
        height={@height}
        class="text-blue-500 dark:text-blue-400 block"
        preserveAspectRatio="none"
      >
        <polyline
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          vector-effect="non-scaling-stroke"
          points={@points}
        />
      </svg>
    </div>
    """
  end

  ## Presentation helpers (public so the LiveView template can call them too)

  def format_bytes(nil), do: "—"
  def format_bytes(n) when is_number(n), do: Sizeable.filesize(n, round: 1)
  def format_bytes(other), do: to_string(other)

  def format_bitrate(nil), do: "—"
  def format_bitrate(0), do: "0 bps"

  def format_bitrate(bps) when is_number(bps) do
    cond do
      bps >= 1_000_000 -> "#{:erlang.float_to_binary(bps / 1_000_000, decimals: 2)} Mbps"
      bps >= 1_000 -> "#{:erlang.float_to_binary(bps / 1_000, decimals: 1)} kbps"
      true -> "#{round(bps)} bps"
    end
  end

  def format_bitrate(other), do: to_string(other)

  def format_fps(nil), do: "—"

  def format_fps(fps) when is_number(fps),
    do: "#{:erlang.float_to_binary(fps / 1, decimals: 1)} fps"

  def format_fps(other), do: to_string(other)

  def format_int(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  def format_int(other), do: to_string(other)

  def format_time(nil), do: "—"

  def format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end

  def format_window({n, :second}), do: "#{n}s"
  def format_window({n, :minute}), do: "#{n} min"
  def format_window({n, :hour}), do: "#{n}h"
  def format_window({n, :day}), do: "#{n}d"
  def format_window(n) when is_integer(n), do: "#{n}s"
  def format_window(other), do: inspect(other)

  ## Stream key vocabulary
  #
  #   :main_stream/:sub_stream — map keys on the pipeline `Track` struct
  #   :high/:low               — telemetry tag values from VideoStreamStatReporter
  #   "main"/"sub"             — UI labels
  #
  # Keep all three translations here so a rename touches one file.

  @doc "Translate the Track map key to the telemetry tag value Mobius is indexed by."
  def stream_tag(:main_stream), do: :high
  def stream_tag(:sub_stream), do: :low
  def stream_tag(other), do: other

  @doc "Human-readable stream label shown in the UI."
  def stream_label(:main_stream), do: "main"
  def stream_label(:sub_stream), do: "sub"

  def stream_label(other) when is_atom(other),
    do: other |> to_string() |> String.replace("_", " ")

  def stream_label(other), do: to_string(other)

  ## Internal helpers

  defp sparkline_points(samples, width, height) do
    nums =
      samples
      |> Enum.map(&to_number/1)
      |> Enum.reject(&is_nil/1)

    case nums do
      [] ->
        {"", 0, 0, 0}

      [_ | _] = list ->
        min_v = Enum.min(list)
        max_v = Enum.max(list)
        range = max(max_v - min_v, 1.0e-9)
        count = length(list)
        step = if count > 1, do: width / (count - 1), else: 0

        points =
          list
          |> Enum.with_index()
          |> Enum.map_join(" ", fn {v, i} ->
            x = i * step
            y = height - (v - min_v) / range * (height - 2) - 1

            "#{:erlang.float_to_binary(x / 1, decimals: 2)},#{:erlang.float_to_binary(y / 1, decimals: 2)}"
          end)

        {points, List.last(list), min_v, max_v}
    end
  end

  defp to_number(n) when is_number(n), do: n / 1
  defp to_number(_), do: nil

  defp format_sparkline_value(v, :bytes) when is_number(v), do: format_bytes(round(v))

  defp format_sparkline_value(v, :percent) when is_number(v),
    do: "#{:erlang.float_to_binary(v / 1, decimals: 0)}%"

  defp format_sparkline_value(v, :watt) when is_number(v),
    do: "#{:erlang.float_to_binary(v / 1, decimals: 1)} W"

  defp format_sparkline_value(v, :bitrate) when is_number(v), do: format_bitrate(v)

  defp format_sparkline_value(mv, :millivolt) when is_number(mv),
    do: "#{:erlang.float_to_binary(mv / 1000, decimals: 2)} V"

  defp format_sparkline_value(v, :number) when is_number(v) do
    cond do
      abs(v) >= 1000 -> :erlang.float_to_binary(v / 1, decimals: 0)
      abs(v) >= 10 -> :erlang.float_to_binary(v / 1, decimals: 1)
      true -> :erlang.float_to_binary(v / 1, decimals: 2)
    end
  end

  defp format_sparkline_value(_, _), do: "—"

  defp display(nil), do: "—"
  defp display(true), do: "yes"
  defp display(false), do: "no"
  defp display(v) when is_binary(v), do: v
  defp display(v) when is_number(v), do: v
  defp display(v) when is_atom(v), do: to_string(v)
  defp display(v) when is_list(v), do: Enum.join(v, ", ")
  defp display(v), do: inspect(v)

  defp bar_color(pct, warn, danger) do
    cond do
      pct >= danger -> "bg-red-500"
      pct >= warn -> "bg-yellow-500"
      true -> "bg-green-500"
    end
  end

  defp block_name(%{name: name}), do: name
  defp block_name(b) when is_map(b), do: Map.get(b, "name", "—")
  defp block_name(_), do: "—"

  defp block_field(b, key) when is_map(b), do: Map.get(b, key) || Map.get(b, to_string(key))
  defp block_field(_, _), do: nil

  defp block_size_bytes(b) do
    case block_field(b, :size) do
      n when is_integer(n) -> n
      _ -> 0
    end
  end

  defp usage_cell(b) do
    size = block_size_bytes(b)

    case {block_used_bytes(b, size), size} do
      {u, s} when is_integer(u) and is_integer(s) and s > 0 ->
        pct = u * 100 / s
        "#{format_bytes(u)} (#{:erlang.float_to_binary(pct, decimals: 1)}%)"

      _ ->
        "—"
    end
  end

  defp block_used_bytes(b, size) do
    case block_effective_fs(b) do
      %{avail: avail} when is_integer(avail) -> max(size - avail, 0)
      _ -> nil
    end
  end

  defp block_fs_field(b, key) do
    case block_effective_fs(b) do
      %{} = fs -> Map.get(fs, key)
      _ -> nil
    end
  end

  defp block_effective_fs(b) when is_map(b) do
    case {Map.get(b, :fs), Map.get(b, :parts)} do
      {%{} = fs, _} -> fs
      {_, [%{fs: %{} = fs}]} -> fs
      _ -> nil
    end
  end

  defp block_effective_fs(_), do: nil

  defp device_state_class(:recording), do: "bg-green-500"
  defp device_state_class(:streaming), do: "bg-green-500"
  defp device_state_class(:failed), do: "bg-red-500"
  defp device_state_class(:stopped), do: "bg-yellow-500"
  defp device_state_class(_), do: "bg-gray-400"

  defp mv_to_v(nil), do: "—"
  defp mv_to_v(mv) when is_number(mv), do: "#{:erlang.float_to_binary(mv / 1000, decimals: 2)} V"
  defp mv_to_v(_), do: "—"

  defp ma_to_a(nil), do: "—"
  defp ma_to_a(ma) when is_number(ma), do: "#{:erlang.float_to_binary(ma / 1000, decimals: 2)} A"
  defp ma_to_a(_), do: "—"

  defp format_temp(t) when is_number(t), do: "#{:erlang.float_to_binary(t / 1, decimals: 1)} °C"
  defp format_temp(_), do: "—"

  defp format_rpm(rpm) when is_number(rpm), do: "#{format_int(round(rpm))} RPM"
  defp format_rpm(_), do: "—"

  defp solar_panel_power(solar) do
    case Map.get(solar, :ppv) do
      ppv when is_number(ppv) -> "#{ppv} W"
      _ -> "—"
    end
  end

  defp router_rows(router), do: stable_rows(router, 8)

  @doc """
  Sort the keys so the renderer is deterministic — atom map iteration order
  is unspecified, and we don't want panel content shuffling on every update.
  """
  def stable_rows(map, limit) when is_map(map) do
    map
    |> Enum.sort_by(fn {k, _v} -> to_string(k) end)
    |> Enum.take(limit)
  end

  def stable_rows(_, _), do: []

  def inspect_short(v) when is_binary(v) or is_number(v) or is_atom(v), do: display(v)
  def inspect_short(v) when is_map(v) and map_size(v) <= 4, do: inspect(v)
  def inspect_short(v), do: inspect(v, limit: 5, printable_limit: 80)

  defp track_summary(track) when is_map(track) do
    stats = Map.get(track, :stats) || %{}

    %{
      encoding: Map.get(track, :encoding),
      resolution: track_resolution(stats),
      profile: Map.get(stats, :profile),
      gop: Map.get(stats, :gop_size),
      frames: Map.get(stats, :total_frames),
      bytes: Map.get(stats, :recv_bytes)
    }
  end

  defp track_summary(_), do: nil

  defp track_resolution(%{width: w, height: h}) when is_integer(w) and is_integer(h),
    do: "#{w}×#{h}"

  defp track_resolution(_), do: nil

  defp latest([]), do: nil
  defp latest(nil), do: nil
  defp latest(list) when is_list(list), do: List.last(list)
  defp latest(_), do: nil
end
