defmodule ExNVRWeb.TriggerConfigLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  import ExNVR.Authorization

  alias ExNVR.Triggers

  alias ExNVR.Triggers.{
    TriggerConfig,
    TriggerSourceConfig,
    TriggerSources,
    TriggerTargetConfig,
    TriggerTargets
  }

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
              Create
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
                <span class="font-medium">{source_label(source.source_type)}</span>
                <span class="text-sm text-gray-500 dark:text-gray-400 ml-2">
                  <span :for={{key, val} <- source.config}>
                    ({format_key(key)}: {format_value(val)})
                  </span>
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
            <form phx-submit="add-source" phx-change="source-type-changed" class="space-y-3">
              <div>
                <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Source Type
                </label>
                <select
                  name="source_type"
                  class="w-full rounded-lg border-gray-300 dark:border-gray-600 dark:bg-gray-800 dark:text-white"
                >
                  <option
                    :for={{label, value} <- TriggerSources.type_options()}
                    value={value}
                    selected={value == @selected_source_type}
                  >
                    {label}
                  </option>
                </select>
              </div>
              <.config_fields fields={@source_fields} />
              <.button type="submit" class="flex-shrink-0">Add Source</.button>
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
                <span class="font-medium">{target_label(target.target_type)}</span>
                <span
                  :if={!target.enabled}
                  class="ml-2 text-xs text-gray-400 bg-gray-200 dark:bg-gray-600 px-2 py-0.5 rounded"
                >
                  disabled
                </span>
                <span
                  :if={target.config != %{}}
                  class="text-sm text-gray-500 dark:text-gray-400 ml-2"
                >
                  <span :for={{key, val} <- target.config}>
                    ({format_key(key)}: {format_value(val)})
                  </span>
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
              <div>
                <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Target Type
                </label>
                <select
                  name="target_type"
                  class="w-full rounded-lg border-gray-300 dark:border-gray-600 dark:bg-gray-800 dark:text-white"
                >
                  <option
                    :for={{label, value} <- TriggerTargets.type_options()}
                    value={value}
                    selected={value == @selected_target_type}
                  >
                    {label}
                  </option>
                </select>
              </div>
              <.config_fields fields={@target_fields} />
              <.button type="submit" class="flex-shrink-0">Add Target</.button>
            </form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :fields, :list, required: true

  defp config_fields(assigns) do
    ~H"""
    <div :for={field <- @fields}>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        {field.label}
      </label>
      <select
        :if={field.type == :select}
        name={Atom.to_string(field.name)}
        class="w-full rounded-lg border-gray-300 dark:border-gray-600 dark:bg-gray-800 dark:text-white"
      >
        <option
          :for={{opt_label, opt_value} <- field.options}
          value={opt_value}
          selected={opt_value == to_string(field.default)}
        >
          {opt_label}
        </option>
      </select>
      <input
        :if={field.type == :integer}
        type="number"
        name={Atom.to_string(field.name)}
        value={field.default}
        placeholder={field.placeholder}
        min={field[:min]}
        class="w-full rounded-lg border-gray-300 dark:border-gray-600 dark:bg-gray-800 dark:text-white"
      />
      <input
        :if={field.type == :string}
        type="text"
        name={Atom.to_string(field.name)}
        value={field[:default]}
        placeholder={field[:placeholder]}
        required={field[:required]}
        class="w-full rounded-lg border-gray-300 dark:border-gray-600 dark:bg-gray-800 dark:text-white"
      />
    </div>
    """
  end

  def mount(%{"id" => "new"}, _session, socket) do
    changeset = TriggerConfig.changeset(%{})
    {source_type, source_fields} = default_type_and_fields(TriggerSources)
    {target_type, target_fields} = default_type_and_fields(TriggerTargets)

    {:ok,
     assign(socket,
       trigger_config: %TriggerConfig{},
       form: to_form(changeset),
       selected_source_type: source_type,
       source_fields: source_fields,
       selected_target_type: target_type,
       target_fields: target_fields
     )}
  end

  def mount(%{"id" => id}, _session, socket) do
    trigger_config = Triggers.get_trigger_config!(String.to_integer(id))
    changeset = TriggerConfig.changeset(trigger_config, %{})
    {source_type, source_fields} = default_type_and_fields(TriggerSources)
    {target_type, target_fields} = default_type_and_fields(TriggerTargets)

    {:ok,
     assign(socket,
       trigger_config: trigger_config,
       form: to_form(changeset),
       selected_source_type: source_type,
       source_fields: source_fields,
       selected_target_type: target_type,
       target_fields: target_fields
     )}
  end

  def handle_event("validate", %{"trigger_config" => params}, socket) do
    changeset =
      TriggerConfig.changeset(socket.assigns.trigger_config, params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"trigger_config" => params}, socket) do
    user = socket.assigns.current_user
    trigger_config = socket.assigns.trigger_config
    action = if trigger_config.id, do: :update, else: :create

    case authorize(user, :trigger, action) do
      :ok ->
        if trigger_config.id,
          do: do_update(socket, trigger_config, params),
          else: do_create(socket, params)

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You are not authorized to perform this action")}
    end
  end

  def handle_event("source-type-changed", %{"source_type" => source_type}, socket) do
    fields = fields_for_type(TriggerSources, source_type, :config_fields)
    {:noreply, assign(socket, selected_source_type: source_type, source_fields: fields)}
  end

  def handle_event("source-type-changed", _params, socket), do: {:noreply, socket}

  def handle_event("target-type-changed", %{"target_type" => target_type}, socket) do
    fields = fields_for_type(TriggerTargets, target_type, :config_fields)
    {:noreply, assign(socket, selected_target_type: target_type, target_fields: fields)}
  end

  def handle_event("target-type-changed", _params, socket), do: {:noreply, socket}

  def handle_event("add-source", params, socket) do
    user = socket.assigns.current_user

    case authorize(user, :trigger, :update) do
      :ok ->
        trigger_config = socket.assigns.trigger_config
        source_type = params["source_type"]
        fields = fields_for_type(TriggerSources, source_type, :config_fields)

        config =
          Enum.into(fields, %{}, fn field ->
            key = Atom.to_string(field.name)
            {key, params[key]}
          end)

        source_params = %{
          trigger_config_id: trigger_config.id,
          source_type: source_type,
          config: config
        }

        case Triggers.create_source_config(source_params) do
          {:ok, _} ->
            trigger_config = Triggers.get_trigger_config!(trigger_config.id)
            {:noreply, assign(socket, trigger_config: trigger_config)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Could not add source")}
        end

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You are not authorized to perform this action")}
    end
  end

  def handle_event("delete-source", %{"source_id" => source_id}, socket) do
    user = socket.assigns.current_user

    case authorize(user, :trigger, :update) do
      :ok ->
        source = ExNVR.Repo.get!(TriggerSourceConfig, source_id)

        case Triggers.delete_source_config(source) do
          {:ok, _} ->
            trigger_config = Triggers.get_trigger_config!(socket.assigns.trigger_config.id)
            {:noreply, assign(socket, trigger_config: trigger_config)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not delete source")}
        end

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You are not authorized to perform this action")}
    end
  end

  def handle_event("add-target", params, socket) do
    user = socket.assigns.current_user

    case authorize(user, :trigger, :update) do
      :ok ->
        trigger_config = socket.assigns.trigger_config
        target_type = params["target_type"]
        fields = fields_for_type(TriggerTargets, target_type, :config_fields)

        config =
          Enum.into(fields, %{}, fn field ->
            key = Atom.to_string(field.name)
            {key, params[key]}
          end)

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

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You are not authorized to perform this action")}
    end
  end

  def handle_event("delete-target", %{"target_id" => target_id}, socket) do
    user = socket.assigns.current_user

    case authorize(user, :trigger, :update) do
      :ok ->
        target = ExNVR.Repo.get!(TriggerTargetConfig, target_id)

        case Triggers.delete_target_config(target) do
          {:ok, _} ->
            trigger_config = Triggers.get_trigger_config!(socket.assigns.trigger_config.id)
            {:noreply, assign(socket, trigger_config: trigger_config)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not delete target")}
        end

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You are not authorized to perform this action")}
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

  defp default_type_and_fields(registry) do
    case registry.type_options() do
      [{_label, type} | _] -> {type, fields_for_type(registry, type, :config_fields)}
      [] -> {nil, []}
    end
  end

  defp fields_for_type(registry, type, callback) do
    case registry.module_for(type) do
      nil -> []
      module -> apply(module, callback, [])
    end
  end

  defp source_label(type) do
    case TriggerSources.module_for(type) do
      nil -> type
      module -> module.label()
    end
  end

  defp target_label(type) do
    case TriggerTargets.module_for(type) do
      nil -> type
      module -> module.label()
    end
  end

  defp format_key(key) when is_binary(key) do
    key |> String.replace("_", " ") |> String.capitalize()
  end

  defp format_value(val) when is_list(val), do: Enum.join(val, ", ")
  defp format_value(val), do: to_string(val)
end
