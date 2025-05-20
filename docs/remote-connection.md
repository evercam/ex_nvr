# Remote Connection

`ExNVR.RemoteConnection` maintains a WebSocket connection to a remote server for receiving commands and sending health data.

## Startup

```elixir
def start_link(options) do
  Slipstream.start_link(__MODULE__, options, name: __MODULE__)
end

@impl Slipstream
def init(options) do
  opts = [uri: options[:uri]]

  opts
  |> connect!()
  |> assign(:message_handler, options[:message_handler])
  |> then(&{:ok, &1})
end
```

Upon connection the process joins the `"ex_nvr"` topic and schedules periodic system status reports:

```elixir
def handle_connect(socket) do
  Logger.info("Connected to remote server")
  {:ok, join(socket, @topic)}
end

def handle_join(@topic, _response, socket) do
  Logger.info("Joined topic: #{@topic}")
  {:ok, ref} = :timer.send_interval(to_timeout(minute: 1), :send_system_status)
  {:ok, assign(socket, timer_ref: ref)}
end
```

## Messaging

Incoming `command` messages trigger execution of system commands:

```elixir
def handle_message(@topic, "command", %{"command" => cmd, "args" => args} = params, socket) do
  run_command(cmd, args, params["ref"])
  {:noreply, socket}
end
```

Other events are forwarded to an optional message handler module:

```elixir
def handle_message(@topic, event, msg, socket) do
  if handler = socket.assigns[:message_handler] do
    handler.handle_message(event, msg)
  else
    Logger.warning(
      "No handler found for event #{event} on topic #{@topic} with message #{inspect(msg)}"
    )
  end

  {:noreply, socket}
end
```

Every minute the connection pushes the current system status:

```elixir
def handle_info(:send_system_status, socket) do
  Logger.info("Sending system status")
  push(socket, @topic, "health", ExNVR.SystemStatus.get_all(), @send_timeout)
  {:noreply, socket}
end
```

If the connection drops or the topic closes the process attempts to reconnect and rejoin.
