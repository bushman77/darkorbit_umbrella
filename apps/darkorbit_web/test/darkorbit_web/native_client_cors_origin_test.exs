defmodule DarkorbitWeb.NativeClientCorsOriginTest do
  use ExUnit.Case, async: false

  alias DarkorbitWeb.NativeClientCors

  setup do
    previous = Application.get_env(:darkorbit_web, :allow_hmd_lan_socket_origin)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:darkorbit_web, :allow_hmd_lan_socket_origin)
      else
        Application.put_env(:darkorbit_web, :allow_hmd_lan_socket_origin, previous)
      end
    end)

    :ok
  end

  test "paired HMD LAN origin is allowed only when enabled for dev and matches the laptop host" do
    origin = URI.parse("http://192.168.0.48:4000")
    hosts = ["192.168.0.48", "10.0.0.4"]

    Application.put_env(:darkorbit_web, :allow_hmd_lan_socket_origin, false)
    refute NativeClientCors.socket_origin_allowed?(origin, [], hosts)

    Application.put_env(:darkorbit_web, :allow_hmd_lan_socket_origin, true)
    assert NativeClientCors.socket_origin_allowed?(origin, [], hosts)
    assert NativeClientCors.socket_origin_allowed?(
             URI.parse("http://10.0.0.4:4000"), [], hosts
           )

    refute NativeClientCors.socket_origin_allowed?(
             URI.parse("http://192.168.0.49:4000"), [], hosts
           )
    refute NativeClientCors.socket_origin_allowed?(
             URI.parse("http://192.168.0.48:4443"), [], hosts
           )
    refute NativeClientCors.socket_origin_allowed?(
             URI.parse("https://192.168.0.48:4000"), [], hosts
           )
    refute NativeClientCors.socket_origin_allowed?(
             URI.parse("http://8.8.8.8:4000"), [], hosts
           )
  end

  test "existing Tauri and loopback socket origins remain accepted" do
    Application.put_env(:darkorbit_web, :allow_hmd_lan_socket_origin, false)

    assert NativeClientCors.socket_origin_allowed?(
             URI.parse("http://127.0.0.1:4000"), [], []
           )
    assert NativeClientCors.socket_origin_allowed?(
             URI.parse("tauri://localhost"), [], []
           )
    assert NativeClientCors.socket_origin_allowed?(
             URI.parse("http://127.0.0.1:1430"), ["http://127.0.0.1:1430"], []
           )
  end
end
