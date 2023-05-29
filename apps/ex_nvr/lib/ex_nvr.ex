defmodule ExNVR do
  @moduledoc false

  require Logger

  alias ExNVR.{Accounts, Devices, Pipelines, Recordings}
  alias ExNVR.Model.Device

  @doc """
  Start the main pipeline
  """
  def start() do
    if Application.get_env(:ex_nvr, :run_pipelines, true) do
      create_directories()
      create_admin_user()
      run_pipelines()
    end
  end

  # create recording & HLS directories
  defp create_directories() do
    File.mkdir_p!(recording_directory())
    File.mkdir_p!(Application.get_env(:ex_nvr, :hls_directory))
  end

  defp create_admin_user() do
    # if no user create an admin
    if Accounts.count_users() == 0 do
      username = Application.get_env(:ex_nvr, :admin_username)
      password = Application.get_env(:ex_nvr, :admin_password)

      with {:error, changeset} =
             Accounts.register_user(%{email: username, password: password, role: :admin}) do
        Logger.error("""
        Could not create admin user, exiting app...
        #{inspect(changeset)}
        """)

        System.halt(-1)
      end
    end
  end

  defp run_pipelines() do
    for device <- Devices.list() do
      options = [
        device_id: device.id,
        stream_uri: build_stream_uri(device)
      ]

      File.mkdir_p!(Path.join(recording_directory(), device.id))
      # make last active run inactive
      # may happens on application crash
      Recordings.deactivate_runs(device.id)
      Pipelines.Supervisor.start_pipeline(options)
    end
  end

  defp build_stream_uri(%Device{config: config}) do
    userinfo =
      if to_string(config["username"]) != "" and to_string(config["password"]) != "" do
        "#{config["username"]}:#{config["password"]}"
      end

    config
    |> Map.fetch!("stream_uri")
    |> URI.parse()
    |> then(&%URI{&1 | userinfo: userinfo})
    |> URI.to_string()
  end

  defp recording_directory(), do: Application.get_env(:ex_nvr, :recording_directory)
end
