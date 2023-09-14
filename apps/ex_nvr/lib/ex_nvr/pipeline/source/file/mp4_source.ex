defmodule ExNVR.Pipeline.Source.File.MP4 do
  @moduledoc """
  An Element responsible for streaming a file video.
  """

  use Membrane.Source

  require Membrane.Logger

  alias ExNVR.Elements.MP4.Depayloader.Native
  alias Membrane.{Buffer, H264}

  def_output_pad :output,
    demand_mode: :manual,
    accepted_format: %H264.RemoteStream{alignment: :au},
    availability: :always

  def_options location: [
                spec: String.t(),
                description: "The location of the video file"
              ],
              loop: [
                spec: boolean(),
                default: false,
                description: "Whether to loop the video indefinitely"
              ]

  @impl true
  def handle_init(_ctx, options) do
    Membrane.Logger.debug("Initialize the file source element")

    state =
      Map.from_struct(options)
      |> Map.merge(%{
        depayloader: nil,
        time_base: nil,
        current_dts: 0,
        last_access_unit_dts: nil,
        pending_buffers: [],
        buffer?: true
      })

    {[], state}
  end

  @impl true
  def handle_setup(_ctx, options) do
    Membrane.Logger.debug("Setup the file source element, start streaming")

    {[], options}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {actions, state} = maybe_loop_file(state, :play)
    {[notify_parent: {:started_streaming}, stream_format: {:output, %H264.RemoteStream{alignment: :au}}] ++ actions, state}
  end

  @impl true
  def handle_demand(:output, _size, :buffers, _ctx, state) do
    case Native.read_access_unit(state.depayloader) do
      {:ok, buffers, dts, pts, keyframes} ->
        map_buffers(state, buffers, dts, pts, keyframes)
        |> prepare_buffer_actions(state)
        |> maybe_redemand()

      {:error, _reason} ->
        maybe_loop_file(state, :error)
    end
  end

  defp prepare_buffer_actions(buffers, %{buffer?: true} = state) do
    last_dts = List.last(buffers).dts
    pending_buffers = Enum.reverse(buffers) ++ state.pending_buffers

    if last_dts >= 0 do
      {first, second} = Enum.split_while(pending_buffers, &(not &1.metadata.key_frame?))

      # rewrite the dts/pts of the buffers so the hd(second) will have dts/pts of 0
      first_dts = hd(second).dts

      buffers =
        Enum.map(
          [hd(second) | Enum.reverse(first)],
          &%Buffer{&1 | dts: &1.dts - first_dts, pts: &1.pts - first_dts}
        )

      {[buffer: {:output, buffers}],
       %{
         state
         | buffer?: false,
           pending_buffers: [],
           last_access_unit_dts: last_dts - first_dts,
           current_dts: -first_dts,
       }}
    else
      {[],
       %{
         state
         | pending_buffers: pending_buffers,
           last_access_unit_dts: last_dts
       }}
    end
  end

  defp prepare_buffer_actions(buffers, state) do
    state = %{state | last_access_unit_dts: List.last(buffers).dts}
    {[buffer: {:output, buffers}], state}
  end

  defp map_buffers(%{time_base: {ticks, base}} = state, buffers, dts, pts, keyframes) do
    [buffers, dts, pts, keyframes]
    |> Enum.zip()
    |> Enum.map(fn {payload, dts, pts, key_frame?} ->
      dts = div(dts * base * Membrane.Time.second(), ticks)
      pts = div(pts * base * Membrane.Time.second(), ticks)

      %Buffer{
        payload: payload,
        dts: dts + state.current_dts,
        pts: pts + state.current_dts,
        metadata: %{key_frame?: key_frame?}
      }
    end)
  end

  defp maybe_redemand({actions, state}) do
    if Keyword.has_key?(actions, :end_of_stream) do
      {actions, state}
    else
      {actions ++ [redemand: :output], state}
    end
  end

  defp maybe_loop_file(state, action) do
    Membrane.Logger.debug("Reached end of file of the current file")
    if state.loop or action == :play do
      state = %{
        state
        | current_dts: state.last_access_unit_dts || 0,
          last_access_unit_dts: nil
      }

      {[redemand: :output], open_file(state)}
    else
      Membrane.Logger.debug("Finished reading the video file, sending end of stream")
      {[end_of_stream: :output, notify_parent: {:finished_streaming}], state}
    end
  end

  defp open_file(state) do
    Membrane.Logger.debug("Open current file: #{state.location}")

    {depayloader, time_base} = Native.open_file!(state.location)

    %{state | depayloader: depayloader, time_base: time_base}
  end
end
