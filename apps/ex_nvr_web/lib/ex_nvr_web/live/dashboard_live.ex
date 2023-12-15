defmodule ExNVRWeb.DashboardLive do
  use ExNVRWeb, :live_view

  alias Ecto.Changeset
  alias ExNVR.Devices
  alias ExNVR.Recordings
  alias ExNVR.Model.Device
  alias ExNVRWeb.TimelineComponent

  @durations [
    {"2 Minutes", "120"},
    {"5 Minutes", "300"},
    {"10 Minutes", "600"},
    {"30 Minutes", "1800"},
    {"1 Hour", "3600"},
    {"2 Hours", "7200"},
    {"Custom", ""}
  ]

  def render(assigns) do
    ~H"""
    <div class="bg-white sm:w-2/3 dark:bg-gray-800">
      <div :if={@devices == []} class="grid tracking-wide text-lg text-center dark:text-gray-200">
        You have no devices, you can create one
        <span><.link href={~p"/devices"} class="ml-2 dark:text-blue-600">here</.link></span>
      </div>
      <div :if={@devices != []}>
        <div class="flex items-center justify-between invisible sm:visible">
          <.simple_form for={@form} id="device_form">
            <div class="flex items-center">
              <div class="mr-4">
                <.input
                  field={@form[:device]}
                  id="device_form_id"
                  type="select"
                  label="Device"
                  options={Enum.map(@devices, &{&1.name, &1.id})}
                  phx-change="switch_device"
                />
              </div>

              <div class={[@start_date && "hidden"]}>
                <.input
                  field={@form[:stream]}
                  type="select"
                  label="Stream"
                  options={@supported_streams}
                  phx-change="switch_stream"
                />
              </div>
            </div>
          </.simple_form>

          <div class="mt-20 mb-2">
            <.button
              id="download-footage-btn"
              class="bg-blue-500 text-white px-4 py-2 rounded flex items-center"
              phx-click={show_modal("download-modal")}
            >
              <span title="Download footage" class="mr-2">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  class="w-5 h-5"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="1.5"
                    d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5M16.5 12L12 16.5m0 0L7.5 12m4.5 4.5V3"
                  />
                </svg>
              </span>
              Download
            </.button>
          </div>
        </div>

        <div class="relative mt-4">
          <div :if={@live_view_enabled?} class="relative">
            <video
              id="live-video"
              class="w-full h-auto dark:bg-gray-500 rounded-tr rounded-tl"
              autoplay
              controls
              muted
            />
            <div
              id="snapshot-button"
              class="absolute top-1 right-1 rounded-sm bg-zinc-900 py-1 px-2 text-sm text-white dark:bg-gray-700 dark:bg-opacity-80 hover:cursor-pointer"
              phx-hook="DownloadSnapshot"
            >
              <.icon name="hero-camera"/>
            </div>
          </div>
          <div
            :if={not @live_view_enabled?}
            class="relative text-lg rounded-tr rounded-tl text-center dark:text-gray-200 mt-4 w-full dark:bg-gray-500 h-96 flex justify-center items-center d-flex"
          >
            Device is not recording, live view is not available
          </div>
          <.live_component
            module={TimelineComponent}
            id="tl"
            segments={@segments}
            timezone={@timezone}
          />
        </div>
      </div>

      <.modal id="download-modal">
        <div class="bg-white dark:bg-gray-800 p-8 rounded">
          <h2 class="text-xl text-white font-bold mb-4">Download Footage</h2>
          <.simple_form
            for={@footage_form}
            id="footage_form"
            class="w-full space-y-4"
            phx-submit="download_footage"
          >
            <div class="space-y-2">
              <div class="mr-4 w-full p-2 rounded">
                <.input
                  field={@footage_form[:device_id]}
                  id="footage_device_id"
                  type="select"
                  label="Device"
                  options={Enum.map(@devices, &{&1.name, &1.id})}
                  required
                />
              </div>
              <div class="mr-4 w-full p-2 rounded">
                <.input
                  field={@footage_form[:start_date]}
                  id="footage_start_date"
                  type="datetime-local"
                  label="Start Date"
                  required
                />
              </div>

              <div class="mr-4 w-full p-2 rounded">
                <.input
                  field={@footage_form[:duration]}
                  id="footage_duration"
                  type="select"
                  label="Duration"
                  options={durations()}
                  phx-change="footage_duration"
                  required
                />
              </div>

              <div :if={@custom_duration}>
                <div class="mr-4 w-full p-2 rounded">
                  <.input
                    field={@footage_form[:end_date]}
                    id="footage_end_date"
                    type="datetime-local"
                    label="End Date"
                    required
                  />
                </div>
              </div>

              <div class="mr-4 w-full p-2 rounded flex justify-center space-x-4">
                <.button
                  class="bg-blue-500 text-white px-4 py-2 rounded flex items-center"
                  phx-disable-with="Downloading..."
                >
                  Download
                </.button>
              </div>
            </div>
          </.simple_form>
        </div>
      </.modal>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_devices()
      |> assign_current_device()
      |> assign_streams()
      |> assign_form(nil)
      |> assign_footage_form(%{})
      |> assign_start_date(nil)
      |> live_view_enabled?()
      |> assign_runs()
      |> assign_timezone()
      |> maybe_push_stream_event(nil)

    {:ok, assign(socket, start_date: nil, custom_duration: false)}
  end

  def handle_event("switch_device", %{"device" => device_id}, socket) do
    device = Enum.find(socket.assigns.devices, &(&1.id == device_id))

    socket =
      socket
      |> assign_current_device(device)
      |> assign_streams()
      |> assign_form(nil)
      |> assign_footage_form(%{})
      |> live_view_enabled?()
      |> assign_runs()
      |> assign_timezone()
      |> maybe_push_stream_event(socket.assigns.start_date)

    {:noreply, socket}
  end

  def handle_event("switch_stream", %{"stream" => stream}, socket) do
    socket =
      socket
      |> assign_form(%{"stream" => stream, "device" => socket.assigns.current_device.id})
      |> live_view_enabled?()
      |> maybe_push_stream_event(socket.assigns.start_date)

    {:noreply, socket}
  end

  def handle_event("datetime", %{"value" => value}, socket) do
    current_datetime = socket.assigns.start_date
    timezone = socket.assigns.current_device.timezone
    new_datetime = parse_datetime(value, timezone)

    socket =
      if current_datetime != new_datetime do
        socket
        |> assign_start_date(new_datetime)
        |> live_view_enabled?()
        |> maybe_push_stream_event(new_datetime)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("footage_duration", %{"footage" => params}, socket) do
    if params["duration"] == "",
      do: {:noreply, assign(socket, custom_duration: true)},
      else: {:noreply, assign(socket, custom_duration: false)}
  end

  def handle_event("download_footage", %{"footage" => params}, socket) do
    device = Enum.find(socket.assigns.devices, &(&1.id == params["device_id"]))

    case validate_footage_req_params(params, device.timezone) do
      {:ok, params} ->
        query_params = %{
          start_date: format_date(params[:start_date]),
          end_date: format_date(params[:end_date]),
          duration: params[:duration]
        }

        socket
        |> push_event("download-footage", %{
          url: ~p"/api/devices/#{device.id}/footage/?#{query_params}"
        })
        |> then(&{:noreply, &1})

      {:error, changeset} ->
        {:noreply, assign_footage_form(socket, changeset)}
    end
  end

  defp assign_devices(socket) do
    assign(socket, devices: Devices.list())
  end

  defp assign_current_device(socket, device \\ nil) do
    devices = socket.assigns.devices
    assign(socket, current_device: device || List.first(devices))
  end

  defp assign_start_date(socket, start_date), do: assign(socket, start_date: start_date)

  defp assign_streams(%{assigns: %{current_device: nil}} = socket), do: socket

  defp assign_streams(socket) do
    device = socket.assigns.current_device

    supported_streams =
      if Device.has_sub_stream(device) do
        [{"Main Stream", "main_stream"}, {"Sub Stream", "sub_stream"}]
      else
        [{"Main Stream", "main_stream"}]
      end

    assign(socket, supported_streams: supported_streams)
  end

  defp assign_runs(%{assigns: %{current_device: nil}} = socket), do: socket

  defp assign_runs(socket) do
    device = socket.assigns.current_device

    segments =
      Recordings.list_runs(%{device_id: device.id})
      |> Enum.map(&Map.take(&1, [:start_date, :end_date]))
      |> shift_timezones(device.timezone)
      |> Jason.encode!()

    assign(socket, segments: segments)
  end

  defp shift_timezones(dates, timezone) do
    Enum.map(dates, fn %{start_date: start_date, end_date: end_date} ->
      %{
        start_date: DateTime.shift_zone!(start_date, timezone) |> DateTime.to_naive(),
        end_date: DateTime.shift_zone!(end_date, timezone) |> DateTime.to_naive()
      }
    end)
  end

  defp assign_timezone(%{assigns: %{current_device: nil}} = socket), do: socket

  defp assign_timezone(socket) do
    assign(socket, timezone: socket.assigns.current_device.timezone)
  end

  defp assign_form(%{assigns: %{current_device: nil}} = socket, _params), do: socket

  defp assign_form(socket, nil) do
    device = socket.assigns.current_device
    assign(socket, form: to_form(%{"device" => device.id, "stream" => "main_stream"}))
  end

  defp assign_form(socket, params) do
    assign(socket, form: to_form(params))
  end

  defp assign_footage_form(socket, params) do
    assign(socket, footage_form: to_form(params, as: "footage"))
  end

  defp maybe_push_stream_event(socket, datetime) do
    cond do
      not connected?(socket) ->
        socket

      not socket.assigns.live_view_enabled? ->
        socket

      true ->
        device = socket.assigns.current_device
        current_stream = if socket.assigns.form.params["stream"] == "main_stream", do: 0, else: 1

        {stream_url, poster_url} = stream_url(device, datetime, current_stream)

        push_event(socket, "stream", %{src: stream_url, poster: poster_url})
    end
  end

  defp live_view_enabled?(socket) do
    device = socket.assigns.current_device
    start_date = socket.assigns[:start_date]

    enabled? =
      cond do
        is_nil(device) -> false
        not is_nil(start_date) -> true
        not ExNVR.Utils.run_main_pipeline?() -> false
        device.state == :recording -> true
        true -> false
      end

    assign(socket, live_view_enabled?: enabled?)
  end

  defp parse_datetime(datetime, timezone) do
    with {:ok, naive_date} <- NaiveDateTime.from_iso8601(datetime),
         {:ok, zoned_date} <- DateTime.from_naive(naive_date, timezone) do
      zoned_date
    else
      _ -> nil
    end
  end

  defp stream_url(device, datetime, current_stream) do
    stream_url =
      ~p"/api/devices/#{device.id}/hls/index.m3u8?#{%{pos: format_date(datetime), stream: current_stream}}"

    if datetime do
      poster_url = ~p"/api/devices/#{device.id}/snapshot?#{%{time: format_date(datetime)}}"
      {stream_url, poster_url}
    else
      {stream_url, nil}
    end
  end

  defp format_date(nil), do: nil
  defp format_date(datetime), do: DateTime.to_iso8601(datetime)

  defp durations(), do: @durations

  def validate_footage_req_params(params, timezone) do
    types = %{
      device_id: :string,
      start_date: :naive_datetime,
      end_date: :native_datetime,
      duration: :integer
    }

    {%{}, types}
    |> Changeset.cast(params, Map.keys(types))
    |> Changeset.validate_required([:device_id, :start_date])
    |> Changeset.validate_number(:duration, greater_than: 5, less_than_or_equal_to: 7200)
    |> validate_end_date_or_duration()
    |> recording_exists?(timezone)
    |> Changeset.apply_action(:create)
    |> case do
      {:ok, params} ->
        params
        |> Map.update!(:start_date, &DateTime.from_naive!(&1, timezone))
        |> Map.update(:end_date, nil, fn datetime ->
          datetime && DateTime.from_naive!(datetime, timezone)
        end)
        |> then(&{:ok, &1})

      error ->
        error
    end
  end

  defp validate_end_date_or_duration(%{valid?: false} = changeset), do: changeset

  defp validate_end_date_or_duration(changeset) do
    start_date = Changeset.get_change(changeset, :start_date)
    end_date = Changeset.get_change(changeset, :end_date)
    duration = Changeset.get_change(changeset, :duration)

    cond do
      is_nil(end_date) and is_nil(duration) ->
        Changeset.add_error(
          changeset,
          :end_date,
          "At least one field should be provided: end_date or duration",
          validation: :required
        )

      not is_nil(end_date) and
          (NaiveDateTime.diff(start_date, end_date) < 5 or
             NaiveDateTime.diff(start_date, end_date) > 7200) ->
        Changeset.add_error(
          changeset,
          :end_date,
          "The duration should be at least 5 seconds and at most 2 hours",
          validation: :format
        )

      true ->
        changeset
    end
  end

  defp recording_exists?(%{valid?: false} = changeset, _timezone), do: changeset

  defp recording_exists?(changeset, timezone) do
    device_id = Changeset.get_field(changeset, :device_id)

    start_date =
      changeset
      |> Changeset.get_field(:start_date)
      |> DateTime.from_naive!(timezone)

    case Recordings.get_recordings_between(device_id, start_date, start_date) do
      [] -> Changeset.add_error(changeset, :start_date, "No recordings found")
      _recordings -> changeset
    end
  end
end
