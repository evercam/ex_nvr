defmodule ExNVR.Pipeline.Output.HLS.MultiFileWriter do
  @moduledoc """
  Module implementing the `ExMP4.FragDataWriter` behaviour to write each segment to its own file
  """

  @behaviour ExMP4.FragDataWriter

  alias ExMP4.Box.Sidx

  @styp %ExMP4.Box.Styp{
    major_brand: "mp42",
    minor_version: 512,
    compatible_brands: ["mp42", "mp41", "isom", "avc1"]
  }

  @impl true
  def open(params) do
    state = %{
      dir: params[:dir],
      init_callback: params[:init_write],
      segment_callback: params[:segment_write],
      segment_name_prefix: params[:segment_name_prefix] || "",
      seg_num: params[:start_segment_number] || 0
    }

    {:ok, state}
  end

  @impl true
  def write_init_header(state, header) do
    filename = "#{state.segment_name_prefix}_init.mp4"

    state.dir
    |> Path.join(filename)
    |> File.write!(ExMP4.Box.serialize(header))

    state.init_callback.(filename)
    state
  end

  @impl true
  def write_segment(state, segment) do
    segment_path = Path.join(state.dir, segment_name(state))
    segment_duration = segment_duration(segment)

    File.write!(segment_path, ExMP4.Box.serialize([@styp | segment]))

    state.segment_callback.(%{
      uri: Path.basename(segment_path),
      duration: segment_duration,
      bitrate: segment_bitrate(segment)
    })

    %{state | seg_num: state.seg_num + 1}
  end

  @impl true
  def close(_state), do: :ok

  defp segment_name(state), do: "#{state.segment_name_prefix}_segment_#{state.seg_num}.m4s"

  defp segment_duration(mp4_segment) do
    mp4_segment
    |> Stream.take_while(&is_struct(&1, Sidx))
    |> Stream.map(&Sidx.duration(&1, :second))
    |> Enum.max()
  end

  defp segment_bitrate(mp4_segment) do
    mp4_segment
    |> Enum.take_while(&is_struct(&1, Sidx))
    |> Enum.sum_by(&Sidx.bitrate(&1))
  end
end
