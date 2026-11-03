defmodule DarkorbitWeb.HelmetNetwork do
  @moduledoc """
  Suggest laptop LAN addresses for phone-based HMD pairing.

  The laptop may serve the game at localhost, but a phone needs the laptop's
  *network* address. These suggestions are sent only to the authenticated
  pilot's helmet control channel, never to the public pairing page. The Atlas
  keeps the address editable for hotspots, VPNs and unusual network setups.
  """

  @doc "Ordered IPv4 host suggestions. DARKORBIT_HMD_HOST overrides detection."
  @spec hosts() :: [String.t()]
  def hosts do
    case System.get_env("DARKORBIT_HMD_HOST") do
      host when is_binary(host) and byte_size(host) > 0 ->
        [String.trim(host)]

      _ ->
        case :inet.getifaddrs() do
          {:ok, interfaces} -> hosts_from_interfaces(interfaces)
          {:error, _reason} -> []
        end
    end
  end

  @doc false
  def hosts_from_interfaces(interfaces) when is_list(interfaces) do
    interfaces
    |> Enum.flat_map(fn {interface, attributes} ->
      name = to_string(interface)

      if interface_up?(attributes) do
        for address <- Keyword.get_values(attributes, :addr),
            local_ipv4?(address),
            do: {interface_priority(name), :inet.ntoa(address) |> to_string()}
      else
        []
      end
    end)
    |> Enum.sort_by(fn {priority, ip} -> {priority, ip} end)
    |> Enum.map(fn {_priority, ip} -> ip end)
    |> Enum.uniq()
  end

  defp interface_up?(attrs) do
    case Keyword.get(attrs, :flags) do
      flags when is_list(flags) -> :up in flags
      _ -> true
    end
  end

  defp local_ipv4?({10, _, _, _}), do: true
  defp local_ipv4?({172, second, _, _}) when second in 16..31, do: true
  defp local_ipv4?({192, 168, _, _}), do: true
  # VPN/tethering networks sometimes use carrier-grade NAT space.
  defp local_ipv4?({100, second, _, _}) when second in 64..127, do: true
  defp local_ipv4?(_), do: false

  defp interface_priority(name) do
    cond do
      String.match?(name, ~r/^(wl|wlan|wifi)/i) -> 0
      String.match?(name, ~r/^(en|eth)/i) -> 1
      String.match?(name, ~r/^(usb|rndis)/i) -> 2
      String.match?(name, ~r/^(tailscale|wg|tun|tap)/i) -> 3
      String.match?(name, ~r/^(docker|veth|br-|virbr|podman)/i) -> 9
      true -> 4
    end
  end
end
