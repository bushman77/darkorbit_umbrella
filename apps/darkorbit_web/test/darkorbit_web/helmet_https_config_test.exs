defmodule DarkorbitWeb.HelmetHttpsConfigTest do
  use ExUnit.Case, async: true

  @dev_config Path.expand("../../../../config/dev.exs", __DIR__)

  test "normal development boot configures secure HMD listener without an opt-in switch" do
    source = File.read!(@dev_config)
    assert {:ok, _ast} = Code.string_to_quoted(source)
    assert source =~ ~s(port: 4443)
    assert source =~ ~s(https: [)
    assert source =~ ~s(:helmet_dev_lan_https_origin)
    refute source =~ "DARKORBIT_DEV_LAN_HTTPS"
  end

  test "native client local HTTP and HMD HTTPS are independently configured" do
    source = File.read!(@dev_config)
    assert source =~ ~s(port: 4000)
    assert source =~ ~s(http: [ip:)
    assert source =~ ~s(certfile: certfile)
    assert source =~ ~s(keyfile: keyfile)
    assert source =~ ~s(:inet.getifaddrs())
    assert source =~ ~s("https://" <> lan_host <> ":4443")
  end
end
