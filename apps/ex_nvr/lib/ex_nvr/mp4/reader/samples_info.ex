defmodule ExNVR.MP4.Reader.SamplesInfo do
  @moduledoc false

  alias Membrane.Time
  alias Membrane.{H264, H265}
  alias Membrane.MP4.Container
  alias Membrane.MP4.MovieBox.SampleTableBox
  alias Membrane.MP4.Track.SampleTable

  @enforce_keys [
    :samples,
    :tracks_number,
    :timescales,
    :sample_tables
  ]

  defstruct @enforce_keys

  @typedoc """
  A struct containing the descriptions of all the samples inside the `mdat` box, as well
  as some metadata needed to generate the output buffers.
  The samples' descriptions are ordered in the way they are stored inside the `mdat` box.

  As the data is processed, the processed samples' descriptions are removed from the list.
  """
  @type t :: %__MODULE__{
          samples: [
            %{
              size: pos_integer(),
              sample_delta: pos_integer(),
              track_id: pos_integer(),
              pts: Membrane.Time.t(),
              dts: Membrane.Time.t(),
              sync: boolean()
            }
          ],
          timescales: %{
            (track_id :: pos_integer()) => timescale :: pos_integer()
          },
          tracks_number: pos_integer(),
          sample_tables: %{(track_id :: pos_integer()) => SampleTable.t()}
        }

  @spec get_video_track(t()) :: {non_neg_integer(), Membrane.H264.t() | Membrane.H265.t()} | nil
  def get_video_track(samples_info) do
    Enum.find_value(samples_info.sample_tables, nil, fn {track_id, sample_table} ->
      case sample_table.sample_description do
        %module{} = h26x when module in [H264, H265] ->
          {track_id, h26x}

        _other ->
          nil
      end
    end)
  end

  @spec get_mdat_offset(t()) :: non_neg_integer()
  def get_mdat_offset(%{sample_tables: sample_tables}) do
    sample_tables
    |> Enum.map(fn {_track_id, sample_table} ->
      List.first(sample_table.chunk_offsets)
    end)
    |> Enum.min()
  end

  @doc """
  Processes the `moov` box and returns a __MODULE__.t() struct, which describes all the samples which are
  present in the `mdat` box.
  The list of samples in the returned struct is used to extract data from the `mdat` box and get output buffers.
  """
  @spec get_samples_info(%{children: boxes :: Container.t()}) :: t
  def get_samples_info(%{children: boxes}) do
    tracks =
      boxes
      |> Enum.filter(fn {type, _content} -> type == :trak end)
      |> Enum.into(%{}, fn {:trak, %{children: boxes}} ->
        {boxes[:tkhd].fields.track_id, boxes}
      end)

    sample_tables =
      Map.new(tracks, fn {track_id, boxes} ->
        {track_id,
         SampleTableBox.unpack(
           boxes[:mdia].children[:minf].children[:stbl],
           boxes[:mdia].children[:mdhd].fields.timescale
         )
         |> Map.put(:sync, unpack_sync_samples(boxes[:mdia].children[:minf].children[:stbl]))}
      end)

    # Create a list of chunks in the order in which they are stored in the `mdat` box
    chunk_offsets =
      Enum.flat_map(tracks, fn {track_id, _boxes} ->
        chunks_with_no =
          sample_tables[track_id].chunk_offsets
          |> Enum.with_index(1)

        Enum.map(
          chunks_with_no,
          fn {offset, chunk_no} ->
            %{chunk_no: chunk_no, chunk_offset: offset, track_id: track_id}
          end
        )
      end)
      |> Enum.sort_by(&Map.get(&1, :chunk_offset))

    tracks_data =
      Map.new(sample_tables, fn {track_id, sample_table} ->
        {track_id,
         Map.take(sample_table, [
           :decoding_deltas,
           :sample_sizes,
           :samples_per_chunk,
           :composition_offsets,
           :sync
         ])}
      end)

    # Create a samples' description list for each chunk and flatten it
    {samples, _acc} =
      chunk_offsets
      |> Enum.flat_map_reduce(tracks_data, fn %{track_id: track_id} = chunk, tracks_data ->
        {new_samples, track_data} = get_chunk_samples(chunk, tracks_data[track_id])
        {new_samples, %{tracks_data | track_id => track_data}}
      end)

    timescales =
      Map.new(sample_tables, fn {track_id, sample_table} ->
        {track_id, sample_table.timescale}
      end)

    {samples, _} = get_dts_and_pts(samples, timescales)
    {samples, _} = get_sync_samples(samples, tracks_data)

    %__MODULE__{
      samples: samples,
      tracks_number: map_size(tracks),
      timescales: timescales,
      sample_tables: sample_tables
    }
  end

  defp get_chunk_samples(chunk, track_data) do
    %{chunk_no: chunk_no, track_id: track_id} = chunk

    {track_data, samples_no} = get_samples_no(chunk_no, track_data)

    Enum.map_reduce(1..samples_no, track_data, fn _no, track_data ->
      {sample, track_data} = get_sample_description(track_data)
      sample = Map.put(sample, :track_id, track_id)
      {sample, track_data}
    end)
  end

  defp get_samples_no(chunk_no, %{samples_per_chunk: samples_per_chunk} = track) do
    {samples_per_chunk, samples_no} =
      case samples_per_chunk do
        [
          %{first_chunk: ^chunk_no, samples_per_chunk: samples_no} = current_chunk_group,
          %{first_chunk: next_chunk_group_no} = next_chunk_group | samples_per_chunk
        ] ->
          samples_per_chunk =
            if chunk_no + 1 == next_chunk_group_no do
              # If the currently processed chunk is the last one in its group
              # we remove this chunk group description
              [next_chunk_group | samples_per_chunk]
            else
              [
                %{current_chunk_group | first_chunk: chunk_no + 1},
                next_chunk_group | samples_per_chunk
              ]
            end

          {samples_per_chunk, samples_no}

        [
          %{first_chunk: ^chunk_no, samples_per_chunk: samples_no} = current_chunk_group
        ] ->
          {[%{current_chunk_group | first_chunk: chunk_no + 1}], samples_no}
      end

    {%{track | samples_per_chunk: samples_per_chunk}, samples_no}
  end

  defp get_sample_description(
         %{
           decoding_deltas: deltas,
           sample_sizes: sample_sizes,
           composition_offsets: composition_offsets
         } = track_data
       ) do
    [size | sample_sizes] = sample_sizes

    {delta, deltas} =
      case deltas do
        [%{sample_count: 1, sample_delta: delta} | deltas] ->
          {delta, deltas}

        [%{sample_count: count, sample_delta: delta} | deltas] ->
          {delta, [%{sample_count: count - 1, sample_delta: delta} | deltas]}
      end

    {sample_composition_offset, composition_offsets} =
      case composition_offsets do
        [%{sample_count: 1, sample_composition_offset: offset} | composition_offsets] ->
          {offset, composition_offsets}

        [%{sample_count: count, sample_composition_offset: offset} | composition_offsets] ->
          {offset,
           [%{sample_count: count - 1, sample_composition_offset: offset} | composition_offsets]}
      end

    {%{size: size, sample_delta: delta, sample_composition_offset: sample_composition_offset},
     %{
       track_data
       | decoding_deltas: deltas,
         sample_sizes: sample_sizes,
         composition_offsets: composition_offsets
     }}
  end

  defp unpack_sync_samples(%{children: boxes}) do
    if stss = boxes[:stss] do
      %{fields: %{entry_list: entry_list}} = stss
      Enum.map(entry_list, fn %{sample_number: sample_no} -> sample_no end)
    else
      []
    end
  end

  defp get_dts_and_pts(samples, timescales) do
    last_dts = Map.new(timescales, fn {track_id, _timescale} -> {track_id, nil} end)

    Enum.map_reduce(samples, last_dts, fn %{track_id: track_id} = sample, last_dts ->
      timescale = timescales[track_id]

      {dts, pts} =
        case last_dts[track_id] do
          nil ->
            {0, 0}

          last_dts ->
            {last_dts + scalify(sample.sample_delta, timescale),
             last_dts +
               scalify(sample.sample_delta + sample.sample_composition_offset, timescale)}
        end

      sample =
        sample
        |> Map.take([:track_id, :size])
        |> Map.merge(%{dts: Ratio.trunc(dts), pts: Ratio.trunc(pts)})

      {sample, Map.put(last_dts, track_id, dts)}
    end)
  end

  defp get_sync_samples(samples, %{sync: []}), do: samples

  defp get_sync_samples(samples, track_data) do
    counter = Map.new(track_data, fn {track_id, _data} -> {track_id, 1} end)

    Enum.map_reduce(samples, counter, fn %{track_id: track_id} = sample, counter ->
      sample = Map.put(sample, :sync, counter[track_id] in track_data[track_id].sync)
      {sample, Map.update!(counter, track_id, &(&1 + 1))}
    end)
  end

  defp scalify(delta, timescale) do
    delta / timescale * Time.second()
  end
end
