defmodule ExNVR.Nerves.Netbird.IdentityTest do
  @moduledoc false
  use ExUnit.Case, async: false

  import Mimic

  alias ExNVR.Nerves.Netbird
  alias ExNVR.Nerves.Netbird.Identity

  setup :set_mimic_global
  setup :verify_on_exit!

  setup_all do
    Mimic.copy(Netbird)
    :ok
  end

  @status %{
    "daemonStatus" => "Connected",
    "publicKey" => "o8WLBjvzT8kNg2ZPYLePqQ5FlwOb1sW5XpIvPNa+vUs=",
    "fqdn" => "nvr-kit-42.netbird.evercam",
    "netbirdIp" => "100.92.10.4/16",
    "netbirdIpv6" => ""
  }

  test "reports the public key as the identifier and addresses as details" do
    expect(Netbird, :status, fn -> {:ok, @status} end)

    assert {:ok, identity} = Identity.identity()

    assert identity == %{
             service: "netbird",
             identifier: "o8WLBjvzT8kNg2ZPYLePqQ5FlwOb1sW5XpIvPNa+vUs=",
             details: %{"fqdn" => "nvr-kit-42.netbird.evercam", "ip" => "100.92.10.4"}
           }
  end

  test "has nothing to report without a public key" do
    expect(Netbird, :status, fn -> {:ok, Map.put(@status, "publicKey", "")} end)
    assert Identity.identity() == :unavailable
  end

  test "has nothing to report when the daemon needs a login" do
    expect(Netbird, :status, fn -> {:error, :needs_login} end)
    assert Identity.identity() == :unavailable
  end

  test "returns an error when the netbird command fails" do
    expect(Netbird, :status, fn -> {:error, "daemon not running\n", 1} end)
    assert Identity.identity() == {:error, {:exit_status, 1, "daemon not running"}}
  end

  test "turns an exit from the client into a return" do
    expect(Netbird, :status, fn -> exit({:noproc, {GenServer, :call, []}}) end)
    assert Identity.identity() == :unavailable

    expect(Netbird, :status, fn -> exit({:timeout, {GenServer, :call, []}}) end)
    assert {:error, {:exit, {:timeout, _call}}} = Identity.identity()
  end
end
