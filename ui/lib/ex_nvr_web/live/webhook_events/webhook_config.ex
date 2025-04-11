defmodule ExNVRWeb.WebhookEventsLive.WebhookConfig do
  use ExNVRWeb, :live_component

  alias ExNVR.Accounts

  @impl true
  def render(assigns) do
    ~H'''
    <div id="webhook-config">
      <div>
        <.header>
          Token
          <:subtitle>
            Use the Webhook token to authenticate incoming requests. <br />
            It can be used either as a Bearer token sent in the request headers, or as a query parameter.
          </:subtitle>
        </.header>

        <%= if @token_data do %>
          <div class="relative w-[42rem] mt-2">
            <div class="h-[4rem]">
              <div class="hidden" id="full-token">{token_str(assigns, true)}</div>
              <.code_snippet
                id="wh-token"
                lang="txt"
                copy_target="#full-token"
                code={token_str(assigns, false, 44)}
              >
                <:actions>
                  <button
                    type="button"
                    phx-click="toggle_token_visibility"
                    phx-target={@myself}
                    class="bg-gray-700 hover:bg-slate-600 text-white font-bold py-2 px-3 rounded-md"
                    title={if @show_token, do: "Hide token", else: "Show token"}
                  >
                    <%= if @show_token do %>
                      <.icon name="hero-eye-slash" />
                    <% else %>
                      <.icon name="hero-eye" />
                    <% end %>
                  </button>
                </:actions>
              </.code_snippet>
            </div>

            <div class="flex items-center justify-between mt-3">
              <p class="text-sm leading-6 text-zinc-600 dark:text-white">
                Created: <time>{format_datetime(@token_data.created_at)}</time>
              </p>
              <.button
                phx-click="delete_token"
                phx-target={@myself}
                data-confirm="Are you sure you want to delete this token? This action cannot be undone."
                class="mr-0"
              >
                <.icon name="hero-trash-solid" class="mr-1" /> Delete token
              </.button>
            </div>
          </div>
        <% else %>
          <div class="relative w-[42rem] mt-2">
            <p class="text-sm leading-6 text-zinc-600 dark:text-white mb-2">
              You don't have a webhook token yet.
            </p>
            <.button phx-click="generate_token" phx-target={@myself} class="pl-3 pr-3">
              <.icon name="hero-plus-solid" class="mr-1" /> Generate Token
            </.button>
          </div>
        <% end %>
      </div>

      <%= if @token_data do %>
        <div>
          <.header>
            Endpoint
          </.header>

          <div class="relative">
            <.simple_form
              for={%{}}
              id="endpoint-form"
              phx-change="update_endpoint"
              phx-target={@myself}
            >
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <.input
                    type="select"
                    name="device_id"
                    id="device_id"
                    value={@device_id}
                    options={@devices}
                    label="Device"
                    prompt="Select a device"
                  />
                </div>

                <div>
                  <.input
                    type="text"
                    name="event_type"
                    id="event_type"
                    value={@event_type}
                    placeholder="e.g. lpr"
                    label="Event Type"
                  />
                </div>
              </div>
            </.simple_form>

            <div class="mt-4">
              <div class="relative w-full h-[4rem]">
                <div class="hidden" id="full-endpoint">{endpoint_url(assigns)}</div>
                <.code_snippet
                  id="endpoint-url"
                  lang="txt"
                  copy_target="#full-endpoint"
                  code={
                    if @token_data do
                      endpoint_url(assigns)
                    else
                      "No token available. Generate a token first."
                    end
                  }
                />
              </div>
            </div>
          </div>
        </div>

        <div class="mt-4">
          <.header>
            Example
            <:subtitle>
              Here's an example of using cURL to send an event to the webhook endpoint
            </:subtitle>
          </.header>

          <div class="mt-2">
            <div class="relative w-full">
              <div class="hidden" id="full-curl-example">{curl_example(assigns, true)}</div>
              <.code_snippet
                id="curl-example"
                lang="bash"
                copy_target="#full-curl-example"
                code={curl_example(assigns)}
              />
            </div>
          </div>
        </div>
      <% end %>
    </div>
    '''
  end

  @impl true
  def update(assigns, socket) do
    token_data = Accounts.get_webhook_token(assigns.current_user)

    device_id =
      case assigns.devices do
        [{_, id} | _] -> id
        _ -> nil
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:show_token, fn -> false end)
     |> assign_new(:token_data, fn -> token_data end)
     |> assign_new(:device_id, fn -> device_id end)
     |> assign_new(:event_type, fn -> "my_event_type" end)}
  end

  @impl true
  def handle_event("generate_token", _params, socket) do
    Accounts.generate_webhook_token(socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(:token_data, Accounts.get_webhook_token(socket.assigns.current_user))
     |> put_flash(:info, "Webhook token created successfully")}
  end

  @impl true
  def handle_event("delete_token", _params, socket) do
    Accounts.delete_webhook_token(socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(:token_data, nil)
     |> put_flash(:info, "Webhook token deleted successfully")}
  end

  @impl true
  def handle_event("toggle_token_visibility", _params, socket) do
    {:noreply, assign(socket, :show_token, !socket.assigns.show_token)}
  end

  @impl true
  def handle_event("update_endpoint", params, socket) do
    {:noreply,
     socket
     |> assign(:device_id, Map.get(params, "device_id"))
     |> assign(:event_type, Map.get(params, "event_type"))}
  end

  defp token_str(
         %{show_token: show_token, token_data: token_data},
         copyable,
         length \\ 10
       ) do
    case show_token || copyable do
      true -> token_data.token
      _ -> String.duplicate("•", length)
    end
  end

  defp endpoint_url(assigns, copyable \\ false) do
    base_url = "#{ExNVRWeb.Endpoint.url()}/api/devices/"

    device = assigns.device_id || ":device_id"
    event = assigns.event_type || ":event_type"
    token = token_str(assigns, copyable)

    "#{base_url}#{device}/events?event_type=#{event}&token=#{token}"
  end

  defp curl_example(assigns, copyable \\ false) do
    """
    curl -X POST \\
      "#{endpoint_url(assigns, copyable)}" \\
      -H "Content-Type: application/json" \\
      -d '{
        "timestamp": "#{DateTime.utc_now() |> DateTime.to_iso8601()}",
        "description": "Example event payload"
      }'
    """
  end

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%B %d, %Y at %H:%M")
  end
end
