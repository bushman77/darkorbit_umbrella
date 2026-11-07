defmodule DarkorbitWeb.HelmetControllerTest do
  use DarkorbitWeb.ConnCase, async: false

  import Darkorbit.AccountsFixtures
  alias Darkorbit.Helmets
  alias DarkorbitWeb.HelmetManager

  test "QR redemption persists registration before the viewer socket connects", %{conn: conn} do
    account = verified_player_account_fixture()
    assert {:ok, code} = HelmetManager.open_pairing(account.id)

    response =
      conn
      |> put_req_header("accept", "application/json")
      |> post("/helmet/pair", %{"code" => code, "device_name" => "Galaxy S21"})

    %{"credential" => credential} = json_response(response, 200)
    assert get_resp_header(response, "cache-control") == ["no-store"]
    assert {:ok, %{player_id: player_id}} = Helmets.authenticate(credential)
    assert player_id == account.id

    # The invitation is one-time, but the saved credential remains valid even
    # after the Atlas panel closes or the initial viewer WebSocket disconnects.
    :ok = HelmetManager.cancel_pairing(account.id)
    assert {:ok, _device} = Helmets.authenticate(credential)

    replay =
      Phoenix.ConnTest.build_conn()
      |> put_req_header("accept", "application/json")
      |> post("/helmet/pair", %{"code" => code, "device_name" => "second phone"})

    assert %{"error" => "invalid_pairing"} = json_response(replay, 410)
    assert {:ok, _device} = Helmets.authenticate(credential)
  end

  test "closed pairing invitation cannot register a phone", %{conn: conn} do
    account = verified_player_account_fixture()
    assert {:ok, code} = HelmetManager.open_pairing(account.id)
    :ok = HelmetManager.cancel_pairing(account.id)

    response =
      conn
      |> put_req_header("accept", "application/json")
      |> post("/helmet/pair", %{"code" => code})

    assert %{"error" => "invalid_pairing"} = json_response(response, 410)
    assert Helmets.device(account.id) == nil
  end

  test "valid remembered headset credential can be verified by the phone", %{conn: conn} do
    account = verified_player_account_fixture()
    assert {:ok, %{credential: credential}} = Helmets.register(account.id, "Galaxy S21")

    response =
      conn
      |> put_req_header("authorization", "Bearer " <> credential)
      |> put_req_header("accept", "application/json")
      |> post("/helmet/verify")

    assert %{"valid" => true} = json_response(response, 200)
    assert get_resp_header(response, "cache-control") == ["no-store"]
  end

  test "revoked or invalid credential is rejected without disclosing device details", %{conn: conn} do
    account = verified_player_account_fixture()
    assert {:ok, %{credential: credential}} = Helmets.register(account.id, "Galaxy S21")
    assert :ok = Helmets.forget(account.id)

    response =
      conn
      |> put_req_header("authorization", "Bearer " <> credential)
      |> put_req_header("accept", "application/json")
      |> post("/helmet/verify")

    assert %{"valid" => false} = json_response(response, 401)

    without_header =
      Phoenix.ConnTest.build_conn()
      |> put_req_header("accept", "application/json")
      |> post("/helmet/verify")

    assert %{"valid" => false} = json_response(without_header, 401)
  end
end
