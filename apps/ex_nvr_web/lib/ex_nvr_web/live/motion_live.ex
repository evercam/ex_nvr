defmodule ExNVRWeb.MotionLive do
  use ExNVRWeb, :live_view

  alias Ecto.Changeset
  alias ExNVR.Devices
  alias ExNVR.Recordings
  alias ExNVR.Model.Device
  alias ExNVRWeb.TimelineComponent
  alias ExNVR.Model.Motion
  alias ExNVR.Motions
  alias ExNVR.Pipelines.Main
  alias ExNVR.Recordings
  alias Evision, as: Cv

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
        </div>

        <div class="relative mt-4">
          <div :if={@live_view_enabled?} class="relative">
            <div id="video-container">
                <%= if @current_snapshot.loading do %>
                  <svg
                    aria-hidden="true"
                    class="w-24 h-24 mt-20 mx-auto text-gray-200 animate-spin dark:text-gray-600 fill-blue-600"
                    viewBox="0 0 100 101"
                    fill="none"
                    xmlns="http://www.w3.org/2000/svg"
                  >
                    <path d="M100 50.5908C100 78.2051 77.6142 100.591 50 100.591C22.3858 100.591 0 78.2051 0 50.5908C0 22.9766 22.3858 0.59082 50 0.59082C77.6142 0.59082 100 22.9766 100 50.5908ZM9.08144 50.5908C9.08144 73.1895 27.4013 91.5094 50 91.5094C72.5987 91.5094 90.9186 73.1895 90.9186 50.5908C90.9186 27.9921 72.5987 9.67226 50 9.67226C27.4013 9.67226 9.08144 27.9921 9.08144 50.5908Z" fill="currentColor"/>
                    <path d="M93.9676 39.0409C96.393 38.4038 97.8624 35.9116 97.0079 33.5539C95.2932 28.8227 92.871 24.3692 89.8167 20.348C85.8452 15.1192 80.8826 10.7238 75.2124 7.41289C69.5422 4.10194 63.2754 1.94025 56.7698 1.05124C51.7666 0.367541 46.6976 0.446843 41.7345 1.27873C39.2613 1.69328 37.813 4.19778 38.4501 6.62326C39.0873 9.04874 41.5694 10.4717 44.0505 10.1071C47.8511 9.54855 51.7191 9.52689 55.5402 10.0491C60.8642 10.7766 65.9928 12.5457 70.6331 15.2552C75.2735 17.9648 79.3347 21.5619 82.5849 25.841C84.9175 28.9121 86.7997 32.2913 88.1811 35.8758C89.083 38.2158 91.5421 39.6781 93.9676 39.0409Z" fill="currentFill"/>
                  </svg>
                <% else %>
                  <%= if @current_snapshot.ok? && @current_snapshot.result do %>
                    <div class="flex flex-row space-x-5">
                      <div class="flex flex-col">
                        <span class="dark:text-white"> Before </span>
                        <img
                          id="snapshot-before"
                          class="h-full dark:bg-gray-500 rounded-tr rounded-tl"
                          src={"data:image/png;base64,#{@current_snapshot.result.image}"}
                        />
                      </div>
                    </div>
                  <% end %>
                <% end %>
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
      |> assign_current_snapshot()
      #|> start_interval()

    {:ok, assign(socket, start_date: nil, custom_duration: false)}
  end

  def start_interval(socket) do
    case :timer.send_interval(1000, self(), :timer) do
      {:ok, ref} ->
        socket
        |> assign(interval_timer: 0)
        |> assign(timer_ref: ref)
      {:error, _} -> socket
    end
  end

  def handle_info(:timer, socket) do
    socket =
      socket
      |> assign(interval_timer: socket.assigns.interval_timer + 1)
      |> assign_current_snapshot()

    {:noreply, socket}
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

    {:noreply, socket}
  end

  def handle_event("switch_stream", %{"stream" => stream}, socket) do
    socket =
      socket
      |> assign_form(%{"stream" => stream, "device" => socket.assigns.current_device.id})
      |> live_view_enabled?()

    {:noreply, socket}
  end

  def handle_event("datetime", %{"value" => value}, socket) do
    current_datetime = socket.assigns.start_date
    new_datetime = parse_datetime(value)

    socket =
      if current_datetime != new_datetime do
        socket
        |> assign_start_date(new_datetime)
        |> assign_current_snapshot()
        |> live_view_enabled?()
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
      |> Jason.encode!()

    assign(socket, segments: segments)
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

  defp parse_datetime(datetime) do
    case DateTime.from_iso8601(datetime <> ":00Z") do
      {:ok, date, _} -> date
      _ -> nil
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

  defp assign_current_snapshot(%{assigns: %{current_device: nil}} = socket), do: assign_async(socket, :current_snapshot, {:ok, %{current_snapshot: ""}})
  defp assign_current_snapshot(%{assigns: %{live_view_enabled: false}} = socket), do: assign_async(socket, :current_snapshot, {:ok, %{current_snapshot: ""}})
  defp assign_current_snapshot(%{assigns: %{current_device: current_device, start_date: nil}} = socket) do
    assign_async(
      socket,
      :current_snapshot,
      fn ->
        with {:ok, snapshot_byte} <- Main.live_snapshot(current_device, :jpeg),
            latest_time <- Motions.get_latest_timestamp(current_device.id),
            rois <- Motions.get_with_device_time(latest_time, current_device.id),
            snapshot <- draw_rectangles(snapshot_byte, rois) do
          {:ok, %{current_snapshot: %{image: snapshot}}}
        else
          _ -> {:failed, "couldn't get the message"}
        end
      end)
  end

  defp assign_current_snapshot(
    %{
      assigns: %{
        current_device: current_device,
        start_date: start_date,
        interval_timer: interval_timer
      }
    } = socket) do

    time = DateTime.add(start_date, interval_timer, :second)
    assign_async(
      socket,
      :current_snapshot,
      fn ->
        with {:ok, snapshot_byte} <- serve_snapshot_from_recorded_videos(current_device, time),
            latest_time <- Motions.get_closest_time(time, current_device.id),
            rois <- Motions.get_with_device_time(latest_time, current_device.id),
            snapshot <- draw_rectangles(snapshot_byte, rois) do
          {:ok, %{current_snapshot: %{image: snapshot}}}
        else
          _ -> {:error, "couldn't get the message"}
        end
      end)
  end

  defp serve_snapshot_from_recorded_videos(device, time) do
    recording_dir = ExNVR.Utils.recording_dir(device.id)

    with [recording] <- Recordings.get_recordings_between(device.id, time, time),
         {:ok, _timestamp, snapshot} <-
           Recordings.Snapshooter.snapshot(recording, recording_dir, time) do
      {:ok, snapshot}
    else
      [] -> {:error, :not_found}
    end
  end

  defp draw_rectangles(snapshot, rois) do
    snapshot
    |> Cv.imdecode(Cv.Constant.cv_IMREAD_ANYCOLOR())
    |> then(&Enum.reduce(rois, &1, fn roi, acc ->
      %Motion.MotionLabelDimention{x: x, y: y, width: w, height: h} = roi.dimentions
      Evision.rectangle(acc, {x, y}, {x + w, y + h}, {255, 0, 0}, thickness: 4, lineType: 4)
    end))
    |> then(&Cv.imencode(".png", &1))
    |> Base.encode64()
  end
end
