ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(ExNVR.Repo, :manual)

Mimic.copy(Onvif.Discovery)
Mimic.copy(Onvif.Device)
Faker.start()
