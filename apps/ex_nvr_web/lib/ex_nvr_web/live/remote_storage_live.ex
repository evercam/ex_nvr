defmodule ExNVRWeb.RemoteStorageLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  alias ExNVR.RemoteStorage
  alias ExNVR.RemoteStorages

  def render(assigns) do
    ~H"""
    <div class="grow max-w-2xl">
      <div class="px-6 lg:px-8 bg-gray-300 dark:bg-gray-800">
        <h3
          :if={@remote_storage.id == nil}
          class="mb-4 text-xl text-center font-medium text-gray-900 dark:text-white"
        >
          Create a new remote storage
        </h3>
        <h3
          :if={@remote_storage.id != nil}
          class="mb-4 text-xl text-center font-medium text-gray-900 dark:text-white"
        >
          Update a remote storage
        </h3>
        <.simple_form
          id="remote_storage_form"
          for={@remote_storage_form}
          class="space-y-6"
          phx-submit="save_remote_storage"
        >
          <.input
            field={@remote_storage_form[:name]}
            id="remote_storage_name"
            type="text"
            label="Name"
            disabled={@remote_storage.id != nil}
            required
          />
          <.input
            field={@remote_storage_form[:type]}
            id="remote_storage_type"
            type="select"
            options={["s3", "http"]}
            label="Type"
            phx-change="update_type"
            disabled={@remote_storage.id != nil}
          />
          <.input field={@remote_storage_form[:url]} id="remote_storage_url" type="text" label="Url" />

          <p class="text-xl font-medium mb-4 text-gray-800 dark:text-white">
            Storage Config
          </p>

          <.inputs_for
            :let={http_config}
            :if={@remote_storage_type == "http"}
            field={@remote_storage_form[:http_config]}
          >
            <.input
              field={http_config[:username]}
              id="remote_storage_username"
              type="text"
              label="Username"
            />
            <.input
              field={http_config[:password]}
              id="remote_storage_password"
              type="password"
              label="Password"
            />
            <.input field={http_config[:token]} id="remote_storage_token" type="text" label="Token" />
          </.inputs_for>
          <.inputs_for
            :let={s3_config}
            :if={@remote_storage_type == "s3"}
            field={@remote_storage_form[:s3_config]}
          >
            <.input
              field={s3_config[:region]}
              id="remote_storage_region"
              type="text"
              label="Region"
              placeholder="default to us-east-1"
            />
            <.input
              field={s3_config[:bucket]}
              id="remote_storage_bucket"
              type="text"
              label="Bucket"
              required
            />
            <.input
              field={s3_config[:access_key_id]}
              id="remote_storage_access_key_id"
              type="text"
              label="Access key"
              required
            />
            <.input
              field={s3_config[:secret_access_key]}
              id="remote_storage_secret_access_key"
              type="password"
              label="Secret access key"
              required
            />
          </.inputs_for>
          <:actions>
            <.button :if={is_nil(@remote_storage.id)} class="w-full" phx-disable-with="Creating...">
              Create
            </.button>

            <.button :if={@remote_storage.id} class="w-full" phx-disable-with="Updating...">
              Update
            </.button>
          </:actions>
        </.simple_form>
      </div>
    </div>
    """
  end

  def mount(%{"id" => "new"}, _session, socket) do
    remote_storage = %RemoteStorage{type: :s3}
    changeset = RemoteStorages.change_remote_storage_creation(remote_storage)

    {:ok,
     assign(socket,
       remote_storage: remote_storage,
       remote_storage_form: to_form(changeset),
       remote_storage_type: "s3"
     )}
  end

  def mount(%{"id" => remote_storage_id}, _session, socket) do
    remote_storage = RemoteStorages.get!(remote_storage_id)
    changeset = RemoteStorages.change_remote_storage_update(remote_storage)

    {:ok,
     assign(socket,
       remote_storage: remote_storage,
       remote_storage_form: to_form(changeset),
       remote_storage_type: Atom.to_string(remote_storage.type)
     )}
  end

  def handle_event("update_type", %{"remote_storage" => %{"type" => type}}, socket) do
    {:noreply, assign(socket, remote_storage_type: type)}
  end

  def handle_event("save_remote_storage", %{"remote_storage" => remote_storage_params}, socket) do
    remote_storage = socket.assigns.remote_storage

    if remote_storage.id,
      do: do_update_remote_storage(socket, remote_storage, remote_storage_params),
      else: do_save_remote_storage(socket, remote_storage_params)
  end

  defp do_update_remote_storage(socket, remote_storage, remote_storage_params) do
    case RemoteStorages.update(remote_storage, remote_storage_params) do
      {:ok, _remote_storage} ->
        info = "Remote storage updated successfully"

        socket
        |> put_flash(:info, info)
        |> redirect(to: ~p"/remote-storages")
        |> then(&{:noreply, &1})

      {:error, changeset} ->
        {:noreply, assign(socket, remote_storage_form: to_form(changeset))}
    end
  end

  defp do_save_remote_storage(socket, remote_storage_params) do
    case RemoteStorages.create(remote_storage_params) do
      {:ok, _remote_storage} ->
        info = "Remote storage created successfully"

        socket
        |> put_flash(:info, info)
        |> redirect(to: ~p"/remote-storages")
        |> then(&{:noreply, &1})

      {:error, changeset} ->
        {:noreply, assign(socket, remote_storage_form: to_form(changeset))}
    end
  end
end
