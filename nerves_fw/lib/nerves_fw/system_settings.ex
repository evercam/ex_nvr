defmodule ExNVR.Nerves.SystemSettings do
  @moduledoc """
  Module describing system settings.

  It's stored as a json file in the system.
  """

  use GenServer

  require Logger

  @default_path "/data/settings.json"
  @system_settings_topic "system_settings"

  defmodule State do
    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false
    @derive JSON.Encoder
    embedded_schema do
      embeds_one :power_schedule, PowerSchedule, primary_key: false, on_replace: :update do
        @derive JSON.Encoder
        field :schedule, :map
        field :timezone, :string, default: "UTC"

        field :action, Ecto.Enum,
          values: ~w(power_off stop_recording nothing)a,
          default: :power_off
      end

      embeds_one :router, Router, primary_key: false, on_replace: :update do
        @derive JSON.Encoder
        field :username, :string
        field :password, :string
      end

      embeds_one :ups, UPS, primary_key: false, on_replace: :update do
        @derive JSON.Encoder
        field :enabled, :boolean, default: false
        field :ac_pin, :string, default: "GPIO23"
        field :battery_pin, :string, default: "GPIO16"

        field :ac_failure_action, Ecto.Enum,
          values: ~w(power_off stop_recording nothing)a,
          default: :nothing

        field :low_battery_action, Ecto.Enum,
          values: ~w(power_off stop_recording nothing)a,
          default: :stop_recording
      end
    end

    def to_struct(settings \\ %__MODULE__{}, params) do
      settings
      |> changeset(params)
      |> apply_action(:validate)
    end

    def changeset(settings \\ %__MODULE__{}, params) do
      settings
      |> cast(params, [])
      |> cast_embed(:power_schedule, with: &power_schedule_changeset/2)
      |> cast_embed(:router, with: &router_changeset/2)
      |> cast_embed(:ups, with: &ups_changeset/2)
    end

    defp power_schedule_changeset(changeset, params) do
      cast(changeset, params, [:schedule, :timezone, :action])
    end

    defp router_changeset(changeset, params) do
      cast(changeset, params, [:username, :password])
    end

    defp ups_changeset(changeset, params) do
      cast(changeset, params, [
        :enabled,
        :ac_pin,
        :battery_pin,
        :ac_failure_action,
        :low_battery_action
      ])
    end
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  @spec get_settings() :: State.t()
  @spec get_settings(pid()) :: State.t()
  def get_settings(pid \\ __MODULE__) do
    GenServer.call(pid, :get_settings)
  end

  def update_router_settings(pid \\ __MODULE__, params) do
    GenServer.call(pid, {:update_router_settings, params})
  end

  def update_power_schedule_settings(pid \\ __MODULE__, params) do
    GenServer.call(pid, {:update_power_schedule_settings, params})
  end

  def update_ups_settings(pid \\ __MODULE__, params) do
    GenServer.call(pid, {:update_ups_settings, params})
  end

  def subscribe() do
    Phoenix.PubSub.subscribe(ExNVR.Nerves.PubSub, @system_settings_topic)
  end

  @impl true
  def init(_opts) do
    path = settings_path()

    settings =
      with {:ok, json_data} <- File.read(path),
           {:ok, data} <- JSON.decode(json_data),
           {:ok, settings} <- State.to_struct(data) do
        settings
      else
        _error ->
          %State{}
      end

    {:ok, %{settings: put_default_values(settings), path: path}}
  end

  @impl true
  def handle_call(:get_settings, _from, state) do
    {:reply, state.settings, state}
  end

  @impl true
  def handle_call({:update_router_settings, params}, _from, state) do
    state = do_update_settings(state, %{router: params})
    {:reply, state.settings, state}
  end

  @impl true
  def handle_call({:update_power_schedule_settings, params}, _from, state) do
    state = do_update_settings(state, %{power_schedule: params})
    {:reply, state.settings, state}
  end

  @impl true
  def handle_call({:update_ups_settings, params}, _from, state) do
    state = do_update_settings(state, %{ups: params})
    {:reply, state.settings, state}
  end

  defp do_update_settings(state, params) do
    with {:ok, new_settings} <- State.to_struct(state.settings, params),
         :ok <- File.write(state.path, JSON.encode!(new_settings)) do

      if state.settings != new_settings do
        Phoenix.PubSub.broadcast!(
          ExNVR.Nerves.PubSub,
          @system_settings_topic,
          {:system_settings, :update}
        )
      end

      %{state | settings: new_settings}
    else
      {:error, reason} ->
        Logger.error("Failed to update settings: #{inspect(reason)}")
        state
    end
  end

  defp settings_path() do
    Application.get_env(:ex_nvr_fw, :system_settings_path, @default_path)
  end

  defp put_default_values(settings) do
    %{
      settings
      | power_schedule: settings.power_schedule || %State.PowerSchedule{},
        router: settings.router || %State.Router{},
        ups: settings.ups || %State.UPS{}
    }
  end
end
