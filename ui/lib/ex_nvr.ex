defmodule ExNVR do
  @moduledoc false

  require Logger

  import ExNVR.Utils

  alias ExNVR.{Accounts, Devices}
  alias ExNVR.Model.Device

  @first_name "Admin"
  @last_name "Admin"

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
    File.mkdir_p(hls_dir())
    File.mkdir_p(unix_socket_dir())
  end

  defp create_admin_user() do
    # if no user create an admin
    if Accounts.count_users() == 0 do
      username = Application.get_env(:ex_nvr, :admin_username)
      password = Application.get_env(:ex_nvr, :admin_password)

      with {:error, changeset} <-
             Accounts.register_user(%{
               email: username,
               password: password,
               role: :admin,
               first_name: @first_name,
               last_name: @last_name
             }) do
        Logger.error("""
        Could not create admin user, exiting app...
        #{inspect(changeset)}
        """)

        System.halt(:abort)
      end
    end
  end

  defp run_pipelines() do
    Devices.list()
    |> Enum.filter(&Device.recording?/1)
    |> Enum.each(&ExNVR.DeviceSupervisor.start/1)
  end
end
