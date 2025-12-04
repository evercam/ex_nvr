defmodule ExNVRWeb.RecordingListLive do
  @moduledoc false
  alias ExNVR.RemovableStorage.Export

  require Logger
  use ExNVRWeb, :live_view

  import ExNVRWeb.ViewUtils

  alias ExNVR.{Devices, Recordings}
  alias ExNVRWeb.Router.Helpers, as: Routes

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grow e-m-8">
      <div>
        <!-- filters -->
        <div class="flex gap-5 ">
          <.filter_form meta={@meta} devices={@devices} id="recording-filter-form" />
          <div class="relative min-w-40 mb-4">
            <button
              phx-click={show_modal("copy-to-usb-modal")}
              class={"absolute bottom-0 py-2 px-3 flex gap-2 rounded-md " <>
         if @export_done, do: "bg-blue-500 text-white", else: "bg-green-500 text-white"}
            >
              <p>Export</p>

              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
                class="size-5"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5m-13.5-9L12 3m0 0 4.5 4.5M12 3v13.5"
                />
              </svg>
            </button>
          </div>
        </div>

        <.modal
          id="copy-to-usb-modal"
          class="bg-gray-900/70 p-3 flex items-center justify-center  w-full"
        >
          <div class="p-5 w-[60rem]">
            
    <!-- stepperr -->

            <ol class="flex items-center w-full text-sm font-medium text-center text-body sm:text-base">
              
    <!-- destination -->
              <li class="flex md:w-full items-center text-fg-brand sm:after:content-[''] after:w-full after:h-1 after:border-b  after:border-gray-500 after:border-px after:hidden sm:after:inline-block after:mx-6 xl:after:mx-10">
                <span class=" text-white flex items-center after:content-['/'] sm:after:hidden after:mx-2 after:text-fg-disabled">
                  <span
                    :if={@step == 1}
                    class="me-2 rounded-full h-6 w-6 text-white flex items-center justify-center bg-blue-500"
                  >
                    1
                  </span>

                  <svg
                    :if={@step > 1}
                    class="w-5 h-5 me-1.5 bg-blue-500 rounded-full"
                    aria-hidden="true"
                    xmlns="http://www.w3.org/2000/svg"
                    width="24"
                    height="24"
                    fill="none"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke="currentColor"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M8.5 11.5 11 14l4-4m6 2a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"
                    />
                  </svg>
                  <span class="font-bold"> Destination </span>
                </span>
              </li>
              
    <!-- Format -->

              <li class="flex md:w-full items-center after:content-[''] after:w-full after:h-1 after:border-b after:border-gray-500 after:border-px after:hidden sm:after:inline-block after:mx-6 xl:after:mx-10">
                <span class="flex items-center after:content-['/'] sm:after:hidden after:mx-2 after:text-fg-disabled">
                  
    <!-- Circle OR Check Mark -->
                  <%= if @step > 2 do %>
                    <!-- Completed step -->
                    <svg
                      class="w-6 h-6 me-2 bg-blue-500 text-white rounded-full p-1"
                      aria-hidden="true"
                      xmlns="http://www.w3.org/2000/svg"
                      fill="none"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke="currentColor"
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M8.5 11.5 11 14l4-4m6 2a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"
                      />
                    </svg>
                  <% else %>
                    <!-- Normal numbered step -->
                    <span class={[
                      "me-2 h-6 w-6 rounded-full flex items-center justify-center text-white",
                      (@step == 2 && "bg-blue-500") || "bg-gray-500"
                    ]}>
                      2
                    </span>
                  <% end %>
                  
    <!-- Label -->
                  <span class={[
                    "font-bold",
                    (@step >= 2 && "text-white") || "text-gray-500"
                  ]}>
                    Format
                  </span>
                </span>
              </li>
              
    <!-- confirmation -->
              <li class="flex items-center">
                <span class={
                  "me-2 rounded-full h-6 w-6 text-white flex items-center justify-center " <>
                    if @step == 3, do: "bg-blue-500", else: "bg-gray-500"
                    }>
                  3
                </span>

                <span class={[
                  "font-bold",
                  (@step == 3 && "text-white") || "text-gray-500"
                ]}>
                  Confirmation
                </span>
              </li>
            </ol>
            
    <!-- export to usb form -->

            <.form
              for={}
              phx-change="validate-export-to-usb-configs"
              class="mt-5"
              phx-submit="export_to_usb"
            >
              <!-- filters -> device, start date, end date -->
              <div class="flex justify-between gap-5 hidden bg-red-300">
                <Flop.Phoenix.filter_fields
                  :let={f}
                  form={to_form(@meta)}
                  fields={[
                    device_id: [
                      op: :==,
                      type: "select",
                      options: Enum.map(@devices, &{&1.name, &1.id}),
                      prompt: "Choose your device",
                      label: "Device"
                    ],
                    start_date: [op: :>=, type: "datetime-local", label: "Start Date"],
                    end_date: [op: :<=, type: "datetime-local", label: "End Date"]
                  ]}
                >
                  <div>
                    <.input
                      class="border rounded p-1"
                      field={f.field}
                      type={f.type}
                      label={f.label}
                      phx-debounce="500"
                      {f.rest}
                    />
                  </div>
                </Flop.Phoenix.filter_fields>
              </div>
              
    <!-- destination -->
              <div :if={@step == 2} class="my-3">
                <h2 class="mb-2 text-gray-300 text-sm">Export format</h2>
                <.input
                  id="duration"
                  type="radio"
                  name="type"
                  value=""
                  label="Export format"
                  options={[
                    {"Export as 1-Minute Segments", "one"},
                    {"Export as a Single Merged Video", "full"}
                  ]}
                />
                <label :if={@type == "Export as a single Merged Video"} class="text-green">
                  Note if the recording are greater than 1 hr, it will be export in chunks of 1 hr
                </label>

                <div>
                  <.input
                    :if={@custom == "custom"}
                    class=""
                    id="custom"
                    type="text"
                    name="custom_duration"
                    value=""
                    placeholder="Time in days"
                  />
                </div>
              </div>
              <!-- format -->
              <div :if={@step == 1} class="my-3">
                <span :if={@total_rec_size != nil} class="block mb-5 text-green-500 font-bold">
                  Footage Size: {@total_rec_size} MB
                </span>
                <label class="text-white"> Select Export Destination </label>
                <.input
                  id="export_to"
                  type="radio"
                  name="export_to"
                  value=""
                  label="Export format"
                  errors={@errors}
                  options={[
                    {"USB", "usb"},
                    {"Remote Storage", "remote"}
                  ]}
                />

                <h2 :if={@export_to == "USB"} class="mb-2 text-gray-300 text-sm mt-5">
                  Select Your USB
                </h2>
                <div :if={@removable_device != nil && @export_to == "USB"}>
                  <%= for device <- @removable_device.partitions do %>
                    <label class="flex items-center p-3 mb-5  rounded-lg border border-gray-600 bg-gray-700 cursor-pointer">
                      <!--Radio -->
                      <input
                        type="radio"
                        name="destination"
                        value={device.mountpoints}
                        class="form-radio h-4 w-4 mt-2 text-blue-500 border-gray-500 bg-gray-600"
                      />
                      <span class="ml-2 text-sm text-gray-300">
                        {device.mountpoints || "/"}
                      </span>

                      <div class="grow flex flex-col space-y-1 ml-3">
                        <span class="text-xs text-gray-400 self-end">{device.size}</span>
                      </div>
                    </label>
                  <% end %>
                  <%= if @errors[:usb_size] do %>
                    <p class="text-red-500 text-sm">{@errors[:usb_size]}</p>
                  <% end %>
                </div>
                <h2 :if={@removable_device == nil && @export_to == "USB"}>No usb detected</h2>
              </div>
              
    <!-- confirmation -->
              <div :if={@step == 3} class="my-3 text-white">
                <h4>Your footage will be save in this particular format</h4>
                <p>
                  Rec_<span class="font-bold">_start_date </span>_to_<span class="font-bold">end_date</span>
                </p>
              </div>

              <div class="flex justify-end text-blue-500 gap-5 font-bold">
                <button :if={@step > 1} type="button" phx-click="prev"> PREV</button>
                <button
                  :if={@step == 3}
                  type="submit"
                  class="px-4 py-2 bg-blue-600 text-sm rounded-lg hover:bg-blue-500 transition text-white"
                >
                  Export Footage
                </button>
                <button :if={@step < 3} type="button" phx-click="next"> NEXT</button>
              </div>
            </.form>
          </div>
        </.modal>
      </div>

      <Flop.Phoenix.table
        id="recordings"
        opts={ExNVRWeb.FlopConfig.table_opts()}
        items={@recordings}
        meta={@meta}
        path={~p"/recordings"}
      >
        <:col :let={recording} label="Id" field={:id}>{recording.id}</:col>
        <:col :let={recording} label="Device" field={:device_name}>{recording.device_name}</:col>
        <:col :let={recording} label="Start-date" field={:start_date}>
          {format_date(recording.start_date, recording.timezone)}
        </:col>
        <:col :let={recording} label="End-date" field={:end_date}>
          {format_date(recording.end_date, recording.timezone)}
        </:col>
        <:action :let={recording}>
          <div class="flex justify-end">
            <button
              data-popover-target={"popover-click-#{recording.id}"}
              data-popover-trigger="click"
              phx-click="fetch-details"
              phx-value-id={recording.id}
              type="button"
            >
              <span title="Show information">
                <.icon
                  name="hero-information-circle-solid"
                  class="w-6 h-6 mr-2 dark:text-gray-400 cursor-pointer"
                />
              </span>
            </button>
            <.recording_details_popover
              recording={recording}
              rec_details={@files_details[recording.id]}
            />
            <span
              title="Preview recording"
              phx-click={open_popup(recording)}
              id={"thumbnail-#{recording.id}"}
            >
              <.icon
                name="hero-eye-solid"
                class="w-6 h-6 z-auto mr-2 dark:text-gray-400 cursor-pointer thumbnail"
              />
            </span>
            <div class="flex justify-end">
              <.link
                href={~p"/api/devices/#{recording.device_id}/recordings/#{recording.filename}/blob"}
                class="inline-flex items-center text-gray-900 rounded-lg"
                id={"recording-#{recording.id}-link"}
              >
                <span title="Download recording">
                  <.icon name="hero-arrow-down-tray-solid" class="w-6 h-6 dark:text-gray-400" />
                </span>
              </.link>
            </div>
          </div>
        </:action>
      </Flop.Phoenix.table>

      <.pagination meta={@meta} />
    </div>
    <!-- Popup container -->
    <div
      id="popup-container"
      class="popup-container fixed top-0 left-0 w-full h-full bg-black bg-opacity-75 flex justify-center items-center hidden"
    >
      <button class="popup-close absolute top-4 right-4 text-white" phx-click={close_popup()}>
        ×
      </button>
      <video id="recording-player" autoplay class="w-full h-auto max-w-full max-h-[80%]"></video>
    </div>
    """
  end

  def filter_form(%{meta: meta, devices: devices} = assigns) do
    assigns = assign(assigns, form: to_form(meta), meta: meta, devices: devices)

    ~H"""
    <div class="flex justify-between">
      <.form for={@form} id={@id} phx-change="filter-recordings" class="flex items-baseline space-x-4">
        <Flop.Phoenix.filter_fields
          :let={f}
          form={@form}
          fields={[
            device_id: [
              op: :==,
              type: "select",
              options: Enum.map(@devices, &{&1.name, &1.id}),
              prompt: "Choose your device",
              label: "Device"
            ],
            start_date: [op: :>=, type: "datetime-local", label: "Start Date"],
            end_date: [op: :<=, type: "datetime-local", label: "End Date"]
          ]}
        >
          <div>
            <.input
              class="border rounded p-1"
              field={f.field}
              type={f.type}
              label={f.label}
              phx-debounce="500"
              {f.rest}
            />
          </div>
        </Flop.Phoenix.filter_fields>
      </.form>
    </div>
    """
  end

  def recording_details_popover(%{rec_details: rec_details} = assigns) do
    assigns =
      if rec_details && rec_details != :error,
        do:
          assign(
            assigns,
            :video_track,
            Enum.find(rec_details.track_details, &(&1.type == :video))
          ),
        else: assigns

    ~H"""
    <div
      data-popover
      id={"popover-click-#{@recording.id}"}
      role="tooltip"
      class="absolute z-10 invisible inline-block w-64 text-sm text-gray-500 transition-opacity duration-300 bg-white border border-gray-200 rounded-lg shadow-sm opacity-0 dark:text-gray-400 dark:border-gray-600 dark:bg-gray-800"
    >
      <div class="px-3 py-2 bg-gray-100 border-b border-gray-200 rounded-t-lg dark:border-gray-600 dark:bg-gray-700">
        <h3 class="font-semibold text-gray-900 dark:text-white">Recording Details</h3>
      </div>
      <div :if={@rec_details && @rec_details != :error} class="px-3 py-2 grid">
        <p class="text-left text-sm font-bold dark:text-white">General</p>
        <table class="ml-3 mb-3 text-left text-xs">
          <tr>
            <td class="font-semibold">Size:</td>
            <td>{humanize_size(@rec_details.size)}</td>
          </tr>
          <tr>
            <td class="font-semibold">Duration:</td>
            <td>{humanize_duration(@rec_details.duration)}</td>
          </tr>
        </table>
        <p :if={@video_track} class="text-left text-sm font-bold dark:text-white">Video</p>
        <table :if={@video_track} class="ml-3 text-left text-xs">
          <tr>
            <td class="font-semibold">Codec:</td>
            <td>{@video_track.media} ({@video_track.media_tag})</td>
          </tr>
          <tr>
            <td class="font-semibold">Resolution:</td>
            <td>{@video_track.width} x {@video_track.height}</td>
          </tr>
          <tr>
            <td class="font-semibold">Bitrate:</td>
            <td>{humanize_bitrate(ExMP4.Track.bitrate(@video_track))}</td>
          </tr>
          <tr>
            <td class="font-semibold">fps:</td>
            <td>{Float.round(ExMP4.Track.fps(@video_track), 2)}</td>
          </tr>
        </table>
      </div>
      <p :if={@rec_details == :error} class="px-3 py-2 text-red-500">
        Error while fetching details of the recording (the file may not exists)
      </p>
      <div data-popper-arrow></div>
    </div>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    Phoenix.PubSub.subscribe(ExNVR.PubSub, "removable_storage_topic")
    Phoenix.PubSub.subscribe(ExNVR.PubSub, "export_notifacation")
    Recordings.subscribe_to_recording_events()

    {:ok,
     assign(socket,
       devices: Devices.list(),
       filter_params: params,
       pagination_params: %{},
       sort_params: %{},
       files_details: %{},
       removable_device: nil,
       usb_detected: false,
       custom: nil,
       step: 1,
       export_to: nil,
       type: nil,
       errors: %{},
       total_rec_size: nil,
       export_done: true
     )}
  end

  def handle_info({:usb, device}, socket) when device != nil do
    {:noreply,
     socket
     |> assign(:removable_device, device)
     |> assign(:usb_detected, true)
     |> put_flash(:info, "Usb Detected")}
  end

  def handle_info(:export_done, socket) do
    {:noreply, put_flash(socket, :info, "Export completed successfully.")}
  end

  def handle_info({:export_failed, reason}, socket) do
    {:noreply, put_flash(socket, :error, "Export failed: #{reason}")}
  end

  def handle_info({:progress, %{done: done}}, socket) do
    {:noreply, assign(socket, export_done: true)}
  end

  @impl true
  def handle_info(_msg, socket) do
    params =
      Map.merge(socket.assigns.filter_params, socket.assigns.pagination_params)
      |> Map.merge(socket.assigns.sort_params)

    load_recordings(params, socket)
  end

  @impl true
  def handle_params(params, _uri, socket) do
    load_recordings(params, socket)
  end

  @impl true
  def handle_event("filter-recordings", filter_params, socket) do
    {:noreply,
     socket
     |> assign(:filter_params, filter_params)
     |> assign(:pagination_params, %{})
     |> push_patch(to: Routes.recording_list_path(socket, :list, filter_params))}
  end

  def handle_event("op", params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("paginate", pagination_params, socket) do
    pagination_params = Map.merge(socket.assigns.pagination_params, pagination_params)

    params =
      Map.merge(socket.assigns.filter_params, pagination_params)
      |> Map.merge(socket.assigns.sort_params)

    {:noreply,
     socket
     |> assign(pagination_params: pagination_params)
     |> push_patch(to: Routes.recording_list_path(socket, :list, params), replace: true)}
  end

  @impl true
  def handle_event("fetch-details", %{"id" => recording_id}, socket) do
    files_details = socket.assigns.files_details
    recording_id = String.to_integer(recording_id)
    recording = Enum.find(socket.assigns.recordings, &(&1.id == recording_id))
    device = Enum.find(socket.assigns.devices, &(&1.id == recording.device_id))

    files_details =
      with :error <- Map.fetch(files_details, recording_id),
           {:error, reason} <- Recordings.details(device, recording) do
        Logger.error("could not fetch file details, due to: #{inspect(reason)}")
        Map.put(files_details, recording_id, :error)
      else
        {:ok, details} -> Map.put(socket.assigns.files_details, recording_id, details)
      end

    {:noreply, assign(socket, :files_details, files_details)}
  end

  @impl true
  def handle_event("validate-before-opening-modal", params, socket) do
    {:noreply, socket}
  end

  # export to usb
  @impl true
  def handle_event("validate-export-to-usb-configs", params, socket) do
    {:noreply,
     socket
     |> update_assigns("type", params)
     |> update_assigns("export_to", params)
     |> update_assigns("destination", params)}
  end

  @impl true
  def handle_event("export_to_usb", params, socket) do
    type =
      case socket.assigns.type do
        "Export as 1-Minute Segments" -> :one
        "Export as a Single Merged Video" -> :full
      end

    {device_id, start_date, end_date} =
      get_values(params["filters"])

    device = Enum.find(socket.assigns.devices, &(&1.id == device_id))

    socket = put_flash(socket, :info, "Exporting footage to usb..")

    ExNVR.Recordings.Export.export_to_usb(
      type,
      device,
      start_date,
      end_date,
      socket.assigns.destination
    )

    {:noreply, redirect(socket, to: ~p"/recordings")}
  end

  def handle_event("next", _params, socket) do
    {:noreply,
     socket
     |> update(:step, &min(&1 + 1, 3))}
  end

  def handle_event("prev", _params, socket) do
    {:noreply, update(socket, :step, &max(&1 - 1, 1))}
  end

  defp load_recordings(params, socket) do
    sort_params = Map.take(params, ["order_by", "order_directions"])

    case Recordings.list(params) do
      {:ok, {recordings, meta}} ->
        socket
        |> assign(meta: meta, recordings: recordings, sort_params: sort_params)
        |> push_event("reload-popovers", %{})
        |> then(&{:noreply, &1})

      {:error, meta} ->
        {:noreply, assign(socket, meta: meta)}
    end
  end

  def open_popup(recording) do
    JS.remove_class("hidden", to: "#popup-container")
    |> JS.set_attribute(
      {"src", "/api/devices/#{recording.device_id}/recordings/#{recording.filename}/blob"},
      to: "#recording-player"
    )
  end

  def close_popup do
    JS.add_class("hidden", to: "#popup-container")
    |> JS.set_attribute({"src", nil}, to: "#recording-player")
  end

  def format_date(date, timezone) do
    date
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime("%b %d, %Y %H:%M:%S %z")
  end

  def get_values(filters) do
    f = fn field ->
      filters
      |> Map.values()
      |> Enum.find(&(&1["field"] == field))
      |> Map.get("value")
    end

    {f.("device_id"), f.("start_date"), f.("end_date")}
  end

  def update_assigns(socket, param, params) when param in ["type", "export_to"] do
    case params[param] do
      nil ->
        socket

      par ->
        socket
        |> assign(String.to_atom(param), par)
    end
  end

  def update_assigns(socket, "destination", params) do
    device =
      Enum.find(socket.assigns.devices, &(&1.id == params["filters"]["0"]["value"]))

    device_id = params["filters"]["0"]["value"]
    start_date = params["filters"]["1"]["value"]

    end_date = params["filters"]["2"]["value"]

    recordings =
      Recordings.get_recordings_between(
        device_id,
        :high,
        start_date,
        end_date
      )

    total_rec_size =
      get_total_recording_size(device, start_date, end_date, 0, false)

    Enum.reduce(recordings, 0, fn rec, acc ->
      {:ok, details} = Recordings.details(device, rec)

      acc + details.size
    end)

    socket = assign(socket, :total_rec_size, (total_rec_size / 1_000_000) |> Float.floor(2))

    case params["destination"] do
      nil ->
        socket

      dest ->
        disk_size =
          ExNVRWeb.DeviceLive.get_disks_data()
          |> Enum.find(fn {path, _sizes} ->
            nil
            path == params["destination"]
          end)
          |> then(fn {_path, {size, _used}} -> size end)

        errors =
          if total_rec_size > disk_size * 1024 do
            Map.put(socket.assigns.errors, :usb_size, "No enough space in the removable disk")
          else
            socket.assigns.errors
          end

        socket
        |> assign(:destination, dest)
        |> assign(:errors, errors)
    end
  end

  @spec get_recording_sizes(binary(), map()) :: non_neg_integer()
  def get_recording_sizes(device_id, rec) do
    {:ok, stats} =
      Recordings.recording_path(device_id, rec.stream, rec)
      |> File.stat()

    stats.size
  end

  def get_total_recording_size(device, start_date, end_date, size, done) when done == false do
    recordings =
      Recordings.get_recordings_between(device.id, :high, start_date, end_date)

    case recordings do
      [] ->
        get_total_recording_size(device, start_date, end_date, size, true)

      rec ->
        size =
          size +
            Enum.reduce(rec, 0, fn rec, acc ->
              {:ok, details} = Recordings.details(device, rec)

              acc + details.size
            end)

        start_date = List.last(rec).end_date

        get_total_recording_size(device, start_date, end_date, size, false)
    end
  end

  def get_total_recording_size(_device, _start_date, _end_date, size, done) when done == true,
    do: size
end
