ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(ExNVR.Repo, :manual)

Faker.start()

File.mkdir_p!(ExNVR.Utils.recording_dir())
