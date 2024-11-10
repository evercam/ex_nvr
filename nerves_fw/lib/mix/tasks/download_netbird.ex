defmodule Mix.Tasks.DownloadNetbird do
  @moduledoc """
  Download netbird from official github releases.
  """

  use Mix.Task.Compiler

  @version "0.30.2"
  @url_prefix "https://github.com/netbirdio/netbird/releases/download/v#{@version}/"

  @impl true
  def run(_args) do
    {:ok, _apps} = Application.ensure_all_started(:httpoison)

    app_name = Mix.Project.config()[:app]
    destination = Path.join(:code.priv_dir(app_name), "netbird")
    archive_prefix = Path.join([:code.priv_dir(app_name), "tmp"])
    archive_path = Path.join(archive_prefix, "netbird.tar.gz")

    with false <- File.exists?(destination),
         :ok <- download_file(archive_path) do
      System.cmd("tar", ["-xf", archive_path, "-C", archive_prefix])
      File.cp!(Path.join(archive_prefix, "netbird"), destination)
      File.rm_rf!(archive_prefix)
    end
  end

  defp download_file(dest) do
    File.mkdir_p!(Path.dirname(dest))

    with {:ok, url} <- build_url(get_target()) do
      HTTPoison.get!(url, [], follow_redirect: true, recv_timeout: :timer.minutes(1))
      |> Map.get(:body)
      |> then(&File.write!(dest, &1))
    end
  end

  defp build_url({"aarch64", "linux", _abi}),
    do: {:ok, "#{@url_prefix}netbird_#{@version}_linux_arm64.tar.gz"}

  defp build_url({"x86_64", "linux", _abi}),
    do: {:ok, "#{@url_prefix}netbird_#{@version}_linux_amd64.tar.gz"}

  defp build_url(_other), do: {:error, :unsupported_architecture}

  defp get_target() do
    {System.fetch_env!("TARGET_ARCH"), System.fetch_env!("TARGET_OS"),
     System.fetch_env!("TARGET_ABI")}
  end
end
