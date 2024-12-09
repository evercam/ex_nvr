defmodule ExNVR.RTP.Payloader.H265 do
  @moduledoc false

  @behaviour ExWebRTC.RTP.Payloader.Behaviour

  alias ExNVR.RTSP.Depayloader.H265.{FU, AP}
  alias ExRTP.Packet

  @nalu_prefixes [<<1::24>>, <<1::32>>]

  @enforce_keys [:max_payload_size]
  defstruct @enforce_keys

  @impl true
  def new(max_payload_size) do
    %__MODULE__{max_payload_size: max_payload_size}
  end

  @impl true
  def payload(%__MODULE__{max_payload_size: max_payload_size} = payloader, frame) do
    frame
    |> :binary.split(@nalu_prefixes, [:global, :trim_all])
    |> Enum.reduce([], &group_nalus(&1, &2, max_payload_size))
    |> Enum.map(&encode(&1, max_payload_size))
    |> set_marker()
    |> Enum.reverse()
    |> List.flatten()
    |> then(&{&1, payloader})
  end

  # the first two bytes of the nalu will be extracted and put only on the first rtp packet.
  defp group_nalus(nalu, acc, max_payload_size) when byte_size(nalu) > max_payload_size + 2,
    do: [nalu | acc]

  # byte_size(nalu) + 2 is the size of the nalu in AP after adding nalu size into the packet.
  defp group_nalus(nalu, [{:ap, size, nalus} | rest], max_payload_size)
       when byte_size(nalu) + size + 2 <= max_payload_size do
    [{:ap, size + byte_size(nalu) + 2, [nalu | nalus]} | rest]
  end

  defp group_nalus(nalu, acc, _max_payload_size) do
    [{:ap, byte_size(nalu), [nalu]} | acc]
  end

  defp encode({:ap, _size, [nalu]}, _max_payload_size), do: Packet.new(nalu)

  defp encode({:ap, _size, nalus}, _max_payload_size) do
    <<r::1, _type::6, layer_id::6, tid::3, _rest::binary>> = hd(nalus)

    nalus
    |> AP.serialize(r, layer_id, tid)
    |> Packet.new()
  end

  defp encode(nalu, max_payload_size) do
    nalu
    |> FU.serialize(max_payload_size)
    |> Enum.map(&Packet.new/1)
  end

  defp set_marker([%Packet{} = packet | rest]), do: [%{packet | marker: true} | rest]

  defp set_marker([packets | rest]) do
    packets = List.update_at(packets, -1, &%{&1 | marker: true})
    [packets | rest]
  end
end
