defmodule ExNVRWeb.DeviceTabs.SettingsTab do
  use ExNVRWeb, :live_component

  import ExNVR.Authorization

  alias ExNVR.{Devices, RemoteStorages}
  alias ExNVR.Model.Device

  @moduledoc false

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Section: General --%>
      <.simple_form
        id={"general_form_#{@device.id}"}
        for={@device_form}
        phx-submit="save_general"
        phx-target={@myself}
      >
        <.settings_section title="General">
          <.settings_row label="Name" description="Human-readable name for this device">
            <.input field={@device_form[:name]} type="text" placeholder="Device Name" />
          </.settings_row>
          <.settings_row label="Timezone" description="Timezone used for recordings and events">
            <.input field={@device_form[:timezone]} type="select" options={Tzdata.zone_list()} />
          </.settings_row>
          <:footer>
            <.section_status saved={@save_section == "general"} />
            <.button type="submit" phx-disable-with="Saving...">Save</.button>
          </:footer>
        </.settings_section>
      </.simple_form>

      <%!-- Section: Connection (IP cameras only) --%>
      <.simple_form
        :if={@device.type == :ip}
        id={"connection_form_#{@device.id}"}
        for={@device_form}
        phx-submit="save_connection"
        phx-target={@myself}
      >
        <.settings_section title="Connection">
          <.settings_row label="Device URL" description="HTTP base URL for ONVIF and snapshot access">
            <.input
              field={@device_form[:url]}
              type="text"
              placeholder="http://192.168.1.100"
            />
          </.settings_row>
          <.settings_row label="Vendor" description="Camera vendor for vendor-specific integrations">
            <.input
              field={@device_form[:vendor]}
              type="select"
              options={Device.vendors()}
              prompt="Select vendor"
            />
          </.settings_row>
          <.inputs_for :let={creds} field={@device_form[:credentials]}>
            <.settings_row label="Username" description="Camera authentication username">
              <.input field={creds[:username]} type="text" autocomplete="off" />
            </.settings_row>
            <.settings_row label="Password" description="Camera authentication password">
              <.password_field field={creds[:password]} />
            </.settings_row>
          </.inputs_for>
          <:footer>
            <.section_status saved={@save_section == "connection"} />
            <.button type="submit" phx-disable-with="Saving...">Save</.button>
          </:footer>
        </.settings_section>
      </.simple_form>

      <%!-- Section: Stream Configuration (IP cameras only) --%>
      <.simple_form
        :if={@device.type == :ip}
        id={"stream_config_form_#{@device.id}"}
        for={@device_form}
        phx-submit="save_stream_config"
        phx-target={@myself}
      >
        <.settings_section title="Stream Configuration">
          <.inputs_for :let={config} field={@device_form[:stream_config]}>
            <.input field={config[:profile_token]} type="hidden" />
            <.input field={config[:sub_profile_token]} type="hidden" />

            <div class="px-5 pb-1 pt-3">
              <p class="text-xs font-semibold text-gray-400 dark:text-gray-500 uppercase tracking-widest mb-3">
                Main Stream
              </p>
            </div>
            <.settings_row label="RTSP URI" description="Main stream RTSP endpoint">
              <.input
                field={config[:stream_uri]}
                type="text"
                placeholder="rtsp://camera1:554/video/stream1"
              />
            </.settings_row>
            <.settings_row label="Snapshot URI" description="Main stream HTTP snapshot endpoint">
              <.input
                field={config[:snapshot_uri]}
                type="text"
                placeholder="http://camera1:80/snapshot"
              />
            </.settings_row>

            <div class="px-5 pb-1 pt-4 border-t border-gray-100 dark:border-gray-700">
              <p class="text-xs font-semibold text-gray-400 dark:text-gray-500 uppercase tracking-widest mb-3">
                Sub Stream
              </p>
            </div>
            <.settings_row label="RTSP URI" description="Sub stream RTSP endpoint (optional)">
              <.input
                field={config[:sub_stream_uri]}
                type="text"
                placeholder="rtsp://camera1:554/video/stream2"
              />
            </.settings_row>
            <.settings_row
              label="Snapshot URI"
              description="Sub stream HTTP snapshot endpoint (optional)"
            >
              <.input
                field={config[:sub_snapshot_uri]}
                type="text"
                placeholder="http://camera1:80/snapshot2"
              />
            </.settings_row>
          </.inputs_for>
          <:footer>
            <.section_status saved={@save_section == "stream_config"} />
            <.button type="submit" phx-disable-with="Saving...">Save</.button>
          </:footer>
        </.settings_section>
      </.simple_form>

      <%!-- Section: Webcam Settings (webcam only) --%>
      <.simple_form
        :if={@device.type == :webcam}
        id={"webcam_form_#{@device.id}"}
        for={@device_form}
        phx-submit="save_webcam_settings"
        phx-target={@myself}
      >
        <.settings_section title="Webcam Settings">
          <.inputs_for :let={config} field={@device_form[:stream_config]}>
            <.settings_row label="Frame Rate" description="Capture frame rate (5–30 fps)">
              <.input
                field={config[:framerate]}
                type="number"
                step="0.01"
                min="5"
                max="30"
                placeholder="e.g. 30"
              />
            </.settings_row>
            <.settings_row
              label="Resolution"
              description="Capture resolution in WIDTHxHEIGHT format"
            >
              <.input field={config[:resolution]} type="text" placeholder="e.g. 1920x1080" />
            </.settings_row>
          </.inputs_for>
          <:footer>
            <.section_status saved={@save_section == "webcam_settings"} />
            <.button type="submit" phx-disable-with="Saving...">Save</.button>
          </:footer>
        </.settings_section>
      </.simple_form>

      <%!-- Section: Storage --%>
      <.simple_form
        id={"storage_form_#{@device.id}"}
        for={@device_form}
        phx-change="validate_storage"
        phx-submit="save_storage"
        phx-target={@myself}
      >
        <.settings_section title="Storage">
          <.inputs_for :let={storage_config} field={@device_form[:storage_config]}>
            <.settings_row label="Recording Mode" description="When to record from this device">
              <.input
                field={storage_config[:recording_mode]}
                type="select"
                options={[{"Always", "always"}, {"On Event", "on_event"}, {"Never", "never"}]}
              />
            </.settings_row>

            <div :if={@recording_mode != "never"}>
              <div :if={@device.type in [:ip, :webcam]}>
                <.settings_row
                  label="Full Drive Threshold (%)"
                  description="Percentage at which the drive is considered full"
                >
                  <.input
                    field={storage_config[:full_drive_threshold]}
                    type="number"
                    min="0"
                    max="99"
                  />
                </.settings_row>
                <.settings_row
                  label="Full Drive Action"
                  description="What to do when the drive reaches the threshold"
                >
                  <.input
                    field={storage_config[:full_drive_action]}
                    type="select"
                    options={[{"Overwrite oldest recordings", "overwrite"}, {"Do nothing", "nothing"}]}
                  />
                </.settings_row>
                <.settings_row
                  :if={@device.type == :ip}
                  label="Record Sub Stream"
                  description="Whether to also record the sub stream"
                >
                  <.input
                    field={storage_config[:record_sub_stream]}
                    type="select"
                    options={[{"Never", "never"}, {"Always", "always"}]}
                  />
                </.settings_row>
              </div>

              <div class="px-5 py-4 border-t border-gray-100 dark:border-gray-700">
                <p class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-3">
                  Recording Schedule
                </p>
                <p class="text-xs text-gray-500 dark:text-gray-400 mb-4">
                  Define time windows when recording is active. Leave empty to record continuously.
                </p>
                <.vue
                  v-component="ScheduleFormInput"
                  class="e-h-full"
                  form_field={Map.take(storage_config[:schedule], [:id, :name, :value])}
                  v-socket={@socket}
                />
              </div>
            </div>
          </.inputs_for>
          <:footer>
            <.section_status saved={@save_section == "storage"} />
            <.button type="submit" phx-disable-with="Saving...">Save</.button>
          </:footer>
        </.settings_section>
      </.simple_form>

      <%!-- Section: Snapshot Upload (IP cameras only) --%>
      <.simple_form
        :if={@device.type == :ip}
        id={"snapshot_form_#{@device.id}"}
        for={@device_form}
        phx-submit="save_snapshot"
        phx-target={@myself}
      >
        <.settings_section title="Snapshot Upload">
          <.inputs_for :let={snapshot_config} field={@device_form[:snapshot_config]}>
            <.settings_row
              label="Enable Snapshot Upload"
              description="Periodically upload snapshots to a remote storage"
            >
              <.input
                field={snapshot_config[:enabled]}
                type="checkbox"
                label="Upload snapshots to remote storage"
              />
            </.settings_row>

            <div :if={snapshot_config[:enabled].value}>
              <.settings_row
                label="Upload Interval (s)"
                description="How often to upload a snapshot (5–3600 seconds)"
              >
                <.input
                  field={snapshot_config[:upload_interval]}
                  type="number"
                  min="5"
                  max="3600"
                />
              </.settings_row>
              <.settings_row
                label="Remote Storage"
                description="Target remote storage for snapshot uploads"
              >
                <.input
                  field={snapshot_config[:remote_storage]}
                  type="select"
                  options={@remote_storages}
                  prompt="Select remote storage"
                />
              </.settings_row>
              <div class="px-5 py-4 border-t border-gray-100 dark:border-gray-700">
                <p class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-3">
                  Upload Schedule
                </p>
                <p class="text-xs text-gray-500 dark:text-gray-400 mb-4">
                  Define time windows when snapshot uploads are active. Leave empty to upload continuously.
                </p>
                <.vue
                  v-component="ScheduleFormInput"
                  class="e-h-full"
                  form_field={Map.take(snapshot_config[:schedule], [:id, :name, :value])}
                  v-socket={@socket}
                />
              </div>
            </div>
          </.inputs_for>
          <:footer>
            <.section_status saved={@save_section == "snapshot"} />
            <.button type="submit" phx-disable-with="Saving...">Save</.button>
          </:footer>
        </.settings_section>
      </.simple_form>

      <%!-- Section: Advanced (IP cameras when recording is enabled) --%>
      <.simple_form
        :if={@device.type == :ip and @recording_mode != "never"}
        id={"advanced_form_#{@device.id}"}
        for={@device_form}
        phx-submit="save_advanced"
        phx-target={@myself}
      >
        <.settings_section title="Advanced">
          <.inputs_for :let={settings} field={@device_form[:settings]}>
            <.settings_row
              label="Generate BIF"
              description="Generate trick-play index files for timeline thumbnails"
            >
              <.input field={settings[:generate_bif]} type="checkbox" label="Generate BIF files" />
            </.settings_row>
            <.settings_row
              label="LPR Events"
              description="Pull license plate recognition events from the camera"
            >
              <.input
                field={settings[:enable_lpr]}
                type="checkbox"
                label="Enable LPR event polling"
              />
            </.settings_row>
          </.inputs_for>
          <:footer>
            <.section_status saved={@save_section == "advanced"} />
            <.button type="submit" phx-disable-with="Saving...">Save</.button>
          </:footer>
        </.settings_section>
      </.simple_form>

      <%!-- Section: Danger Zone (admins only) --%>
      <div
        :if={@current_user.role == :admin}
        id={"danger_zone_#{@device.id}"}
        class="bg-white dark:bg-gray-800 rounded-xl border border-red-200 dark:border-red-900 shadow-sm overflow-hidden"
      >
        <div class="px-5 py-3.5 border-b border-red-200 dark:border-red-900 bg-red-50 dark:bg-red-950/30">
          <h3 class="text-xs font-semibold text-red-600 dark:text-red-400 uppercase tracking-widest">
            Danger Zone
          </h3>
        </div>
        <div class="px-5 py-4 flex flex-col sm:flex-row sm:items-center gap-4 sm:gap-8">
          <div class="flex-1">
            <p class="text-sm font-medium text-gray-700 dark:text-gray-300">Delete Device</p>
            <p class="text-xs text-gray-400 dark:text-gray-500 mt-0.5">
              Permanently remove this device and all its recording metadata. Files on disk will not be deleted.
            </p>
          </div>
          <div :if={not @confirm_delete}>
            <button
              type="button"
              phx-click="toggle_confirm_delete"
              phx-target={@myself}
              class="inline-flex items-center justify-center whitespace-nowrap rounded-md text-sm font-semibold h-10 px-4 py-2 bg-red-600 hover:bg-red-700 active:bg-red-800 text-white shadow-sm transition-all"
            >
              Delete Device
            </button>
          </div>
          <div :if={@confirm_delete} class="flex items-center gap-3">
            <span class="text-sm text-gray-600 dark:text-gray-400">Are you sure?</span>
            <button
              type="button"
              phx-click="delete_device"
              phx-target={@myself}
              class="inline-flex items-center justify-center whitespace-nowrap rounded-md text-sm font-semibold h-10 px-4 py-2 bg-red-600 hover:bg-red-700 active:bg-red-800 text-white shadow-sm transition-all"
            >
              Yes, delete
            </button>
            <button
              type="button"
              phx-click="toggle_confirm_delete"
              phx-target={@myself}
              class="inline-flex items-center justify-center whitespace-nowrap rounded-md text-sm font-semibold h-10 px-4 py-2 bg-gray-100 hover:bg-gray-200 active:bg-gray-300 text-gray-700 dark:bg-gray-700 dark:hover:bg-gray-600 dark:text-gray-300 shadow-sm transition-all"
            >
              Cancel
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true

  defp password_field(assigns) do
    assigns = assign(assigns, :errors, Enum.map(assigns.field.errors, &translate_error(&1)))

    ~H"""
    <div phx-feedback-for={@field.name}>
      <div class="relative">
        <input
          type="password"
          id={@field.id}
          name={@field.name}
          value={Phoenix.HTML.Form.normalize_value("password", @field.value)}
          autocomplete="new-password"
          class={[
            "mt-1 block w-full rounded-lg text-black focus:ring-0 sm:text-sm sm:leading-6 pr-10",
            "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
            "border-zinc-300 focus:border-zinc-400 dark:bg-gray-600 dark:border-gray-500",
            "placeholder-gray-400 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500",
            @errors != [] && "border-rose-400 focus:border-rose-400"
          ]}
        />
        <button
          type="button"
          tabindex="-1"
          class="absolute right-2 top-1/2 -translate-y-1/2 p-1 text-gray-400 hover:text-gray-600 dark:hover:text-gray-200 transition-colors"
          phx-click={JS.toggle_attribute({"type", "password", "text"}, to: "##{@field.id}")}
          aria-label="Toggle password visibility"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
            />
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"
            />
          </svg>
        </button>
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  attr :saved, :boolean, required: true

  defp section_status(assigns) do
    ~H"""
    <span
      :if={@saved}
      class="flex items-center gap-1.5 text-sm text-green-600 dark:text-green-400"
    >
      <svg class="w-4 h-4 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
      </svg>
      Saved
    </span>
    <span :if={not @saved}></span>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true
  slot :footer

  defp settings_section(assigns) do
    ~H"""
    <div class="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 shadow-sm overflow-hidden">
      <div class="px-5 py-3.5 border-b border-gray-200 dark:border-gray-700">
        <h3 class="text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-widest">
          {@title}
        </h3>
      </div>
      <div class="divide-y divide-gray-100 dark:divide-gray-700">
        {render_slot(@inner_block)}
      </div>
      <div
        :if={@footer != []}
        class="px-5 py-3 border-t border-gray-100 dark:border-gray-700 flex items-center justify-between"
      >
        {render_slot(@footer)}
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :description, :string, default: nil
  slot :inner_block, required: true

  defp settings_row(assigns) do
    ~H"""
    <div class="px-5 py-4 flex flex-col sm:flex-row sm:items-start gap-3 sm:gap-8">
      <div class="sm:w-56 shrink-0">
        <p class="text-sm font-medium text-gray-700 dark:text-gray-300">{@label}</p>
        <p :if={@description} class="text-xs text-gray-400 dark:text-gray-500 mt-0.5">
          {@description}
        </p>
      </div>
      <div class="flex-1 min-w-0">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    device = assigns.device

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:device_form, fn ->
       to_form(Devices.change_device_update(device, %{}))
     end)
     |> assign_new(:recording_mode, fn ->
       Atom.to_string(Device.recording_mode(device))
     end)
     |> assign_new(:remote_storages, fn -> list_remote_storages() end)
     |> assign_new(:save_section, fn -> nil end)
     |> assign_new(:confirm_delete, fn -> false end)}
  end

  @impl true
  def handle_event("validate_storage", %{"device" => device_params}, socket) do
    recording_mode =
      get_in(device_params, ["storage_config", "recording_mode"]) || "always"

    {:noreply, assign(socket, :recording_mode, recording_mode)}
  end

  @impl true
  def handle_event("save_general", %{"device" => device_params}, socket) do
    do_save(socket, device_params, "general")
  end

  @impl true
  def handle_event("save_connection", %{"device" => device_params}, socket) do
    do_save(socket, device_params, "connection")
  end

  @impl true
  def handle_event("save_stream_config", %{"device" => device_params}, socket) do
    do_save(socket, device_params, "stream_config")
  end

  @impl true
  def handle_event("save_webcam_settings", %{"device" => device_params}, socket) do
    do_save(socket, device_params, "webcam_settings")
  end

  @impl true
  def handle_event("save_storage", %{"device" => device_params}, socket) do
    do_save(socket, decode_schedule(device_params), "storage")
  end

  @impl true
  def handle_event("save_snapshot", %{"device" => device_params}, socket) do
    do_save(socket, decode_schedule(device_params), "snapshot")
  end

  @impl true
  def handle_event("save_advanced", %{"device" => device_params}, socket) do
    do_save(socket, device_params, "advanced")
  end

  @impl true
  def handle_event("toggle_confirm_delete", _params, socket) do
    {:noreply, assign(socket, :confirm_delete, not socket.assigns.confirm_delete)}
  end

  @impl true
  def handle_event("delete_device", _params, socket) do
    user = socket.assigns.current_user
    device = socket.assigns.device

    with :ok <- authorize(user, :device, :delete),
         :ok <- Devices.delete(device) do
      {:noreply,
       socket
       |> put_flash(:info, "Device #{device.name} deleted successfully")
       |> push_navigate(to: ~p"/devices")}
    else
      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You are not authorized to delete this device")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not delete device")}
    end
  end

  defp do_save(socket, device_params, section) do
    device = socket.assigns.device

    case Devices.update(device, device_params) do
      {:ok, updated_device} ->
        send(self(), {:device_updated, updated_device})
        changeset = Devices.change_device_update(updated_device, %{})

        {:noreply,
         socket
         |> assign(:device, updated_device)
         |> assign(:device_form, to_form(changeset))
         |> assign(:recording_mode, Atom.to_string(Device.recording_mode(updated_device)))
         |> assign(:save_section, section)}

      {:error, changeset} ->
        {:noreply, assign(socket, device_form: to_form(changeset), save_section: nil)}
    end
  end

  defp list_remote_storages do
    RemoteStorages.list() |> Enum.map(& &1.name)
  end

  defp decode_schedule(params) do
    params =
      if params["storage_config"],
        do: update_in(params, ["storage_config", "schedule"], &do_decode_schedule/1),
        else: params

    if params["snapshot_config"],
      do: update_in(params, ["snapshot_config", "schedule"], &do_decode_schedule/1),
      else: params
  end

  defp do_decode_schedule(schedule) when is_binary(schedule), do: Jason.decode!(schedule)
  defp do_decode_schedule(schedule), do: schedule
end
