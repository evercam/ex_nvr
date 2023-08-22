defmodule ExNVRWeb.RecordingListLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  alias ExNVRWeb.Router.Helpers, as: Routes
  alias ExNVR.{Recordings, Devices}

  def render(assigns) do
    ~H"""
    <div class="grow">
      <.filter_form meta={@meta} devices={@devices} id="recording-filter-form" />

      <Flop.Phoenix.table
        id="recordings"
        opts={ExNVRWeb.FlopConfig.table_opts()}
        items={@recordings}
        meta={@meta}
        path={~p"/recordings"}
      >
        <:col :let={recording} label="Id" field={:id}><%= recording.id %></:col>
        <:col :let={recording} label="Device" field={:device_name}><%= recording.device_name %></:col>
        <:col :let={recording} label="Start-date" field={:start_date}>
          <%= format_date(recording.start_date, recording.timezone) %>
        </:col>
        <:col :let={recording} label="End-date" field={:end_date}>
          <%= format_date(recording.end_date, recording.timezone) %>
        </:col>
        <:action :let={recording}>
          <div class="flex justify-end">
            <.link
              href={~p"/api/devices/#{recording.device_id}/recordings/#{recording.filename}/blob"}
              class="inline-flex items-center text-gray-900 rounded-lg"
              id={"recording-#{recording.id}-link"}
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="currentColor"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="white"
                class="w-6 h-6"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5M16.5 12L12 16.5m0 0L7.5 12m4.5 4.5V3"
                />
              </svg>
            </.link>
          </div>
        </:action>
      </Flop.Phoenix.table>

      <nav aria-label="Page navigation" class="flex justify-end mt-4">
        <ul class="flex items-center -space-x-px h-8 text-sm">
          <li>
            <a
              href="#"
              phx-click="nav"
              phx-value-page={@meta.previous_page}
              class={
                [
                  "flex items-center justify-center px-3 h-8 ml-0 leading-tight bg-white border border-gray-300 rounded-l-lg"
                ] ++
                  if not @meta.has_previous_page?,
                    do: ["pointer-events-none text-gray-300"],
                    else: [
                      "text-gray-500 hover:bg-gray-100 hover:text-gray-700 dark:bg-gray-800 dark:border-gray-700 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-white"
                    ]
              }
            >
              <span class="sr-only">Previous</span>
              <svg
                class="w-2.5 h-2.5"
                aria-hidden="true"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 6 10"
              >
                <path
                  stroke="currentColor"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M5 1 1 5l4 4"
                />
              </svg>
            </a>
          </li>
          <%= if @meta.total_pages > 6 do %>
            <%= for page <- [1,2] do %>
              <li>
                <a
                  href="#"
                  phx-click="nav"
                  phx-value-page={page}
                  class={
                    [
                      "flex items-center justify-center px-3 h-8 leading-tight border dark:border-gray-700"
                    ] ++
                      if @meta.current_page == page,
                        do: [
                          "z-10 pointer-events-none text-blue-600 bg-blue-50 border-blue-300 hover:bg-blue-100 hover:text-blue-700 dark:bg-gray-700 dark:text-white"
                        ],
                        else: [
                          "text-gray-500 bg-white border-gray-300 hover:bg-gray-100 hover:text-gray-700 dark:bg-gray-800 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-white"
                        ]
                  }
                >
                  <%= page %>
                </a>
              </li>
            <% end %>
            <%= if @meta.current_page > 4 do %>
              <li>
                <span class="flex items-center justify-center px-3 h-8 leading-tight text-gray-500">
                  ...
                </span>
              </li>
            <% end %>
            <%= for idx <-  Enum.to_list(3..@meta.total_pages-2) do %>
              <%= if abs(@meta.current_page - idx) <= 1 do %>
                <li>
                  <a
                    href="#"
                    phx-click="nav"
                    phx-value-page={idx}
                    class={
                      [
                        "flex items-center justify-center px-3 h-8 leading-tight border dark:border-gray-700"
                      ] ++
                        if @meta.current_page == idx,
                          do: [
                            "z-10 pointer-events-none text-blue-600 bg-blue-50 border-blue-300 hover:bg-blue-100 hover:text-blue-700 dark:bg-gray-700 dark:text-white"
                          ],
                          else: [
                            "text-gray-500 bg-white border-gray-300 hover:bg-gray-100 hover:text-gray-700 dark:bg-gray-800 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-white"
                          ]
                    }
                  >
                    <%= idx %>
                  </a>
                </li>
              <% end %>
            <% end %>
            <%= if @meta.current_page < @meta.total_pages - 3 do %>
              <li>
                <span class="flex items-center justify-center px-3 h-8 leading-tight text-gray-500">
                  ...
                </span>
              </li>
            <% end %>
            <%= for page <- [@meta.total_pages-1, @meta.total_pages] do %>
              <li>
                <a
                  href="#"
                  phx-click="nav"
                  phx-value-page={page}
                  class={
                    [
                      "flex items-center justify-center px-3 h-8 leading-tight border dark:border-gray-700"
                    ] ++
                      if @meta.current_page == page,
                        do: [
                          "z-10 pointer-events-none text-blue-600 bg-blue-50 border-blue-300 hover:bg-blue-100 hover:text-blue-700 dark:bg-gray-700 dark:text-white"
                        ],
                        else: [
                          "text-gray-500 bg-white border-gray-300 hover:bg-gray-100 hover:text-gray-700 dark:bg-gray-800 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-white"
                        ]
                  }
                >
                  <%= page %>
                </a>
              </li>
            <% end %>
          <% else %>
            <%= for idx <-  Enum.to_list(1..@meta.total_pages) do %>
              <li>
                <a
                  href="#"
                  phx-click="nav"
                  phx-value-page={idx}
                  class={
                    [
                      "flex items-center justify-center px-3 h-8 leading-tight border dark:border-gray-700"
                    ] ++
                      if @meta.current_page == idx,
                        do: [
                          "z-10 pointer-events-none text-blue-600 bg-blue-50 border-blue-300 hover:bg-blue-100 hover:text-blue-700 dark:bg-gray-700 dark:text-white"
                        ],
                        else: [
                          "text-gray-500 bg-white border-gray-300 hover:bg-gray-100 hover:text-gray-700 dark:bg-gray-800 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-white"
                        ]
                  }
                >
                  <%= idx %>
                </a>
              </li>
            <% end %>
          <% end %>
          <li>
            <a
              href="#"
              phx-click="nav"
              phx-value-page={@meta.next_page}
              class={
                [
                  "flex items-center justify-center px-3 h-8 leading-tight border border-gray-300 bg-white rounded-r-lg"
                ] ++
                  if not @meta.has_next_page?,
                    do: ["pointer-events-none text-gray-300"],
                    else: [
                      "text-gray-500 hover:bg-gray-100 hover:text-gray-700 dark:bg-gray-800 dark:border-gray-700 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-white"
                    ]
              }
            >
              <span class="sr-only">Next</span>
              <svg
                class="w-2.5 h-2.5"
                aria-hidden="true"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 6 10"
              >
                <path
                  stroke="currentColor"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="m1 9 4-4-4-4"
                />
              </svg>
            </a>
          </li>
        </ul>
      </nav>
    </div>
    """
  end

  def filter_form(%{meta: meta, devices: devices} = assigns) do
    assigns = assign(assigns, form: Phoenix.Component.to_form(meta), meta: meta, devices: devices)

    ~H"""
    <div class="flex space-x-4">
      <.form
        for={@form}
        id={@id}
        phx-submit="update-filter"
        phx-change="update-filter"
        class="flex items-center space-x-4"
      >
        <Flop.Phoenix.filter_fields
          :let={f}
          form={@form}
          fields={[
            device_name: [
              op: :like_and,
              type: "select",
              options: Enum.map(@devices, & &1.name),
              label: "Device"
            ],
            start_date: [op: :>=, type: "datetime-local", label: "Start Date"],
            end_date: [op: :<=, type: "datetime-local", label: "End Date"]
          ]}
        >
          <.input field={f.field} type={f.type} phx-debounce="500" {f.rest} />
        </Flop.Phoenix.filter_fields>

        <div class="flex items-center">
          <button
            class="button bg-blue-500 hover:bg-blue-600 text-white font-bold py-2 px-4 rounded"
            type="submit"
          >
            Filter
          </button>
        </div>
      </.form>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, devices: Devices.list())}
  end

  @spec handle_event(<<_::24, _::_*80>>, map, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("update-filter", params, socket) do
    params = Map.delete(params, "_target")
    {:noreply, push_patch(socket, to: ~p"/recordings?#{params}")}
  end

  def handle_event("nav", %{"page" => page}, socket) do
    {:noreply, push_patch(socket, to: Routes.recording_list_path(socket, :list, page: page))}
  end

  def handle_params(params, _uri, socket) do
    case Recordings.list(params) do
      {:ok, {recordings, meta}} ->
        {:noreply, assign(socket, %{recordings: recordings, meta: meta, form: nil})}

      {:error, _meta} ->
        {:noreply, push_navigate(socket, to: ~p"/recordings")}
    end
  end

  defp format_date(date, timezone) do
    date
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime("%b %d, %Y %H:%M:%S")
  end
end
