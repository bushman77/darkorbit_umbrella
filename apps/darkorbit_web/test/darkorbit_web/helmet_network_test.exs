defmodule DarkorbitWeb.HelmetNetworkTest do
  use ExUnit.Case, async: true
  alias DarkorbitWeb.HelmetNetwork

  test "prefers Wi-Fi, then wired LAN, and avoids Docker and loopback" do
    interfaces = [
      {~c"lo", [flags: [:up], addr: {127, 0, 0, 1}]},
      {~c"docker0", [flags: [:up], addr: {172, 17, 0, 1}]},
      {~c"enp6s0", [flags: [:up], addr: {10, 0, 0, 2}]},
      {~c"wlp2s0", [flags: [:up], addr: {192, 168, 1, 56}]},
      {~c"wg0", [flags: [:up], addr: {100, 105, 0, 13}]},
      {~c"wlan1", [flags: [:down], addr: {192, 168, 9, 9}]}
    ]

    assert HelmetNetwork.hosts_from_interfaces(interfaces) ==
             ["192.168.1.56", "10.0.0.2", "100.105.0.13", "172.17.0.1"]
  end

  test "excludes public, link-local, IPv6 and invalid addresses" do
    assert HelmetNetwork.hosts_from_interfaces([
             {~c"eth0",
              [addr: {8, 8, 8, 8}, addr: {169, 254, 10, 3},
               addr: {0, 0, 0, 0}, addr: {192, 168, 20, 11},
               addr: {8193, 3512, 0, 0, 0, 0, 0, 1}]}
           ]) == ["192.168.20.11"]
  end
end
