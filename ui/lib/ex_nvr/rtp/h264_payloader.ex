defmodule ExNVR.RTP.Payloader.H264 do
  @moduledoc false

  @behaviour ExWebRTC.RTP.Payloader.Behaviour

  alias ExRTP.Packet
  alias RTSP.RTP.H264.{FU, StapA}

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

  defp group_nalus(nalu, acc, max_payload_size) when byte_size(nalu) > max_payload_size,
    do: [nalu | acc]

  # byte_size(nalu) + 2 is the size of the nalu in stap_a after adding nalu size into the packet.
  defp group_nalus(nalu, [{:stap_a, size, nalus} | rest], max_payload_size)
       when byte_size(nalu) + size + 2 <= max_payload_size do
    [{:stap_a, size + byte_size(nalu) + 2, [nalu | nalus]} | rest]
  end

  defp group_nalus(nalu, acc, _max_payload_size) do
    [{:stap_a, byte_size(nalu), [nalu]} | acc]
  end

  defp encode({:stap_a, _size, [nalu]}, _max_payload_size), do: Packet.new(nalu)

  defp encode({:stap_a, _size, nalus}, _max_payload_size) do
    <<f::1, nri::2, _type::5, _rest::binary>> = hd(nalus)

    nalus
    |> StapA.serialize(f, nri)
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
