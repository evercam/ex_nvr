defmodule ExNVR do
  @moduledoc false

  require Logger

  import ExNVR.Utils

  alias ExNVR.{Accounts, Devices}
  alias ExNVR.Model.Device

  @first_name "Admin"
  @last_name "Admin"

  @cert_file_path "priv/integrated_turn_cert.pem"

  @doc """
  Start the main pipeline
  """
  def start() do
    if run_main_pipeline?() do
      create_directories()
      create_admin_user()
      run_pipelines()
    end

    config_common_dtls_key_cert()
    create_integrated_turn_cert_file()
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

  defp create_integrated_turn_cert_file() do
    cert_path = Application.fetch_env!(:ex_nvr, :integrated_turn_cert)
    pkey_path = Application.fetch_env!(:ex_nvr, :integrated_turn_pkey)

    if cert_path != nil and pkey_path != nil do
      cert = File.read!(cert_path)
      pkey = File.read!(pkey_path)

      File.touch!(@cert_file_path)
      File.chmod!(@cert_file_path, 0o600)
      File.write!(@cert_file_path, "#{cert}\n#{pkey}")

      Application.put_env(:ex_nvr, :integrated_turn_cert_pkey, @cert_file_path)
    else
      Logger.warning("""
      Integrated TURN certificate or private key path not specified.
      Integrated TURN will not handle TLS connections.
      """)
    end
  end

  defp config_common_dtls_key_cert() do
    {:ok, pid} = ExDTLS.start_link(client_mode: false, dtls_srtp: true)
    {:ok, pkey} = ExDTLS.get_pkey(pid)
    {:ok, cert} = ExDTLS.get_cert(pid)
    :ok = ExDTLS.stop(pid)
    Application.put_env(:ex_nvr, :dtls_pkey, pkey)
    Application.put_env(:ex_nvr, :dtls_cert, cert)
  end
end
