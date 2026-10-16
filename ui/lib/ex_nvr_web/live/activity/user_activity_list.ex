defmodule ExNVRWeb.ActivityLive.UserActivityList do
  @moduledoc """
  The user activity tab: actions made by users, API clients and the remote server.

  The parent LiveView forwards new entries with `send_update/2` and a `:new_entries` count.
  """

  use ExNVRWeb, :live_component

  alias ExNVR.Activity
  alias ExNVR.Activity.Entry

  @quick_filters [
    {"all", "All", nil},
    {"alerts", "Alerts", {"severity", "!=", "info"}},
    {"logins", "Logins", {"category", "==", "auth"}},
    {"devices", "Devices", {"category", "==", "device"}},
    {"config", "Config changes", {"category", "==", "config"}},
    {"exports", "Exports", {"category", "==", "export"}}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <div id="user-activity" class="grow">
      <div class="flex flex-wrap items-center justify-between gap-2 mb-2">
        <div id="activity-quick-filters" class="flex flex-wrap gap-2">
          <.link
            :for={{id, label, filter} <- quick_filters()}
            id={"quick-filter-#{id}"}
            patch={~p"/activity?#{quick_filter_params(filter)}"}
            class={[
              "px-3 py-1 text-sm rounded-full border",
              if(@active_quick_filter == id,
                do: "bg-blue-600 border-blue-600 text-white",
                else:
                  "border-gray-400 text-gray-700 hover:bg-gray-200 dark:text-gray-300 dark:hover:bg-gray-700"
              )
            ]}
          >
            {label}
          </.link>
        </div>

        <button
          :if={@new_count > 0}
          id="activity-new-entries"
          phx-click="refresh"
          phx-target={@myself}
          class="px-3 py-1 text-sm rounded-full bg-blue-600 text-white hover:bg-blue-700"
        >
          {@new_count} new {if @new_count == 1, do: "entry", else: "entries"} — refresh
        </button>
      </div>

      <.filter_form :if={@meta} meta={@meta} devices={@devices} target={@myself} />

      <Flop.Phoenix.table
        :if={@meta}
        id="activity-entries"
        opts={ExNVRWeb.FlopConfig.table_opts()}
        items={@entries}
        meta={@meta}
        path={~p"/activity?tab=user"}
      >
        <:col :let={entry} label="Time" field={:time}>
          <span class="whitespace-nowrap">{format_time(entry.time)}</span>
        </:col>
        <:col :let={entry} label="Severity" field={:severity}>
          <.severity_badge severity={entry.severity} />
        </:col>
        <:col :let={entry} label="Category" field={:category}>
          <span class="inline-flex items-center gap-1 whitespace-nowrap">
            <.icon name={category_icon(entry.category)} class="w-4 h-4" />
            {humanize(entry.category)}
          </span>
        </:col>
        <:col :let={entry} label="Activity">
          <div class="text-left">
            <p>{entry.message}</p>
            <p class="font-mono text-xs text-gray-500 dark:text-gray-400">{entry.action}</p>
          </div>
        </:col>
        <:col :let={entry} label="Actor">
          <div class="text-left">
            <p class="whitespace-nowrap">{entry.actor_label}</p>
            <p class="text-xs text-gray-500 dark:text-gray-400">
              {humanize(entry.actor_type)}{if entry.source_ip, do: " · #{entry.source_ip}"}
            </p>
          </div>
        </:col>
        <:col :let={entry} label="Device">
          <.device_cell entry={entry} devices={@devices_by_id} />
        </:col>
        <:col :let={entry} label="Details">
          <.entry_details entry={entry} />
        </:col>
      </Flop.Phoenix.table>

      <.pagination :if={@meta} meta={@meta} target={@myself} />
    </div>
    """
  end

  attr :meta, Flop.Meta, required: true
  attr :devices, :list, required: true
  attr :target, :any, required: true

  defp filter_form(assigns) do
    assigns = assign(assigns, :form, to_form(assigns.meta))

    ~H"""
    <.form
      for={@form}
      id="activity-filter-form"
      phx-change="filter"
      phx-target={@target}
      class="flex flex-wrap gap-4"
    >
      <Flop.Phoenix.filter_fields
        :let={f}
        form={@form}
        fields={[
          category: [
            type: "select",
            options: Enum.map(Entry.categories(), &{humanize(&1), &1}),
            prompt: "All categories"
          ],
          severity: [
            type: "select",
            options: Enum.map(Entry.severities(), &{humanize(&1), &1}),
            prompt: "All severities"
          ],
          device_id: [
            type: "select",
            options: Enum.map(@devices, &{&1.name, &1.id}),
            prompt: "All devices"
          ],
          message: [op: :like, label: "Search", placeholder: "Search activity"],
          time: [op: :>=, label: "From"],
          time: [op: :<=, label: "To"]
        ]}
      >
        <div>
          <.input
            class="border rounded p-1"
            field={f.field}
            label={f.label}
            type={f.type}
            phx-debounce="500"
            {f.rest}
          />
        </div>
      </Flop.Phoenix.filter_fields>
    </.form>
    """
  end

  attr :severity, :atom, required: true

  defp severity_badge(assigns) do
    ~H"""
    <span class={[
      "px-2 py-0.5 text-xs font-medium rounded",
      case @severity do
        :critical -> "bg-red-600 text-white"
        :warning -> "bg-yellow-400 text-black"
        _info -> "bg-gray-400 text-black dark:bg-gray-600 dark:text-white"
      end
    ]}>
      {humanize(@severity)}
    </span>
    """
  end

  attr :entry, Entry, required: true
  attr :devices, :map, required: true

  defp device_cell(%{entry: %{device_id: nil}} = assigns) do
    ~H"""
    <span class="text-gray-400">—</span>
    """
  end

  defp device_cell(assigns) do
    ~H"""
    <.link
      :if={Map.has_key?(@devices, @entry.device_id)}
      navigate={~p"/devices/#{@entry.device_id}/details"}
      class="underline whitespace-nowrap"
    >
      {@devices[@entry.device_id].name}
    </.link>
    <span
      :if={not Map.has_key?(@devices, @entry.device_id)}
      class="whitespace-nowrap"
      title="Device deleted"
    >
      {@entry.device_name} <span class="text-xs text-gray-500">(deleted)</span>
    </span>
    """
  end

  attr :entry, Entry, required: true

  defp entry_details(assigns) do
    {changes, metadata} = Map.pop(assigns.entry.metadata || %{}, "changes", %{})
    assigns = assign(assigns, changes: changes, metadata: metadata)

    ~H"""
    <span :if={@changes == %{} and @metadata == %{}} class="text-gray-400">—</span>
    <details :if={@changes != %{} or @metadata != %{}} class="text-left">
      <summary class="cursor-pointer text-blue-700 dark:text-blue-400">Show</summary>
      <table :if={@changes != %{}} class="mt-2 text-xs">
        <tr :for={{field, value} <- Enum.sort(@changes)}>
          <td class="pr-2 font-semibold align-top">{field}</td>
          <td class="align-top">{format_value(value)}</td>
        </tr>
      </table>
      <div :if={@metadata != %{}} class="mt-2">
        <.metadata_display metadata={@metadata} />
      </div>
    </details>
    """
  end

  @impl true
  def mount(socket) do
    {:ok, assign(socket, params: nil, meta: nil, entries: [], new_count: 0)}
  end

  @impl true
  def update(%{new_entries: count}, socket) do
    if live_reload?(socket.assigns.meta) do
      {:ok, load_entries(socket)}
    else
      {:ok, update(socket, :new_count, &(&1 + count))}
    end
  end

  def update(assigns, socket) do
    params_changed? = socket.assigns.params != assigns.params

    socket =
      socket
      |> assign(assigns)
      |> assign(:devices_by_id, Map.new(assigns.devices, &{&1.id, &1}))

    if params_changed?,
      do: {:ok, socket |> assign(new_count: 0) |> load_entries()},
      else: {:ok, socket}
  end

  @impl true
  def handle_event("filter", params, socket) do
    params =
      params
      |> Map.take(["filters", "order_by", "order_directions", "page_size"])
      |> Map.put("tab", "user")

    {:noreply, push_patch(socket, to: ~p"/activity?#{params}")}
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    params = Map.merge(socket.assigns.params, %{"page" => page, "tab" => "user"})
    {:noreply, push_patch(socket, to: ~p"/activity?#{params}")}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, socket |> assign(new_count: 0) |> load_entries()}
  end

  defp load_entries(socket) do
    case Activity.list(Map.delete(socket.assigns.params, "tab")) do
      {:ok, {entries, meta}} ->
        assign(socket,
          entries: entries,
          meta: meta,
          active_quick_filter: active_quick_filter(meta)
        )

      {:error, meta} ->
        assign(socket, entries: [], meta: meta, active_quick_filter: nil)
    end
  end

  # New entries are shown right away only when they would land on the current page.
  defp live_reload?(nil), do: false

  defp live_reload?(meta) do
    meta.current_page in [nil, 1] and active_filters(meta) == [] and
      meta.flop.order_by in [nil, [:time, :id]] and
      meta.flop.order_directions in [nil, [:desc, :desc]]
  end

  defp active_filters(meta), do: Enum.reject(meta.flop.filters, &(&1.value in [nil, ""]))

  defp active_quick_filter(meta) do
    current =
      meta
      |> active_filters()
      |> Enum.map(&{to_string(&1.field), to_string(&1.op), to_string(&1.value)})

    Enum.find_value(@quick_filters, fn
      {id, _label, nil} -> if current == [], do: id
      {id, _label, filter} -> if current == [filter], do: id
    end)
  end

  defp quick_filters, do: @quick_filters

  defp quick_filter_params(nil), do: %{"tab" => "user"}

  defp quick_filter_params({field, op, value}) do
    %{"tab" => "user", "filters" => %{"0" => %{"field" => field, "op" => op, "value" => value}}}
  end

  defp format_time(time), do: Calendar.strftime(time, "%b %d, %Y %H:%M:%S %Z")

  defp format_value(nil), do: "—"
  defp format_value("[REDACTED]"), do: "changed"
  defp format_value(value) when is_binary(value), do: value
  defp format_value(value), do: Jason.encode!(value)

  defp humanize(nil), do: ""

  defp humanize(value),
    do: value |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp category_icon(:auth), do: "hero-key"
  defp category_icon(:user), do: "hero-user"
  defp category_icon(:device), do: "hero-video-camera"
  defp category_icon(:export), do: "hero-arrow-down-tray"
  defp category_icon(:config), do: "hero-cog-6-tooth"
  defp category_icon(:remote), do: "hero-cloud"
  defp category_icon(_other), do: "hero-information-circle"
end
