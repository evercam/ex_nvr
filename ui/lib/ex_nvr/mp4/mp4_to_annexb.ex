defmodule ExNVR.MP4.MP4ToAnnexb do
  @moduledoc """
  Convert an MP4 elementary stream to annexb format

  Move this to `ex_mp4` repo.
  """

  alias ExMP4.{Sample, Track}

  @nalu_prefix <<0, 0, 0, 1>>

  defstruct nalu_prefix_size: 4, parameters_sets: <<>>

  def init(%Track{type: :video, media: media} = track) when media in [:h264, :h265] do
    init_module(track)
  end

  def filter(%__MODULE__{} = module, %Sample{} = sample) do
    payload = to_annexb(sample.payload, module.nalu_prefix_size)

    payload =
      case sample.sync? do
        true -> module.parameters_sets <> payload
        false -> payload
      end

    %Sample{sample | payload: payload}
  end

  defp init_module(%{priv_data: %ExMP4.Box.Avcc{} = priv_data}) do
    %__MODULE__{
      nalu_prefix_size: priv_data.nalu_length_size,
      parameters_sets: Enum.map_join(priv_data.spss ++ priv_data.ppss, &(@nalu_prefix <> &1))
    }
  end

  defp init_module(%{priv_data: %ExMP4.Box.Hvcc{} = priv_data}) do
    parameter_sets =
      Enum.map_join(
        priv_data.vpss ++ priv_data.spss ++ priv_data.ppss,
        &(@nalu_prefix <> &1)
      )

    %__MODULE__{
      nalu_prefix_size: priv_data.nalu_length_size,
      parameters_sets: parameter_sets
    }
  end

  defp to_annexb(access_unit, nalu_prefix_size) do
    for <<size::size(8 * nalu_prefix_size), nalu::binary-size(size) <- access_unit>>,
      into: <<>>,
      do: @nalu_prefix <> nalu
  end
end
