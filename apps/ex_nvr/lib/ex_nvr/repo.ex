defmodule ExNVR.Repo do
  use Ecto.Repo,
    otp_app: :ex_nvr,
    adapter: Ecto.Adapters.SQLite3

  use Scrivener, page_size: 20
end
