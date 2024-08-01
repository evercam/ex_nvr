defmodule ExNVR.RTSP.H265.AP do
  @moduledoc """
  Module responsible for parsing Aggregation Packets.

  Documented in [RFC7798](https://tools.ietf.org/html/rfc7798#page-28)

  ```
    0                   1                   2                   3
    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |                         RTP Header                            |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |    PayloadHdr (Type=48)     |        NALU 1 Size              |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |        NALU 1 HDR           |                                 |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+      NALU 1 Data              |
    |                  . . .                                        |
    |                                                               |
    +               +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    | . . .         | NALU 2 Size                   | NALU 2 HDR    |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    | NALU 2 HDR    |                                               |
    +-+-+-+-+-+-+-+-+             NALU 2 Data                       |
    |                   . . .                                       |
    |                               +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |                               :...OPTIONAL RTP padding        |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  ```

  A packet width DONL
  ```
  0                   1                   2                   3
  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |                          RTP Header                           |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |     PayloadHdr (Type=48)    |          NALU 1 DONL            |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |         NALU 1 Size         |          NALU 1 HDR             |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |                                                               |
  |                NALU 1 Data  . . .                             |
  |                                                               |
  +     . . .    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+|
  | NALU 2 DOND  |               NALU 2 Size                      |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |         NALU 2 HDR          |                                 |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+         NALU 2 Data           |
  |                                                               |
  |          . . .                +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |                               :...OPTIONAL RTP padding        |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  ```
  """
  use Bunch

  alias ExNVR.RTSP.H265.NAL

  @type don :: nil | non_neg_integer()

  @spec parse(binary(), boolean()) :: {:ok, [{binary(), don()}]} | {:error, :packet_malformed}
  def parse(data, donl? \\ false) do
    if donl?,
      do: do_parse(data, 0, []),
      else: do_parse(data, [])
  end

  # Parse packet without DONL
  defp do_parse(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  defp do_parse(<<size::16, nalu::binary-size(size), rest::binary>>, acc),
    do: do_parse(rest, [{nalu, nil} | acc])

  defp do_parse(_data, _acc), do: {:error, :packet_malformed}

  # Parse packets with DONL
  defp do_parse(<<>>, _last_don, acc), do: {:ok, Enum.reverse(acc)}

  defp do_parse(
         <<donl::16, size::16, nalu::binary-size(size), rest::binary>>,
         _last_don,
         [] = acc
       ) do
    do_parse(rest, donl, [{nalu, donl} | acc])
  end

  defp do_parse(<<dond::8, size::16, nalu::binary-size(size), rest::binary>>, last_don, acc) do
    don = rem(last_don + dond + 1, 65_536)
    do_parse(rest, don, [{nalu, don} | acc])
  end

  defp do_parse(_data, _last_don, _acc), do: {:error, :packet_malformed}

  @spec aggregation_unit_size(binary()) :: pos_integer()
  def aggregation_unit_size(nalu), do: byte_size(nalu) + 2

  @spec serialize([binary], 0..1, NAL.Header.nuh_layer_id(), NAL.Header.nuh_temporal_id_plus1()) ::
          binary
  def serialize(payloads, reserved, layer_id, t_id) do
    payloads
    |> Enum.reverse()
    |> Enum.map(&<<byte_size(&1)::16, &1::binary>>)
    |> IO.iodata_to_binary()
    |> NAL.Header.add_header(reserved, NAL.Header.encode_type(:ap), layer_id, t_id)
  end
end
