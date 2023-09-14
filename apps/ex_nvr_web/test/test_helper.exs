ExUnit.start(capture_log: true)
Ecto.Adapters.SQL.Sandbox.mode(ExNVR.Repo, :manual)

Faker.start()

File.mkdir_p!(ExNVR.Utils.recording_dir())
