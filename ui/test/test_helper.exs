ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(ExNVR.Repo, :manual)

Mimic.copy(ExOnvif.Discovery)
Mimic.copy(ExOnvif.Device)
Mimic.copy(ExNVR.Devices)
Faker.start()
