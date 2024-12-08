defmodule Mix.Tasks.Firmware.Deps do
  use Mix.Task

  @github_api_url "https://api.github.com/repos/:owner/releases"
  @grafana_agent_repo "grafana/agent"
  @netbird_repo "netbirdio/netbird"

  @netbird_regex ~r/^netbird_.*/

  @dest Path.join("rootfs_overlay", "bin")

  @impl true
  def run(_args) do
    :ok = Application.ensure_started(:req)

    File.rm_rf!(@dest)

    download_netbird()
    download_grafana_agent()

    :ok
  end

  defp download_netbird() do
    tmp_path = Path.join(System.tmp_dir!(), "netbird.tar.xz")

    Req.get!(netbird_download_url(), into: File.stream!(tmp_path))

    File.mkdir_p!(@dest)
    {_output, 0} = System.cmd("tar", ["-xvf", tmp_path, "-C", @dest, "netbird"])

    File.rm!(tmp_path)
  end

  defp download_grafana_agent() do
    tmp_path = Path.join(System.tmp_dir!(), "grafana-agent.zip")

    Req.get!(grafana_agent_download_url(), into: File.stream!(tmp_path))

    File.mkdir_p!(@dest)

    {:ok, [grafana_agent]} = :zip.unzip(tmp_path |> to_charlist(), cwd: @dest |> to_charlist())
    File.rename!(grafana_agent |> List.to_string(), Path.join(@dest, "grafana-agent"))

    File.rm!(tmp_path)
  end

  defp netbird_download_url() do
    Req.get!(repo_url(@netbird_repo),
      headers: [{"content-type", "application/vnd.github+json"}],
      params: [per_page: 1]
    )
    |> Map.get(:body)
    |> List.first()
    |> Map.get("assets")
    |> Enum.find(fn %{"name" => name} ->
      arch = System.fetch_env!("TARGET_ARCH") |> map_arch()

      String.match?(name, @netbird_regex) and
        String.ends_with?(name, "linux_" <> arch <> ".tar.gz")
    end)
    |> Map.get("browser_download_url")
  end

  defp grafana_agent_download_url() do
    Req.get!(repo_url(@grafana_agent_repo),
      headers: [{"content-type", "application/vnd.github+json"}],
      params: [per_page: 1]
    )
    |> Map.get(:body)
    |> List.first()
    |> Map.get("assets")
    |> Enum.find(fn %{"name" => name} ->
      arch = System.fetch_env!("TARGET_ARCH") |> map_arch()
      String.ends_with?(name, "linux-" <> arch <> ".zip")
    end)
    |> Map.get("browser_download_url")
  end

  defp repo_url(owner) do
    String.replace(@github_api_url, ":owner", owner)
  end

  defp map_arch("aarch64"), do: "arm64"
end