defmodule ExNVRWeb.RecordingListLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  alias ExNVRWeb.Router.Helpers, as: Routes
  alias ExNVR.Recordings
  alias ExNVRWeb.RecordingListLive

  def render(assigns) do
    ~H"""
    <div class="grow">
      <.table id="recordings" rows={@recordings}>
        <:col :let={recording} label="Id"><%= recording.id %></:col>
        <:col :let={recording} label="Device"><%= recording.device.name %></:col>
        <:col :let={recording} label="Start-date"><%= recording.start_date %></:col>
        <:col :let={recording} label="End-date"><%= recording.end_date %></:col>
        <:action :let={recording}>
          <.button
            id={"dropdownMenuIconButton_#{recording.id}"}
            data-dropdown-toggle={"dropdownDots_#{recording.id}"}
            class="text-sm ml-3 hover:bg-gray-100 dark:bg-gray-800"
          >
            <svg
              class="w-5 h-5"
              aria-hidden="true"
              fill="currentColor"
              viewBox="0 0 20 20"
              xmlns="http://www.w3.org/2000/svg"
            >
              <path d="M10 6a2 2 0 110-4 2 2 0 010 4zM10 12a2 2 0 110-4 2 2 0 010 4zM10 18a2 2 0 110-4 2 2 0 010 4z" />
            </svg>
            <div
              id={"dropdownDots_#{recording.id}"}
              class="z-10 hidden text-left bg-white divide-y divide-gray-100 rounded-lg shadow w-44 dark:bg-gray-700 dark:divide-gray-600"
            >
              <ul
                class="py-2 text-sm text-gray-700 dark:text-gray-200"
                aria-labelledby={"dropdownMenuIconButton_#{recording.id}"}
              >
                <li>
                  <.link
                    phx-click="download-recording"
                    phx-value-device={recording.id}
                    class="block px-4 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
                  >
                    Download
                  </.link>
                </li>
              </ul>
            </div>
          </.button>
        </:action>
      </.table>
      <nav class="border-t border-gray-200">
        <ul class="flex my-2">
          <li>
            <a
            class={previous_page(@page_number)}
            href="#"
            phx-click="nav"
            phx-value-page={@page_number - 1}
            >
            Previous
            </a>
          </li>
          <%= for idx <-  Enum.to_list(1..@total_pages) do %>
          <li>
            <a
              class={current_page(@page_number, idx)}
              href="#"
              phx-click="nav"
              phx-value-page={idx}
              >
              <%= idx %>
            </a>
          </li>
          <% end %>
          <li>
            <a
              class={next_page(@page_number, @total_pages)}
              href="#"
              phx-click="nav"
              phx-value-page={@page_number + 1}
            >
              Next
            </a>
          </li>
        </ul>
      </nav>
    </div>
    """
  end

  def mount(_session, socket) do
    {:ok, assign(socket, conn: socket)}
  end

  def handle_event("nav", %{"page" => page}, socket) do
    {:noreply, push_redirect(socket, to: Routes.recording_list_path(socket, :list, page: page))}
  end

  def handle_params(%{"page" => page}, _, socket) do
    assigns = get_and_assign_page(page)
    {:noreply, assign(socket, assigns)}
  end

  def handle_params(_, _, socket) do
    assigns = get_and_assign_page(nil)
    {:noreply, assign(socket, assigns)}
  end

  defp get_and_assign_page(page_number) do
    %{
      entries: entries,
      page_number: page_number,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages
    } = Recordings.paginate_recordings(page: page_number)

    [
      recordings: entries,
      page_number: page_number,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages
    ]
  end

  defp next_page(page_number, total_pages) do
    if page_number >= total_pages, do: "px-2 py-2 pointer-events-none", else: "px-2 py-2 text-gray-600"
  end

  defp previous_page(page_number) do
    if page_number <= 1, do: "px-2 py-2 pointer-events-none", else: "px-2 py-2 text-gray-600"
  end

  defp current_page(page_number, idx) do
    if page_number == idx, do: "px-2 py-2 pointer-events-none", else: "px-2 py-2 text-gray-600"
  end
end
