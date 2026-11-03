defmodule DarkorbitWeb.HelmetControllerTest do
  use DarkorbitWeb.ConnCase, async: false

  import Darkorbit.AccountsFixtures
  alias Darkorbit.Helmets

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
