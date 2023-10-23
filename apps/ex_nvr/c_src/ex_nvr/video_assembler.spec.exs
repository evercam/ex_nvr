module ExNVR.VideoAssembler.Native

state_type "State"

interface [NIF]

type recording :: %ExNVR.Model.Recording.Download{
  path: string,
  start_date: int64,
  end_date: int64
}

spec assemble_recordings(recordings :: [recording], start_date :: int64, end_date :: int64, duration :: int64, dest :: string) ::
  {:ok :: label, start_date :: int64} | {:error :: label, reason :: atom}
  :ok | {:error :: label, reason :: atom}

dirty :cpu, assemble_files: 2
