ExUnit.start(capture_log: true)
Ecto.Adapters.SQL.Sandbox.mode(ExNVR.Repo, :manual)

Mimic.copy(Onvif.Discovery)
Mimic.copy(Onvif.Device)
Faker.start()
