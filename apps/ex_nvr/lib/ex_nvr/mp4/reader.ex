defmodule ExNVR.MP4.Reader do
  @moduledoc false

  alias ExNVR.MP4.Reader.SamplesInfo
  alias Membrane.Buffer
  alias Membrane.MP4.Container
  alias Membrane.MP4.Track.SampleTable

  @type track_id :: non_neg_integer()

  @type t :: %__MODULE__{
          fd: IO.device(),
          samples_info: SamplesInfo.t(),
          mdat_offset: non_neg_integer()
        }

  @enforce_keys [:fd, :samples_info]
  defstruct @enforce_keys ++ [mdat_offset: 0]

  @spec new(Path.t()) :: {:ok, t()} | {:error, term()}
  def new(filename) do
    with {:ok, fd} <- File.open(filename, [:read, :binary]),
         {:ok, mov_box} <- lookup_moov_box(fd),
         {box, ""} <- Container.parse!(mov_box) do
      samples_info = SamplesInfo.get_samples_info(box[:moov])
      mdat_offset = SamplesInfo.get_mdat_offset(samples_info)
      :file.position(fd, mdat_offset)

      {:ok,
       %__MODULE__{
         fd: fd,
         samples_info: samples_info,
         mdat_offset: mdat_offset
       }}
    end
  end

  @spec close(t()) :: :ok
  def close(%__MODULE__{} = reader), do: File.close(reader.fd)

  @spec get_video_track(t()) :: {track_id(), SampleTable.t()} | nil
  def get_video_track(%__MODULE__{} = reader),
    do: SamplesInfo.get_video_track(reader.samples_info)

  @spec read_packet(t(), track_id() | nil) :: :eof | {t(), track_id(), Buffer.t()}
  def read_packet(%__MODULE__{} = reader, track_id \\ nil) do
    case do_read_packet(reader.samples_info, track_id, reader.fd) do
      {_samples_info, nil} ->
        :eof

      {samples_info, track_id, packet} ->
        {%__MODULE__{reader | samples_info: samples_info}, track_id, packet}
    end
  end

  @spec seek_file(t(), track_id(), non_neg_integer()) :: t()
  def seek_file(%__MODULE__{samples_info: samples_info} = reader, track_id, ts) do
    index =
      samples_info.samples
      |> Enum.reverse()
      |> Enum.find_index(&(&1.track_id == track_id and &1.sync and &1.dts <= ts))
      |> then(&(length(samples_info.samples) - &1 - 1))

    {to_discard, rest} = Enum.split(samples_info.samples, index)
    total_size = Enum.reduce(to_discard, 0, fn sample, size -> size + sample.size end)
    move_cursor(reader.fd, total_size)

    samples_info = %{samples_info | samples: rest}
    %__MODULE__{reader | samples_info: samples_info}
  end

  defp lookup_moov_box(fd) do
    case IO.binread(fd, 8) do
      <<size::32, "moov">> = box_header ->
        {:ok, box_header <> IO.binread(fd, size - 8)}

      <<size::32, _box_type::binary-size(4)>> ->
        {:ok, _} = :file.position(fd, {:cur, size - 8})
        lookup_moov_box(fd)

      _other ->
        {:error, :invalid_file}
    end
  end

  defp do_read_packet(%{samples: []} = samples_info, _track_id, _fd), do: {samples_info, nil}

  defp do_read_packet(%{samples: [sample | rest]} = samples_info, track_id, fd)
       when is_nil(track_id) or sample.track_id == track_id do
    buffer =
      %Membrane.Buffer{
        payload: IO.binread(fd, sample.size),
        dts: sample.dts,
        pts: sample.pts
      }

    {%{samples_info | samples: rest}, sample.track_id, buffer}
  end

  defp do_read_packet(%{samples: [sample | rest]} = samples_info, track_id, fd) do
    move_cursor(fd, sample.size)
    do_read_packet(%{samples_info | samples: rest}, track_id, fd)
  end

  defp move_cursor(fd, amount), do: :file.position(fd, {:cur, amount})
end
