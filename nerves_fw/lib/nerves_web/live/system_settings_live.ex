defmodule ExNVR.NervesWeb.SystemSettingsLive do
  use ExNVRWeb, :live_view

  alias ExNVR.Nerves.SystemSettings

  def render(assigns) do
    ~H"""
    <div class="grow flex justify-center dark:text-white pt-5">
      <div class="mx-auto w-1/2">
        <div class="my-8">
          <h1 class="text-2xl font-bold">System Settings</h1>
          <p class="mt-2 dark:text-gray-400">Configure your system components and preferences</p>
        </div>

        <div class="space-y-6">
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
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_ups_settings()
      |> assign_ups_form()

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

  # View functions
  defp disabled_class(false), do: ["pointer-events-none opacity-50"]
  defp disabled_class(true), do: []

  defp ups_actions do
    [{"Power Off", :power_off}, {"Stop Recording", :stop_recording}, {"Nothing", :nothing}]
  end

  defp gpio_pins do
    Circuits.GPIO.enumerate()
    |> Enum.map(& &1.label)
    |> Enum.reject(&(&1 == "-"))
  end
end
