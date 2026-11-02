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
    document = LazyHTML.from_document(response)

    assert Enum.count(
             LazyHTML.query(
               document,
               "#game-client[data-map-id='1-1'][data-layout-player-id='#{account.id}']"
             )
           ) == 1

    assert Enum.count(LazyHTML.query(document, "#space-viewport[tabindex='0']")) == 1
    assert Enum.count(LazyHTML.query(document, "#action-hotbar")) == 1

    assert Enum.count(
             LazyHTML.query(
               document,
               "#hotbar-slot-1[data-action-id='x1_laser'][data-action-type='ammunition'][data-activation-mode='toggle']"
             )
           ) == 1

    assert Enum.count(LazyHTML.query(document, "#hotbar-slot-10")) == 1
    # The old target-info window was retired; the active cockpit HUD has
    # ship-status and minimap windows. The Solar Atlas is now the entry view.
    assert Enum.count(LazyHTML.query(document, "[data-cockpit-window]")) == 2
    assert Enum.count(LazyHTML.query(document, "[data-cockpit-window='ship_status']")) == 1
    assert Enum.count(LazyHTML.query(document, "[data-cockpit-window='minimap']")) == 1
    assert Enum.count(LazyHTML.query(document, "#navigation-computer")) == 1
    assert Enum.count(LazyHTML.query(document, "#nav-solar-view")) == 1
    assert Enum.count(LazyHTML.query(document, "#nav-solar-engage")) == 1
    assert Enum.count(LazyHTML.query(document, "#cockpit-minimap-canvas")) == 1
    assert Enum.count(LazyHTML.query(document, "#minimap-decrease")) == 1
    assert Enum.count(LazyHTML.query(document, "#minimap-increase")) == 1
    assert Enum.count(LazyHTML.query(document, "#cockpit-lock-toggle")) == 1
    assert Enum.count(LazyHTML.query(document, "#cockpit-reset-layout")) == 1

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
