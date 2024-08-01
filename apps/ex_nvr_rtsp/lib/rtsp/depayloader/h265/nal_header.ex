defmodule ExNVR.RTSP.H265.NAL.Header do
  @moduledoc """
  Defines a structure representing Network Abstraction Layer Unit Header

  Defined in [RFC 7798](https://tools.ietf.org/html/rfc7798#section-1.1.4)

  ```
    +---------------+---------------+
    |0|1|2|3|4|5|6|7|0|1|2|3|4|5|6|7|
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |F|   Type    |  LayerId  | TID |
    +-------------+-----------------+
  ```
  """

  @typedoc """
  Specifies the type of RBSP data structure contained in the NAL unit.
  """
  @type type :: 0..63

  @typedoc """
  Required to be 0 in first version of HEVC, may be used in future extensions.
  """
  @type nuh_layer_id :: 0

  @typedoc """
  Specifies the temporal sub-layer identifier of the NAL unit plus 1.
  """
  @type nuh_temporal_id_plus1 :: 1..7

  @type supported_types :: :ap | :fu | :single_nalu
  @type unsupported_types :: :paci
  @type types :: supported_types | unsupported_types | :reserved

  defstruct [:type, :nuh_layer_id, :nuh_temporal_id_plus1]

  @type t :: %__MODULE__{
          type: type(),
          nuh_layer_id: nuh_layer_id(),
          nuh_temporal_id_plus1: nuh_temporal_id_plus1()
        }

  @spec parse_unit_header(binary()) :: {:error, :malformed_data} | {:ok, {t(), binary()}}
  def parse_unit_header(raw_nal)

  def parse_unit_header(<<0::1, type::6, layer_id::6, tid::3, rest::binary>>) do
    nal = %__MODULE__{
      type: type,
      nuh_layer_id: layer_id,
      nuh_temporal_id_plus1: tid
    }

    {:ok, {nal, rest}}
  end

  # If first bit is not set to 0 packet is flagged as malformed
  def parse_unit_header(_binary), do: {:error, :malformed_data}

  @doc """
  Adds NAL header to payload
  """
  @spec add_header(binary(), 0 | 1, type(), nuh_layer_id(), nuh_temporal_id_plus1()) :: binary()
  def add_header(payload, reserved, type, layer_id, t_id),
    do: <<reserved::1, type::6, layer_id::6, t_id::3>> <> payload

  @doc """
  Parses type stored in NAL Header
  """
  @spec decode_type(t) :: types()
  def decode_type(%__MODULE__{type: type}), do: do_decode_type(type)

  defp do_decode_type(number) when number in 0..47, do: :single_nalu
  defp do_decode_type(48), do: :ap
  defp do_decode_type(49), do: :fu
  defp do_decode_type(50), do: :paci
  defp do_decode_type(_number), do: :reserved

  @doc """
  Encodes given NAL type
  """
  @spec encode_type(types()) :: type()
  def encode_type(:single_nalu), do: 1
  def encode_type(:ap), do: 48
  def encode_type(:fu), do: 49
  def encode_type(:paci), do: 50
end
