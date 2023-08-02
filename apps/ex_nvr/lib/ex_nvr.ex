defmodule ExNVR do
  @moduledoc false

  require Logger

  import ExNVR.Utils

  alias ExNVR.{Accounts, Devices, Pipelines}

  @doc """
  Start the main pipeline
  """
  def start() do
    if run_main_pipeline?() do
      create_directories()
      create_admin_user()
      run_pipelines()
    end
  end

  # create recording & HLS directories
  defp create_directories() do
    File.mkdir_p!(recording_dir())
    File.mkdir_p!(hls_dir())
  end

  defp create_admin_user() do
    # if no user create an admin
    if Accounts.count_users() == 0 do
      username = Application.get_env(:ex_nvr, :admin_username)
      password = Application.get_env(:ex_nvr, :admin_password)
      first_name = Application.get_env(:ex_nvr, :admin)
      last_name = Application.get_env(:ex_nvr, :admin)

      with {:error, changeset} <-
             Accounts.register_user(%{
               email: username,
               password: password,
               role: :admin,
               first_name: first_name,
               last_name: last_name
             }) do
        Logger.error("""
        Could not create admin user, exiting app...
        #{inspect(changeset)}
        """)

        System.halt(-1)
      end
    end
  end

  defp run_pipelines() do
    for device <- Devices.list(%{state: [:recording, :failed]}) do
      Pipelines.Supervisor.start_pipeline(device)
    end
  end
end
