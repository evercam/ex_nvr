defmodule ExNVR.Nerves.RecomputerR22.SimConfigurer do
  @moduledoc false

  import SweetXml

  require Logger

  alias ExNVR.Nerves.RecomputerR22.ATModem

  @apns_file "apns-full-conf.xml"

  @spec auto_configure_apn(non_neg_integer()) :: {:ok, binary()} | {:error, term()}
  def auto_configure_apn(cid \\ 1) do
    with :ok <- start_modem() do
      try do
        configure(cid)
      after
        stop_modem()
      end
    end
  end

  defp configure(cid) do
    with {:ok, imsi} <- fetch_imsi(),
         {:ok, mcc, mncs} <- parse_imsi(imsi),
         {:ok, entry} <- lookup_apn(mcc, mncs) do
      Logger.info(
        ~s|SimConfigurer: IMSI=#{imsi} MCC=#{mcc} MNC=#{entry.mnc} -> APN="#{entry.apn}"|
      )

      with {:ok, _} <- ATModem.set_pdp_context(cid, "IP", entry.apn) do
        {:ok, entry.apn}
      end
    end
  end

  defp start_modem do
    case ATModem.start() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, {:modem_start_failed, reason}}
    end
  end

  defp stop_modem do
    ATModem.close()
  catch
    :exit, _ -> :ok
  end

  defp fetch_imsi do
    case ATModem.imsi() do
      {:ok, imsi} when is_binary(imsi) -> {:ok, String.trim(imsi)}
      {:ok, other} -> {:error, {:unexpected_imsi_response, other}}
      {:error, _} = err -> err
    end
  end

  # MNC length isn't encoded in the IMSI (varies 2-3 digits by country), so
  # we try the 3-digit form first and fall back to the 2-digit form.
  defp parse_imsi(<<mcc::binary-size(3), rest::binary>>) when byte_size(rest) >= 2 do
    mncs =
      [String.slice(rest, 0, 3), String.slice(rest, 0, 2)]
      |> Enum.filter(&(byte_size(&1) >= 2))
      |> Enum.uniq()

    {:ok, mcc, mncs}
  end

  defp parse_imsi(imsi), do: {:error, {:invalid_imsi, imsi}}

  defp lookup_apn(mcc, mncs) do
    Enum.find_value(mncs, {:error, {:apn_not_found, mcc, mncs}}, fn mnc ->
      case scan(mcc, mnc) do
        nil -> nil
        entry -> {:ok, entry}
      end
    end)
  end

  defp scan(mcc, mnc) do
    :ex_nvr_fw
    |> Application.app_dir(["priv", @apns_file])
    |> File.stream!()
    |> SweetXml.stream_tags(:apn, discard: [:apn])
    |> Enum.reduce_while(nil, fn {:apn, node}, _acc ->
      entry = extract_entry(node)
      if matches?(entry, mcc, mnc), do: {:halt, entry}, else: {:cont, nil}
    end)
  end

  defp extract_entry(node) do
    %{
      apn: xpath(node, ~x"./@apn"s),
      mcc: xpath(node, ~x"./@mcc"s),
      mnc: xpath(node, ~x"./@mnc"s),
      type: xpath(node, ~x"./@type"s),
      carrier_enabled: xpath(node, ~x"./@carrier_enabled"s)
    }
  end

  defp matches?(entry, mcc, mnc) do
    entry.mcc == mcc and entry.mnc == mnc and
      entry.carrier_enabled != "false" and entry.apn != "" and
      default_apn?(entry.type)
  end

  defp default_apn?(""), do: true
  defp default_apn?(type), do: String.contains?(type, "default")
end
