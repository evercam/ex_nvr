module ExNVR.Elements.MP4.Depayloader.Native

state_type "State"

interface [NIF]

spec open_file(filename :: string) :: {:ok :: label, state, time_base_num :: int, time_base_den :: int}
                                      | {:error :: label, reason :: atom}

spec read_access_unit(state) :: {:ok :: label, access_unit :: [payload], pts :: [int64]}
                                  | {:error :: label, reason :: atom}
