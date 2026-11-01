defmodule DarkorbitWeb.SessionControllerTest do
  use DarkorbitWeb.ConnCase

  import Darkorbit.AccountsFixtures

  test "the game route requires an authenticated pilot", %{conn: conn} do
    conn = get(conn, ~p"/play")

    assert redirected_to(conn) == ~p"/login"
  end

  test "a verified pilot can sign in, launch the client, and sign out", %{conn: conn} do
    password = "sector-access-123"

    account =
      verified_player_account_fixture(%{
        username: "channel_pilot_#{System.unique_integer([:positive])}",
        password: password
      })

    conn =
      post(conn, ~p"/login", %{
        "session" => %{"username" => account.username, "password" => password}
      })

    assert redirected_to(conn) == ~p"/play"

    conn = get(conn, ~p"/play")
    response = html_response(conn, 200)
    assert response =~ ~s(id="game-client")
    assert response =~ ~s(id="space-viewport")
    assert response =~ ~s(data-map-id="1-1")

    conn = delete(conn, ~p"/logout")
    assert redirected_to(conn) == ~p"/login"

    conn = get(conn, ~p"/play")
    assert redirected_to(conn) == ~p"/login"
  end

  test "invalid credentials do not create a browser session", %{conn: conn} do
    conn =
      post(conn, ~p"/login", %{
        "session" => %{"username" => "missing-pilot", "password" => "wrong-password"}
      })

    assert html_response(conn, 422) =~ ~s(id="pilot-login-form")
    assert get_session(conn, :player_id) == nil
  end
end
