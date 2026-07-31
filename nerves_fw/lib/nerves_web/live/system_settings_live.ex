defmodule ExNVR.NervesWeb.SystemSettingsLive do
  use ExNVRWeb, :live_view

  alias ExNVR.Devices
  alias ExNVR.Nerves.Monitoring.AutoReboot
  alias ExNVR.Nerves.SystemSettings

  @preview_count 3

  def render(assigns) do
    ~H"""
    <div class="grow flex justify-center dark:text-white pt-5">
      <div class="mx-auto w-1/2">
        <div class="my-8">
          <h1 class="text-2xl font-bold">System Settings</h1>
          <p class="mt-2 dark:text-gray-400">Configure your system components and preferences</p>
        </div>

        <.tabs id="system-settings-tabs">
          <:tab id="auto_reboot" label="Auto Reboot" />
          <:tab id="ups" label="UPS" />

          <:tab_content for="auto_reboot">
          <.card class="space-y-6">
            <div>
              <div class="flex items-center gap-2 text-xl">
                <.icon name="hero-arrow-path" class="h-6 w-6" /> Auto Reboot
              </div>
              <div class="text-sm dark:text-gray-400">
                Reboot the device automatically on a recurring schedule
              </div>
            </div>

            <.simple_form
              id="auto-reboot-form"
              for={@auto_reboot_form}
              phx-change="validate-auto-reboot"
              phx-submit="submit-auto-reboot"
            >
              <div class="flex flex-col gap-4">
                <div class="w-full font-medium">
                  <.icon name="hero-clock" class="h-5 w-5 mr-1" />Reboot Schedule
                </div>
                <div class="grid grid-cols-2 gap-4">
                  <.input
                    field={@auto_reboot_form[:interval]}
                    value={@auto_reboot_form[:interval].value || ""}
                    label="Reboot Interval"
                    type="select"
                    options={reboot_intervals()}
                  />
                </div>
                <p class="text-sm dark:text-gray-400">
                  How often the device reboots itself
                </p>
              </div>
              <.separator />
              <div class={
                ["flex flex-col gap-4"] ++ disabled_class(reboot_enabled?(@auto_reboot_form))
              }>
                <div class="w-full font-medium">
                  <.icon name="hero-calendar-days" class="h-5 w-5 mr-1" />First Reboot
                </div>
                <div class="grid grid-cols-2 gap-4">
                  <.input
                    field={@auto_reboot_form[:reboot_at]}
                    label="First Reboot At"
                    type="datetime-local"
                    phx-debounce="500"
                  />
                  <.input
                    field={@auto_reboot_form[:timezone]}
                    label="Timezone"
                    type="select"
                    options={@timezones}
                  />
                </div>
                <p class="text-sm dark:text-gray-400">
                  Local wall clock of the first reboot, the next ones follow every interval after it.
                  A time in the future delays the first reboot, a past one only anchors the series.
                </p>
              </div>
              <.separator />
              <div class="flex flex-col gap-4">
                <div class="w-full font-medium">
                  <.icon name="hero-queue-list" class="h-5 w-5 mr-1" />Next Reboots
                </div>
                <p :if={@next_reboots == []} class="text-sm dark:text-gray-400">
                  No reboot is scheduled
                </p>
                <div
                  :if={@next_reboots != []}
                  class="flex flex-col gap-1 text-sm dark:text-gray-400"
                >
                  <div :for={occurrence <- @next_reboots} class="flex items-center gap-2">
                    <.icon name="hero-chevron-double-right" class="h-4 w-4" />
                    {format_occurrence(occurrence)}
                  </div>
                  <p class="mt-1 text-xs dark:text-gray-500">
                    Times are shown in {@auto_reboot_form[:timezone].value}
                  </p>
                </div>
              </div>
              <.separator />
              <div class="flex justify-end">
                <button
                  id="auto-reboot-submit-button"
                  type="submit"
                  phx-disable-with="Updating..."
                  class="phx-submit-loading:opacity-75 focus:outline-none text-white bg-green-700 hover:bg-green-800 focus:ring-4 focus:ring-green-300 font-medium rounded-lg text-sm px-5 py-2.5 me-2 mb-2 dark:bg-green-600 dark:hover:bg-green-700 dark:focus:ring-green-800"
                >
                  <.icon name="hero-document-check-solid" class="w-4 h-4 mr-1" />Update
                </button>
              </div>
            </.simple_form>
          </.card>
          </:tab_content>

          <:tab_content for="ups">
          <.card class="space-y-6">
            <div>
              <div class="flex items-center gap-2 text-xl">
                <.icon name="hero-battery-0" class="h-6 w-6" /> UPS Settings
              </div>
              <div class="text-sm dark:text-gray-400">
                Configure Uninterruptible Power Supply settings and monitoring
              </div>
            </div>

            <.simple_form for={@ups_form} phx-submit="submit">
              <div class="flex items-center justify-between">
                <div>
                  <span class="font-medium">UPS Monitoring Enabled</span>
                  <p class="text-sm dark:text-gray-400">
                    Enable or disable UPS monitoring system
                  </p>
                </div>

                <.input field={@ups_form[:enabled]} type="toggle" phx-change="enable-ups" />
              </div>
              <.separator />
              <div class={["flex flex-col gap-4"] ++ disabled_class(@ups_enabled)}>
                <div class="w-full font-medium">
                  <.icon name="hero-bolt-solid" class="h-5 w-5 mr-1" />Power Management Actions
                </div>
                <div class="grid grid-cols-2 gap-4">
                  <.input
                    field={@ups_form[:ac_failure_action]}
                    label="AC Failure Action"
                    type="select"
                    options={ups_actions()}
                  />
                  <.input
                    field={@ups_form[:low_battery_action]}
                    label="Low Battery Action"
                    type="select"
                    options={ups_actions()}
                  />
                </div>
              </div>
              <.separator />
              <div class={["flex flex-col gap-4"] ++ disabled_class(@ups_enabled)}>
                <div class="w-full font-medium">
                  <.icon name="hero-clock" class="h-5 w-5 mr-1" />Timing Configuration
                </div>
                <div class="grid grid-cols-2 gap-4">
                  <.input
                    field={@ups_form[:trigger_after]}
                    label="Trigger Action After (seconds)"
                    type="number"
                    min="0"
                    max="600"
                  />
                </div>
                <p class="text-sm dark:text-gray-400">
                  Delay before executing the configured action
                </p>
              </div>
              <.separator />
              <div class={["flex flex-col gap-4"] ++ disabled_class(@ups_enabled)}>
                <div class="w-full font-medium">
                  <.icon name="hero-cog-solid" class="h-5 w-5 mr-1" />GPIO Pin Configuration
                </div>
                <div class="grid grid-cols-2 gap-4">
                  <.input
                    field={@ups_form[:ac_pin]}
                    label="AC OK GPIO Pin"
                    type="select"
                    options={gpio_pins()}
                  />
                  <.input
                    field={@ups_form[:battery_pin]}
                    label="Low Battery GPIO Pin"
                    type="select"
                    options={gpio_pins()}
                  />
                </div>
              </div>
              <.separator />
              <div class="flex justify-end">
                <button
                  id="ups-submit-button"
                  type="submit"
                  phx-disable-with="Updating..."
                  class="phx-submit-loading:opacity-75 focus:outline-none text-white bg-green-700 hover:bg-green-800 focus:ring-4 focus:ring-green-300 font-medium rounded-lg text-sm px-5 py-2.5 me-2 mb-2 dark:bg-green-600 dark:hover:bg-green-700 dark:focus:ring-green-800"
                >
                  <.icon name="hero-document-check-solid" class="w-4 h-4 mr-1" />Update
                </button>
              </div>
            </.simple_form>
          </.card>
          </:tab_content>
        </.tabs>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(timezones: Tzdata.zone_list())
      |> assign_ups_settings()
      |> assign_ups_form()
      |> assign_auto_reboot_settings()
      |> assign_auto_reboot_form()

    {:ok, socket}
  end

  def handle_event("enable-ups", %{"ups" => %{"enabled" => enabled}}, socket) do
    {:noreply, assign(socket, ups_enabled: String.to_existing_atom(enabled))}
  end

  def handle_event("submit", %{"ups" => ups}, socket) do
    case SystemSettings.update_ups_settings(ups) do
      {:ok, %{ups: ups_settings}} ->
        socket
        |> assign_ups_settings(ups_settings)
        |> assign_ups_form()
        |> put_flash(:info, "Successfully updated UPS settings")
        |> then(&{:noreply, &1})

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_ups_form(socket, changeset.changes[:ups])}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "could not save UPS settings, due to: #{inspect(reason)}")}
    end
  end

  def handle_event("validate-auto-reboot", %{"auto_reboot" => params}, socket) do
    changeset =
      SystemSettings.State.auto_reboot_changeset(socket.assigns.auto_reboot_settings, params)

    socket
    |> assign(auto_reboot_form: to_form(changeset), next_reboots: next_reboots(changeset))
    |> then(&{:noreply, &1})
  end

  def handle_event("submit-auto-reboot", %{"auto_reboot" => params}, socket) do
    case SystemSettings.update_auto_reboot_settings(params) do
      {:ok, %{auto_reboot: auto_reboot_settings}} ->
        socket
        |> assign_auto_reboot_settings(auto_reboot_settings)
        |> assign_auto_reboot_form()
        |> put_flash(:info, "Successfully updated auto reboot settings")
        |> then(&{:noreply, &1})

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_auto_reboot_form(socket, changeset.changes[:auto_reboot])}

      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "could not save auto reboot settings, due to: #{inspect(reason)}"
         )}
    end
  end

  def handle_event(event, _params, socket) do
    {:noreply, put_flash(socket, :error, "unexpected event: #{inspect(event)}")}
  end

  defp assign_ups_settings(socket, settings \\ nil) do
    ups_settings = settings || SystemSettings.get_settings().ups
    assign(socket, ups_settings: ups_settings, ups_enabled: ups_settings.enabled)
  end

  defp assign_ups_form(socket, changeset \\ nil) do
    changeset = changeset || SystemSettings.State.ups_changeset(socket.assigns.ups_settings)
    assign(socket, ups_form: to_form(changeset))
  end

  # `settings` is only nil on the initial mount; the post-submit path passes the
  # saved settings explicitly, so prefill defaults never clobber a saved config.
  defp assign_auto_reboot_settings(socket, settings \\ nil)

  defp assign_auto_reboot_settings(socket, nil) do
    settings = prefill_auto_reboot(SystemSettings.get_settings().auto_reboot)
    assign(socket, auto_reboot_settings: settings, next_reboots: next_reboots(settings))
  end

  defp assign_auto_reboot_settings(socket, settings) do
    assign(socket, auto_reboot_settings: settings, next_reboots: next_reboots(settings))
  end

  # Prefill a never-configured schedule (no `reboot_at` yet): default the first
  # reboot to today at midnight and adopt a device's timezone when one exists.
  defp prefill_auto_reboot(%{reboot_at: nil} = settings) do
    timezone = device_timezone() || settings.timezone
    %{settings | reboot_at: NaiveDateTime.new!(today_in(timezone), ~T[00:00:00]), timezone: timezone}
  end

  defp prefill_auto_reboot(settings), do: settings

  defp device_timezone do
    case Devices.list() do
      [device | _] -> device.timezone
      [] -> nil
    end
  end

  defp today_in(timezone) do
    case DateTime.now(timezone) do
      {:ok, now} -> DateTime.to_date(now)
      {:error, _reason} -> Date.utc_today()
    end
  end

  defp assign_auto_reboot_form(socket, changeset \\ nil) do
    changeset =
      changeset ||
        SystemSettings.State.auto_reboot_changeset(socket.assigns.auto_reboot_settings)

    assign(socket, auto_reboot_form: to_form(changeset))
  end

  # View functions
  defp disabled_class(false), do: ["pointer-events-none opacity-50"]
  defp disabled_class(true), do: []

  # "No reboot" carries an empty string rather than nil so that
  # `options_for_select/2` marks it selected, `List.wrap(nil)` matches nothing.
  defp reboot_intervals do
    intervals = Enum.map(SystemSettings.State.reboot_intervals(), &{"Every #{&1} hours", &1})
    [{"No reboot", ""} | intervals]
  end

  defp reboot_enabled?(form), do: form[:interval].value not in [nil, ""]

  # The preview follows the form, an invalid draft has no meaningful schedule.
  defp next_reboots(%Ecto.Changeset{valid?: false}), do: []

  defp next_reboots(%Ecto.Changeset{} = changeset) do
    next_reboots(Ecto.Changeset.apply_changes(changeset))
  end

  defp next_reboots(%{interval: nil}), do: []

  defp next_reboots(config) do
    case DateTime.now(config.timezone) do
      {:ok, now} ->
        now
        |> DateTime.to_naive()
        |> NaiveDateTime.truncate(:second)
        |> then(&AutoReboot.next_occurrences(config, &1, @preview_count))

      {:error, _reason} ->
        []
    end
  end

  defp format_occurrence(occurrence) do
    Calendar.strftime(occurrence, "%a %b %d, %Y at %H:%M")
  end

  defp ups_actions do
    [{"Power Off", :power_off}, {"Stop Recording", :stop_recording}, {"Nothing", :nothing}]
  end

  defp gpio_pins do
    Circuits.GPIO.enumerate()
    |> Enum.map(& &1.label)
    |> Enum.reject(&(&1 == "-"))
  end
end
