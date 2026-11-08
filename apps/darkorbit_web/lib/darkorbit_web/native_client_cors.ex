defmodule DarkorbitWeb.NativeClientCors do
  @moduledoc """
  CORS for the explicitly named native-app JSON endpoints, never for cookies,
  browser login pages or general Phoenix APIs.
  """
  @behaviour Plug

  import Plug.Conn

  @origins ~w(tauri://localhost http://tauri.localhost https://tauri.localhost)

  def init(opts), do: opts

  def call(%Plug.Conn{request_path: "/api/native/" <> _} = conn, _opts) do
    origin = get_req_header(conn, "origin") |> List.first()

    cond do
      is_binary(origin) and origin not in @origins ->
        conn |> send_resp(403, "Forbidden origin") |> halt()

      true ->
        conn =
          if origin in @origins do
            conn
            |> put_resp_header("access-control-allow-origin", origin)
            |> put_resp_header("vary", "Origin")
            |> put_resp_header("access-control-allow-methods", "POST, OPTIONS")
            |> put_resp_header("access-control-allow-headers", "content-type, authorization")
            |> put_resp_header("access-control-max-age", "600")
          else
            conn
          end

        if conn.method == "OPTIONS" do
          conn |> send_resp(204, "") |> halt()
        else
          conn
        end
    end
  end

  def call(conn, _opts), do: conn

  # Phoenix Socket requires its own Origin validation. Explicitly allow the
  # bundled Tauri origins as well as the configured HTTPS host and local dev.
  def socket_origin_allowed?(
        %URI{} = uri,
        dev_origins \\ Application.get_env(:darkorbit_web, :native_dev_socket_origins, [])
      ) do
    native? =
      (uri.scheme == "tauri" and uri.host == "localhost") or
        (uri.scheme in ["http", "https"] and uri.host == "tauri.localhost")

    public_host =
      Application.get_env(:darkorbit_web, DarkorbitWeb.Endpoint, [])
      |> Keyword.get(:url, [])
      |> Keyword.get(:host, "localhost")

    public? = uri.scheme == "https" and uri.host == public_host and uri.port in [443, 4000]
    dev? =
      uri.host in ["localhost", "127.0.0.1"] and
        uri.scheme in ["http", "https"] and uri.port == 4000

    # Tauri dev runs the packaged UI on its own loopback origin (port 1430
    # on Pop!_OS). Accept only explicitly configured origins in development;
    # production never configures this allowlist.
    tauri_dev? = URI.to_string(uri) in dev_origins
    # Explicit opt-in for trusted phone-only LAN TLS. This is absent in
    # production and allows only the exact configured host and port.
    helmet_lan? =
      URI.to_string(uri) ==
        Application.get_env(:darkorbit_web, :helmet_dev_lan_https_origin, "")

    native? or public? or dev? or tauri_dev? or helmet_lan?
  end
end
