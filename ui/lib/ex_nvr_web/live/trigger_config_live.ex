defmodule ExNVRWeb.TriggerConfigLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  alias ExNVR.Triggers
  alias ExNVR.Triggers.{TriggerConfig, TriggerSourceConfig, TriggerTargetConfig}

  def render(assigns) do
    ~H"""
    <div class="grow max-w-3xl mx-auto e-py-10">
      <div class="bg-white p-6 border rounded-lg dark:border-gray-700 dark:bg-gray-800 dark:text-white">
        <h3 class="mb-4 text-xl text-center font-medium text-gray-900 dark:text-white">
          {if @trigger_config.id, do: "Update trigger", else: "Create a new trigger"}
        </h3>

        <.simple_form
          id="trigger_config_form"
          for={@form}
          class="space-y-6"
          phx-change="validate"
          phx-submit="save"
        >
          <.input field={@form[:name]} type="text" label="Name" placeholder="Trigger name" required />
          <.input field={@form[:enabled]} type="checkbox" label="Enabled" />

          <:actions>
            <.button :if={is_nil(@trigger_config.id)} class="w-full" phx-disable-with="Creating...">
              {if @trigger_config.id, do: "Update", else: "Create"}
            </.button>
            <.button :if={@trigger_config.id} class="w-full" phx-disable-with="Updating...">
              Update
            </.button>
          </:actions>
        </.simple_form>

        <%!-- Sources section (only shown after trigger is created) --%>
        <div :if={@trigger_config.id} class="mt-8">
          <div class="relative flex py-5 items-center">
            <span class="flex-shrink mr-4 text-black dark:text-white font-medium">
              Event Sources
            </span>
            <div class="flex-grow border-t border-gray-400"></div>
          </div>

          <div :if={@trigger_config.source_configs != []} class="mb-4 space-y-2">
            <div
              :for={source <- @trigger_config.source_configs}
              class="flex items-center justify-between p-3 bg-gray-50 dark:bg-gray-700 rounded-lg"
            >
              <div>
                <span class="font-medium">{source.source_type}</span>
                <span
                  :if={source.config["event_type"]}
                  class="text-sm text-gray-500 dark:text-gray-400 ml-2"
                >
                  (event_type: {source.config["event_type"]})
                </span>
              </div>
              <button
                phx-click="delete-source"
                phx-value-source_id={source.id}
                class="text-red-500 hover:text-red-700 text-sm"
              >
                Remove
              </button>
            </div>
          </div>

          <p
            :if={@trigger_config.source_configs == []}
            class="text-sm text-gray-500 dark:text-gray-400 mb-4"
          >
            No event sources configured. Add one below.
          </p>

          <div class="p-4 bg-gray-50 dark:bg-gray-700 rounded-lg">
            <h4 class="text-sm font-medium mb-3">Add Event Source</h4>
            <form phx-submit="add-source" class="flex items-end gap-3">
              <div class="flex-1">
                <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Source Type
                </label>
                <select
                  name="source_type"
                  class="w-full rounded-lg border-gray-300 dark:border-gray-600 dark:bg-gray-800 dark:text-white"
                >
                  <option :for={type <- TriggerSourceConfig.source_types()} value={type}>
                    {type}
                  </option>
                </select>
              </div>
              <div class="flex-1">
                <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Event Type
                </label>
                <input
                  name="event_type"
                  type="text"
                  placeholder="e.g. motion_detected"
                  required
                  class="w-full rounded-lg border-gray-300 dark:border-gray-600 dark:bg-gray-800 dark:text-white"
                />
              </div>
              <.button type="submit" class="flex-shrink-0">Add</.button>
            </form>
          </div>
        </div>

        <%!-- Targets section (only shown after trigger is created) --%>
        <div :if={@trigger_config.id} class="mt-8">
          <div class="relative flex py-5 items-center">
            <span class="flex-shrink mr-4 text-black dark:text-white font-medium">Targets</span>
            <div class="flex-grow border-t border-gray-400"></div>
          </div>

          <div :if={@trigger_config.target_configs != []} class="mb-4 space-y-2">
            <div
              :for={target <- @trigger_config.target_configs}
              class="flex items-center justify-between p-3 bg-gray-50 dark:bg-gray-700 rounded-lg"
            >
              <div>
                <span class="font-medium">{humanize_target_type(target.target_type)}</span>
                <span
                  :if={!target.enabled}
                  class="ml-2 text-xs text-gray-400 bg-gray-200 dark:bg-gray-600 px-2 py-0.5 rounded"
                >
                  disabled
                </span>
                <span
                  :if={target.target_type == "log_message"}
                  class="text-sm text-gray-500 dark:text-gray-400 ml-2"
                >
                  (level: {target.config["level"] || "info"}, prefix: {target.config["message_prefix"] ||
                    "Trigger"})
                </span>
              </div>
              <button
                phx-click="delete-target"
                phx-value-target_id={target.id}
                class="text-red-500 hover:text-red-700 text-sm"
              >
                Remove
              </button>
            </div>
          </div>

          <p
            :if={@trigger_config.target_configs == []}
            class="text-sm text-gray-500 dark:text-gray-400 mb-4"
          >
            No targets configured. Add one below.
          </p>

          <div class="p-4 bg-gray-50 dark:bg-gray-700 rounded-lg">
            <h4 class="text-sm font-medium mb-3">Add Target</h4>
            <form phx-submit="add-target" phx-change="target-type-changed" class="space-y-3">
              <div class="flex items-end gap-3">
                <div class="flex-1">
                  <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                    Target Type
                  </label>
                  <select
                    name="target_type"
                    class="w-full rounded-lg border-gray-300 dark:border-gray-600 dark:bg-gray-800 dark:text-white"
                  >
                    <option
                      :for={type <- TriggerTargetConfig.target_types()}
                      value={type}
                      selected={type == @selected_target_type}
                    >
                      {humanize_target_type(type)}
                    </option>
                  </select>
                </div>
              </div>

              <div :if={@selected_target_type == "log_message"} class="flex items-end gap-3">
                <div class="flex-1">
                  <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                    Log Level
                  </label>
                  <select
                    name="level"
                    class="w-full rounded-lg border-gray-300 dark:border-gray-600 dark:bg-gray-800 dark:text-white"
                  >
                    <option :for={level <- ~w(debug info warning error)} value={level}>
                      {level}
                    </option>
                  </select>
                </div>
                <div class="flex-1">
                  <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                    Message Prefix
                  </label>
                  <input
                    name="message_prefix"
                    type="text"
                    value="Trigger"
                    class="w-full rounded-lg border-gray-300 dark:border-gray-600 dark:bg-gray-800 dark:text-white"
                  />
                </div>
              </div>

              <.button type="submit" class="flex-shrink-0">Add Target</.button>
            </form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(%{"id" => "new"}, _session, socket) do
    changeset = TriggerConfig.changeset(%{})

    {:ok,
     assign(socket,
       trigger_config: %TriggerConfig{},
       form: to_form(changeset),
       selected_target_type: "log_message"
     )}
  end

  def mount(%{"id" => id}, _session, socket) do
    trigger_config = Triggers.get_trigger_config!(String.to_integer(id))
    changeset = TriggerConfig.changeset(trigger_config, %{})

    {:ok,
     assign(socket,
       trigger_config: trigger_config,
       form: to_form(changeset),
       selected_target_type: "log_message"
     )}
  end

  def handle_event("validate", %{"trigger_config" => params}, socket) do
    changeset =
      TriggerConfig.changeset(socket.assigns.trigger_config, params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"trigger_config" => params}, socket) do
    trigger_config = socket.assigns.trigger_config

    if trigger_config.id,
      do: do_update(socket, trigger_config, params),
      else: do_create(socket, params)
  end

  def handle_event("target-type-changed", %{"target_type" => target_type}, socket) do
    {:noreply, assign(socket, selected_target_type: target_type)}
  end

  def handle_event("target-type-changed", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("add-source", params, socket) do
    trigger_config = socket.assigns.trigger_config

    source_params = %{
      trigger_config_id: trigger_config.id,
      source_type: params["source_type"],
      config: %{"event_type" => params["event_type"]}
    }

    case Triggers.create_source_config(source_params) do
      {:ok, _} ->
        trigger_config = Triggers.get_trigger_config!(trigger_config.id)
        {:noreply, assign(socket, trigger_config: trigger_config)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not add source")}
    end
  end

  def handle_event("delete-source", %{"source_id" => source_id}, socket) do
    source = ExNVR.Repo.get!(TriggerSourceConfig, source_id)

    case Triggers.delete_source_config(source) do
      {:ok, _} ->
        trigger_config = Triggers.get_trigger_config!(socket.assigns.trigger_config.id)
        {:noreply, assign(socket, trigger_config: trigger_config)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete source")}
    end
  end

  def handle_event("add-target", params, socket) do
    trigger_config = socket.assigns.trigger_config
    target_type = params["target_type"]

    config =
      case target_type do
        "log_message" ->
          %{
            "level" => params["level"] || "info",
            "message_prefix" => params["message_prefix"] || "Trigger"
          }

        _ ->
          %{}
      end

    target_params = %{
      trigger_config_id: trigger_config.id,
      target_type: target_type,
      config: config
    }

    case Triggers.create_target_config(target_params) do
      {:ok, _} ->
        trigger_config = Triggers.get_trigger_config!(trigger_config.id)
        {:noreply, assign(socket, trigger_config: trigger_config)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not add target")}
    end
  end

  def handle_event("delete-target", %{"target_id" => target_id}, socket) do
    target = ExNVR.Repo.get!(TriggerTargetConfig, target_id)

    case Triggers.delete_target_config(target) do
      {:ok, _} ->
        trigger_config = Triggers.get_trigger_config!(socket.assigns.trigger_config.id)
        {:noreply, assign(socket, trigger_config: trigger_config)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete target")}
    end
  end

  defp do_create(socket, params) do
    case Triggers.create_trigger_config(params) do
      {:ok, trigger_config} ->
        socket
        |> put_flash(:info, "Trigger created successfully")
        |> redirect(to: ~p"/triggers/#{trigger_config.id}")
        |> then(&{:noreply, &1})

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp do_update(socket, trigger_config, params) do
    case Triggers.update_trigger_config(trigger_config, params) do
      {:ok, updated} ->
        updated = Triggers.get_trigger_config!(updated.id)
        changeset = TriggerConfig.changeset(updated, %{})

        socket
        |> put_flash(:info, "Trigger updated successfully")
        |> assign(trigger_config: updated, form: to_form(changeset))
        |> then(&{:noreply, &1})

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp humanize_target_type("log_message"), do: "Log Message"
  defp humanize_target_type("start_recording"), do: "Start Recording"
  defp humanize_target_type("stop_recording"), do: "Stop Recording"
  defp humanize_target_type(other), do: other
end
