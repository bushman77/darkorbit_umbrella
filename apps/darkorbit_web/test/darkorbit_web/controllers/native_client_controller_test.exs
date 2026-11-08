defmodule DarkorbitWeb.NativeClientControllerTest do
  use DarkorbitWeb.ConnCase

  import Darkorbit.AccountsFixtures

  alias DarkorbitWeb.{GameAuth, NativeClientCors}

  @origin "tauri://localhost"

  defp json_post(conn, path, data, token \\ nil) do
    conn =
      conn
      |> put_req_header("origin", @origin)
      |> put_req_header("content-type", "application/json")

    conn =
      if token, do: put_req_header(conn, "authorization", "Bearer " <> token), else: conn

    post(conn, path, Jason.encode!(data))
  end

  test "native probe works without credentials through the same CORS pipeline", %{conn: conn} do
    result = json_post(conn, "/api/native/probe", %{})
    assert json_response(result, 200) == %{"status" => "ok"}
    assert get_resp_header(result, "access-control-allow-origin") == [@origin]
    assert get_resp_header(result, "cache-control") == ["no-store"]
  end

  test "a verified account can launch and refresh a native pilot session", %{conn: conn} do
    password = "native-space-client-123"

    account =
      verified_player_account_fixture(%{
        username: "native_pilot_#{System.unique_integer([:positive])}",
        password: password
      })

    login = json_post(conn, "/api/native/login", %{
      username: account.username,
      password: password
    })
    assert get_resp_header(login, "access-control-allow-origin") == [@origin]
    payload = json_response(login, 200)
    assert payload["pilot_id"] == account.id
    assert payload["pilot_name"] == account.pilot_name
    assert payload["expires_in"] == 900
    assert {:ok, verified} = GameAuth.verify_socket_token(payload["token"])
    assert verified.id == account.id

    refreshed = json_post(build_conn(), "/api/native/refresh", %{}, payload["token"])
    token = json_response(refreshed, 200)["token"]
    assert {:ok, _} = GameAuth.verify_socket_token(token)

    logout = json_post(build_conn(), "/api/native/logout", %{}, token)
    assert response(logout, 204) == ""
    assert :error == GameAuth.verify_socket_token(token)
  end

  test "native login rejects invalid credentials without a session", %{conn: conn} do
    result = json_post(conn, "/api/native/login", %{
      username: "does-not-exist",
      password: "invalid-credential"
    })

    assert json_response(result, 401)["error"] == "Invalid or unverified pilot credentials."
  end

  test "the native API rejects cross-site browser origins", %{conn: conn} do
    conn = put_req_header(conn, "origin", "https://untrusted.example")
    result = options(conn, "/api/native/login")
    assert response(result, 403) == "Forbidden origin"
  end

  test "Tauri receives credential-free CORS preflight", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", @origin)
      |> put_req_header("access-control-request-method", "POST")
      |> put_req_header("access-control-request-headers", "content-type")

    result = options(conn, "/api/native/login")
    assert response(result, 204) == ""
    assert get_resp_header(result, "access-control-allow-origin") == [@origin]
  end

  test "only expected socket origins are accepted" do
    assert NativeClientCors.socket_origin_allowed?(URI.parse("tauri://localhost"))
    assert NativeClientCors.socket_origin_allowed?(URI.parse("http://tauri.localhost"))
    refute NativeClientCors.socket_origin_allowed?(URI.parse("https://attacker.example"))
  end

  test "Tauri loopback WebSocket origin is only allowed by explicit dev configuration" do
    dev_origin = URI.parse("http://127.0.0.1:1430")
    allowed = ["http://127.0.0.1:1430"]

    assert NativeClientCors.socket_origin_allowed?(dev_origin, allowed)
    refute NativeClientCors.socket_origin_allowed?(dev_origin, [])
    refute NativeClientCors.socket_origin_allowed?(URI.parse("http://127.0.0.1:1431"), allowed)
    refute NativeClientCors.socket_origin_allowed?(URI.parse("http://localhost:1430"), allowed)
    refute NativeClientCors.socket_origin_allowed?(URI.parse("https://attacker.example"), allowed)
  end
end
