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
            <div class="popup-container relative">
              <span title="Preview recording">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 24 24"
                  fill="currentColor"
                  class="w-6 h-6 mr-2 cursor-pointer thumbnail"
                  phx-hook="VideoPopup"
                  phx-value-url={"/api/devices/#{recording.device_id}/recordings/#{recording.filename}/blob"}
                  id={"thumbnail-#{recording.id}"}
                  alt="Thumbnail"
                >
                  <path d="M12 15a3 3 0 100-6 3 3 0 000 6z" />
                  <path
                    fill-rule="evenodd"
                    d="M1.323 11.447C2.811 6.976 7.028 3.75 12.001 3.75c4.97 0 9.185 3.223 10.675 7.69.12.362.12.752 0 1.113-1.487 4.471-5.705 7.697-10.677 7.697-4.97 0-9.186-3.223-10.675-7.69a1.762 1.762 0 010-1.113zM17.25 12a5.25 5.25 0 11-10.5 0 5.25 5.25 0 0110.5 0z"
                    clip-rule="evenodd"
                  />
                </svg>
              </span>
            </div>
            <div class="flex justify-end">
              <.link
                href={~p"/api/devices/#{recording.device_id}/recordings/#{recording.filename}/blob"}
                class="inline-flex items-center text-gray-900 rounded-lg"
                id={"recording-#{recording.id}-link"}
              >
                <span title="Download recording">
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
                </span>
              </.link>
            </div>
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
          <%= if @meta.total_pages == 0 do %>
            <li>
              <a
                href="#"
                phx-click="nav"
                phx-value-page={0}
                class={
                  [
                    "flex items-center justify-center px-3 h-8 leading-tight border dark:border-gray-700"
                  ] ++
                    if @meta.current_page == 0,
                      do: [
                        "z-10 pointer-events-none text-blue-600 bg-blue-50 border-blue-300 hover:bg-blue-100 hover:text-blue-700 dark:bg-gray-700 dark:text-white"
                      ],
                      else: [
                        "text-gray-500 bg-white border-gray-300 hover:bg-gray-100 hover:text-gray-700 dark:bg-gray-800 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-white"
                      ]
                }
              >
                <%= 0 %>
              </a>
            </li>
          <% end %>
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
          <% end %>
          <%= if @meta.total_pages in Enum.to_list(1..6) do %>
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
    <!-- Popup container -->
    <div
      class={
        [
          "popup-container fixed top-0 left-0 w-full h-full bg-black bg-opacity-75 flex justify-center items-center"
        ] ++ if not @popup_open, do: ["hidden"], else: [""]
      }
      id="popup-container"
    >
      <button class="popup-close absolute top-4 right-4 text-white" phx-click="close-popup">×</button>
      <video autoplay class="w-full h-auto max-w-full max-h-[80%]">
        <source src="" type="video/mp4" phx-value-video-url />
        Your browser does not support the video tag.
      </video>
    </div>
    """
  end

  def filter_form(%{meta: meta, devices: devices} = assigns) do
    assigns = assign(assigns, form: Phoenix.Component.to_form(meta), meta: meta, devices: devices)

    ~H"""
    <div class="flex justify-between">
      <.form for={@form} id={@id} phx-change="update-filter" class="flex items-baseline space-x-4">
        <Flop.Phoenix.filter_fields
          :let={f}
          form={@form}
          fields={[
            device_id: [
              op: :==,
              type: "select",
              options: Enum.map(@devices, &{&1.name, &1.id}),
              label: "Device"
            ],
            start_date: [op: :>=, type: "datetime-local", label: "Start Date"],
            end_date: [op: :<=, type: "datetime-local", label: "End Date"]
          ]}
        >
          <div>
            <.input
              class="border rounded p-1"
              field={f.field}
              type={f.type}
              phx-debounce="500"
              {f.rest}
            />
          </div>
        </Flop.Phoenix.filter_fields>
      </.form>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, devices: Devices.list(), popup_open: false)}
  end

  def handle_event("close-popup", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/recordings")}
  end

  def handle_event("update-filter", params, socket) do
    params = Map.delete(params, "_target")
    {:noreply, push_patch(socket, to: ~p"/recordings?#{params}")}
  end

  def handle_event("nav", %{"page" => page}, socket) do
    flop = Flop.set_page(socket.assigns.meta.flop, page)

    case Recordings.list(flop) do
      {:ok, {recordings, meta}} ->
        {:noreply, assign(socket, recordings: recordings, meta: meta)}

      {:error, _meta} ->
        {:noreply, push_navigate(socket, to: ~p"/recordings")}
    end
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
