ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(ExNVR.Repo, :manual)

Faker.start()

File.mkdir_p!(Application.get_env(:ex_nvr, :recording_directory))
