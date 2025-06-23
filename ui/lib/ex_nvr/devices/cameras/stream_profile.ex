defmodule ExNVR.Devices.Cameras.StreamProfile do
  @moduledoc false

  alias Onvif.Media2.Profile

  defmodule VideoConfig do
    @moduledoc false

    alias Onvif.Media2.Profile.VideoEncoder

    @type t :: %__MODULE__{
            codec: atom(),
            codec_profile: nil | binary(),
            width: non_neg_integer(),
            height: non_neg_integer(),
            frame_rate: number(),
            bitrate: non_neg_integer(),
            bitrate_mode: :vbr | :cbr | :abr | nil,
            gop: non_neg_integer(),
            smart_codec: boolean()
          }

    defstruct [
      :codec,
      :codec_profile,
      :width,
      :height,
      :frame_rate,
      :bitrate,
      :bitrate_mode,
      :gop,
      smart_codec: false
    ]

    def from_onvif(%VideoEncoder{} = encoder) do
      %__MODULE__{
        codec: encoder.encoding,
        codec_profile: encoder.profile,
        width: encoder.resolution.width,
        height: encoder.resolution.height,
        frame_rate: encoder.rate_control.frame_rate_limit,
        bitrate: encoder.rate_control.bitrate_limit,
        bitrate_mode: bitrate_mode(encoder.rate_control.constant_bitrate),
        gop: encoder.gov_length
      }
    end

    defp bitrate_mode(true), do: :cbr
    defp bitrate_mode(false), do: :vbr
    defp bitrate_mode(nil), do: nil
  end

  @type t :: %__MODULE__{
          id: binary() | non_neg_integer(),
          enabled: boolean(),
          name: binary(),
          video_config: nil | VideoConfig.t()
        }

  defstruct [
    :id,
    :name,
    enabled: false,
    video_config: nil
  ]

  @spec flatten(t()) :: map()
  def flatten(profile) do
    profile.video_config
    |> Map.from_struct()
    |> Map.merge(Map.take(profile, [:id, :enabled, :name]))
  end

  @spec from_onvif(Profile.t()) :: t()
  def from_onvif(%Profile{} = onvif_profile) do
    %__MODULE__{
      id: onvif_profile.reference_token,
      name: onvif_profile.name,
      enabled: true,
      video_config: VideoConfig.from_onvif(onvif_profile.video_encoder_configuration)
    }
  end
end
