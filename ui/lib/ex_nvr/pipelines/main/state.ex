defmodule ExNVR.Pipelines.Main.State do
  @moduledoc false

  use Bunch.Access

  alias ExNVR.Model.Device
  alias ExNVR.Pipeline.Track

  @default_segment_duration Membrane.Time.seconds(60)

  @typedoc """
  Pipeline state

  `device` - The device from where to pull the media streams
  `segment_duration` - The duration of each video chunk saved by the storage bin.
  `supervisor_pid` - The supervisor pid of this pipeline (needed to stop a pipeline)
  `live_snapshot_waiting_pids` - List of pid waiting for live snapshot request to be completed
  `main_stream_video_track` - The main stream video track.
  `sub_stream_video_track` - The sub stream video track.
  `record_main_stream?` - Whether to record the main stream or not.
  `ice_servers` - The list of ICE or/and TURN servers to use for WebRTC.
  `storage_monitor` - pid of the process responsible for monitoring recording
  """
  @type t :: %__MODULE__{
          device: Device.t(),
          segment_duration: Membrane.Time.t(),
          supervisor_pid: pid(),
          live_snapshot_waiting_pids: list(),
          main_stream_video_track: Track.t(),
          sub_stream_video_track: Track.t() | nil,
          record_main_stream?: boolean(),
          ice_servers: list(map()),
          storage_monitor: pid()
        }

  @enforce_keys [:device]

  defstruct @enforce_keys ++
              [
                segment_duration: @default_segment_duration,
                supervisor_pid: nil,
                live_snapshot_waiting_pids: [],
                main_stream_video_track: nil,
                sub_stream_video_track: nil,
                record_main_stream?: false,
                ice_servers: [],
                storage_monitor: nil
              ]
end
