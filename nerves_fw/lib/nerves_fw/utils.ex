defmodule ExNVR.Nerves.Utils do
  @moduledoc false

  @spec get_default_gateway() :: {:ok, String.t()} | {:error, term()}
  def get_default_gateway do
    case System.cmd("ip", ["route"], stderr_to_stdout: true) do
      {output, 0} ->
        String.split(output, "\n")
        |> Enum.find("", &String.starts_with?(&1, "default"))
        |> String.split(" ")
        |> case do
          ["default", "via", gateway | _rest] -> {:ok, gateway}
          _other -> {:error, :no_gateway}
        end

      {error, _exit_status} ->
        {:error, error}
    end
  end

  @spec get_mac_address(String.t()) :: {:ok, String.t()} | {:error, term()}
  def get_mac_address(ip_addr) do
    case System.cmd("ip", ["neigh", "show", ip_addr], stderr_to_stdout: true) do
      {output, 0} ->
        case Enum.at(String.split(output, " "), 4) do
          nil -> {:error, :not_found}
          mac_addr -> {:ok, mac_addr}
        end

      {error, _exit_status} ->
        {:error, error}
    end
  end

  @spec hostname() :: String.t() | nil
  def hostname() do
    case :inet.gethostname() do
      {:ok, hostname} -> to_string(hostname)
      {:error, _} -> nil
    end
  end
end
