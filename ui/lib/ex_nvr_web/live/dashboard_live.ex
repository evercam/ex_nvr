defmodule ExNVRWeb.DashboardLive do
  use ExNVRWeb, :live_view

  alias Ecto.Changeset
  alias ExNVR.Devices
  alias ExNVR.Recordings
  alias ExNVR.Model.Device
  alias ExNVRWeb.Router.Helpers, as: Routes

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
    <div class="bg-gray-300 e-w-full dark:bg-gray-800">
      <div :if={@devices == []} class="grid tracking-wide text-lg text-center dark:text-gray-200">
        You have no devices, you can create one
        <span><.link href={~p"/devices"} class="ml-2 dark:text-blue-600">here</.link></span>
      </div>
      <div :if={@devices != []} class="e-h-full">
        <h1 class="text-xl text-black dark:text-white font-bold mb-4">My ExNVR Custom Version</h1>
      </div>

      <.modal id="download-modal">
        <div class="bg-gray-300 dark:bg-gray-800 p-8 rounded">
          <h2 class="text-xl text-black dark:text-white font-bold mb-4">Download Footage</h2>
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
    Recordings.subscribe_to_recording_events()

    socket
    |> assign_devices()
    |> assign(
      start_date: nil,
      custom_duration: false
    )
    |> assign(stream_url: "", poster_url: "")
    |> then(&{:ok, &1})
  end

  def handle_params(params, _uri, socket) do
    devices = socket.assigns.devices

    device =
      Enum.find(socket.assigns.devices, List.first(devices), &(&1.id == params["device_id"]))

    stream = Map.get(params, "stream", socket.assigns[:stream]) || "sub_stream"

    socket
    |> assign(current_device: device)
    |> assign(stream: stream, start_date: nil)
    |> assign_streams()
    |> assign_footage_form(%{"device_id" => device && device.id})
    |> live_view_enabled?()
    |> assign_runs()
    |> assign_timezone()
    |> maybe_push_stream_event(socket.assigns.start_date)
    |> then(&{:noreply, &1})
  end

  def handle_info({event, nil}, socket) when event in [:delete, :new] do
    {:noreply, assign_runs(socket)}
  end

  def handle_info(_, socket), do: socket

  def handle_event("switch_device", %{"device" => device_id}, socket) do
    route =
      Routes.dashboard_path(socket, :new, %{device_id: device_id, stream: socket.assigns.stream})

    {:noreply, push_patch(socket, to: route, replace: true)}
  end

  def handle_event("switch_stream", %{"stream" => stream}, socket) do
    route =
      Routes.dashboard_path(socket, :new, %{
        device_id: socket.assigns.current_device.id,
        stream: stream
      })

    {:noreply, push_patch(socket, to: route, replace: true)}
  end

  def handle_event("load-recording", %{"timestamp" => timestamp}, socket) do
    current_datetime = socket.assigns.start_date
    timezone = socket.assigns.current_device.timezone
    new_datetime = parse_datetime(timestamp, timezone)

    socket =
      if current_datetime != new_datetime do
        socket
        |> assign(start_date: new_datetime)
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

  defp assign_streams(%{assigns: %{current_device: nil}} = socket), do: socket

  defp assign_streams(socket) do
    %{current_device: device, stream: stream} = socket.assigns

    {supported_streams, stream} =
      if Device.has_sub_stream(device) do
        {[
           %{name: "Main Stream", value: "main_stream"},
           %{name: "Sub Stream", value: "sub_stream"}
         ], stream}
      else
        {[%{name: "Main Stream", value: "main_stream"}], "main_stream"}
      end

    assign(socket, supported_streams: supported_streams, stream: stream)
  end

  defp assign_runs(%{assigns: %{current_device: nil}} = socket), do: socket

  defp assign_runs(socket) do
    device = socket.assigns.current_device

    segments =
      Recordings.list_runs(%{device_id: device.id})
      |> Enum.map(&Map.take(&1, [:start_date, :end_date]))
      |> shift_timezones(device.timezone)

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

        current_stream =
          if socket.assigns.stream == "main_stream", do: :high, else: :low

        {stream_url, poster_url} = stream_url(device, datetime, current_stream)

        assign(socket, stream_url: stream_url, poster_url: poster_url)
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
        true -> Device.streaming?(device)
      end

    assign(socket, live_view_enabled?: enabled?)
  end

  defp parse_datetime(nil, _), do: nil

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
      end_date: :naive_datetime,
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
          (NaiveDateTime.diff(end_date, start_date) < 5 or
             NaiveDateTime.diff(end_date, start_date) > 7200) ->
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
