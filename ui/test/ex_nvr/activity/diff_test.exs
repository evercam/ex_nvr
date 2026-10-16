defmodule ExNVR.Activity.DiffTest do
  use ExUnit.Case, async: true

  alias ExNVR.Activity.Diff
  alias ExNVR.Model.Device

  test "returns the new value of changed fields only" do
    assert Diff.changes(%{name: "a", vendor: "x"}, %{name: "b", vendor: "x"}) == %{"name" => "b"}
    assert Diff.changes(%{name: "a"}, %{name: "a"}) == %{}
  end

  test "flattens nested maps and embedded schemas" do
    old = %Device{
      name: "Cam",
      state: :recording,
      stream_config: %Device.StreamConfig{stream_uri: "rtsp://old"},
      credentials: %Device.Credentials{username: "admin", password: "secret1"}
    }

    new = %Device{
      old
      | state: :stopped,
        stream_config: %Device.StreamConfig{stream_uri: "rtsp://new"},
        credentials: %Device.Credentials{username: "admin", password: "secret2"}
    }

    changes = Diff.changes(old, new)

    assert changes == %{
             "state" => "stopped",
             "stream_config.stream_uri" => "rtsp://new",
             "credentials.password" => "[REDACTED]"
           }

    refute inspect(changes) =~ "rtsp://old"
    refute inspect(changes) =~ "secret"
  end

  test "redacts sensitive fields but keeps cleared values" do
    assert Diff.changes(%{token: nil}, %{token: "abc"}) == %{"token" => "[REDACTED]"}
    assert Diff.changes(%{token: "abc"}, %{token: nil}) == %{"token" => nil}

    assert Diff.changes(%{pin: "1234"}, %{pin: "5678"}, redact: [:pin]) == %{
             "pin" => "[REDACTED]"
           }
  end

  test "redacts sensitive fields nested in lists" do
    assert %{"accounts" => [%{"password" => "[REDACTED]", "user" => "a"}]} =
             Diff.changes(%{accounts: []}, %{accounts: [%{user: "a", password: "p"}]})
  end

  test "redact/1 hides sensitive values" do
    assert Diff.redact(%{url: "https://x", token: "abc"}) == %{
             "url" => "https://x",
             "token" => "[REDACTED]"
           }
  end

  test "ignores timestamps and custom keys" do
    old = %{name: "a", updated_at: ~U[2026-01-01 00:00:00Z], notes: "x"}
    new = %{name: "a", updated_at: ~U[2026-02-01 00:00:00Z], notes: "y"}

    assert Diff.changes(old, new, ignore: [:notes]) == %{}
  end

  test "produces JSON encodable values" do
    changes =
      Diff.changes(%{at: ~U[2026-01-01 00:00:00Z], ip: {127, 0, 0, 1}}, %{
        at: ~U[2026-01-02 00:00:00Z],
        ip: {10, 0, 0, 1}
      })

    assert changes["at"] == "2026-01-02T00:00:00Z"
    assert {:ok, _json} = Jason.encode(changes)
  end
end
