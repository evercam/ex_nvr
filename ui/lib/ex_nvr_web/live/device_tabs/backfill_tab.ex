defmodule ExNVRWeb.DeviceTabs.BackfillTab do
  @moduledoc false

  use ExNVRWeb, :live_component

  import ExNVR.Authorization
  import ExNVRWeb.Components.Settings

  alias ExNVR.Recordings.BackfillJob

  @default_min_gap 10

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.simple_form
        id={"backfill_form_#{@device.id}"}
        for={@form}
        phx-submit="start_backfill"
        phx-target={@myself}
      >
        <.settings_section title="Recover footage from camera storage">
          <div class="px-5 py-4 space-y-4">
            <p class="text-sm text-gray-600 dark:text-gray-300">
              Download footage stored on the camera (SD card or internal storage) to fill gaps in this device's recordings.
              Only footage missing from the NVR is downloaded.
            </p>
            <.backfill_status :if={@backfill} backfill={@backfill} timezone={@device.timezone} />
            <.backfill_result :if={is_nil(@backfill) and @last_result} result={@last_result} />
          </div>
          <.settings_row label="Minimum gap" description="Gaps shorter than this are skipped">
            <div class="flex items-center gap-3">
              <div class="w-32">
                <.input field={@form[:min_gap]} type="number" min="1" step="1" disabled={!!@backfill} />
              </div>
              <span class="text-sm text-gray-500 dark:text-gray-400">minutes</span>
            </div>
          </.settings_row>
          <:footer>
            <span></span>
            <.button
              id="start-backfill"
              type="submit"
              disabled={!!@backfill}
              phx-disable-with="Starting..."
            >
              {if @backfill, do: "Recovering footage…", else: "Recover footage"}
            </.button>
          </:footer>
        </.settings_section>
      </.simple_form>
    </div>
    """
  end

  attr :backfill, :map, required: true
  attr :timezone, :string, required: true

  defp backfill_status(assigns) do
    ~H"""
    <div
      id="backfill-in-progress"
      class="flex items-start gap-3 rounded-lg border border-blue-200 dark:border-blue-800 bg-blue-50 dark:bg-blue-900/30 px-4 py-3 text-sm text-blue-800 dark:text-blue-200"
    >
      <.icon name="hero-arrow-path" class="w-5 h-5 shrink-0 animate-spin" />
      <div>
        <p class="font-medium">
          Recovering footage since {format_date(@backfill.started_at, @timezone)}
        </p>
        <p class="mt-0.5">
          Filling gaps longer than {@backfill.min_gap} min. It keeps running in the background if you leave this page.
        </p>
      </div>
    </div>
    """
  end

  attr :result, :any, required: true

  defp backfill_result(%{result: {:completed, []}} = assigns) do
    ~H"""
    <div
      id="backfill-result"
      class={[
        banner_class(),
        "border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-900/40 text-gray-700 dark:text-gray-300"
      ]}
    >
      <.icon name="hero-information-circle" class="w-5 h-5 shrink-0" />
      <p>No missing footage found on the camera.</p>
    </div>
    """
  end

  defp backfill_result(%{result: {:completed, runs}} = assigns) do
    assigns = assign(assigns, :duration, runs |> recovered_duration() |> format_duration())

    ~H"""
    <div
      id="backfill-result"
      class={[
        banner_class(),
        "border-green-200 dark:border-green-800 bg-green-50 dark:bg-green-900/30 text-green-800 dark:text-green-200"
      ]}
    >
      <.icon name="hero-check-circle" class="w-5 h-5 shrink-0" />
      <p>Recovered {@duration} of footage.</p>
    </div>
    """
  end

  defp backfill_result(%{result: {:failed, reason}} = assigns) do
    assigns = assign(assigns, :reason, format_reason(reason))

    ~H"""
    <div
      id="backfill-result"
      class={[
        banner_class(),
        "border-red-200 dark:border-red-800 bg-red-50 dark:bg-red-900/30 text-red-800 dark:text-red-200"
      ]}
    >
      <.icon name="hero-exclamation-triangle" class="w-5 h-5 shrink-0" />
      <p>Recovery failed: {@reason}</p>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn -> to_form(%{"min_gap" => @default_min_gap}, as: :backfill) end)}
  end

  @impl true
  def handle_event("start_backfill", %{"backfill" => params}, socket) do
    with :ok <- authorize(socket.assigns.current_user, :device, :update),
         {:ok, min_gap} <- parse_min_gap(params["min_gap"]),
         {:ok, _pid} <- BackfillJob.start(socket.assigns.device, min_gap) do
      {:noreply, assign(socket, :form, to_form(params, as: :backfill))}
    else
      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You are not authorized to perform this action")}

      {:error, :invalid_min_gap} ->
        form =
          to_form(params,
            as: :backfill,
            errors: [min_gap: {"must be a whole number of at least 1 minute", []}]
          )

        {:noreply, assign(socket, :form, form)}

      {:error, :already_running} ->
        {:noreply,
         put_flash(socket, :error, "Footage is already being recovered for this device")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not start recovering footage")}
    end
  end

  defp parse_min_gap(value) do
    case Integer.parse(value || "") do
      {min_gap, ""} when min_gap >= 1 -> {:ok, min_gap}
      _other -> {:error, :invalid_min_gap}
    end
  end

  defp recovered_duration(runs) do
    Enum.reduce(runs, 0, &(&2 + DateTime.diff(&1.end_date, &1.start_date)))
  end

  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_duration(seconds) do
    [
      {div(seconds, 86_400), "d"},
      {div(rem(seconds, 86_400), 3600), "h"},
      {div(rem(seconds, 3600), 60), "m"}
    ]
    |> Enum.reject(fn {value, _unit} -> value == 0 end)
    |> Enum.map_join(" ", fn {value, unit} -> "#{value}#{unit}" end)
  end

  defp format_reason(:not_implemented), do: "this camera does not support downloading recordings."
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp format_date(date, timezone) do
    date
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime("%b %d, %Y · %H:%M:%S %Z")
  end

  defp banner_class, do: "flex items-start gap-3 rounded-lg border px-4 py-3 text-sm"
end
