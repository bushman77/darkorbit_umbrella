defmodule DarkorbitWeb.RegistrationControllerTest do
  use DarkorbitWeb.ConnCase

  import Darkorbit.AccountsFixtures
  import Swoosh.TestAssertions

  alias Darkorbit.Accounts
  alias Darkorbit.Fleet

  test "GET /register offers signup to visitors", %{conn: conn} do
    conn = get(conn, ~p"/register")
    html = html_response(conn, 200)
    assert html =~ ~s(id="registration-page")
    assert html =~ ~s(id="pilot-registration-form")
    assert html =~ ~s(id="pilot-register-button")
    assert html =~ "Create your pilot account."
  end

  test "signup creates an unverified account with starter ship and sends confirmation", %{conn: conn} do
    attrs = unique_account_attributes()
    conn = post(conn, ~p"/register", %{"registration" => attrs})

    assert redirected_to(conn) == ~p"/register/success"
    account = Accounts.get_by_username(attrs.username)
    assert account
    assert account.verification["verified"] == false
    assert [starter_ship] = Fleet.list_ships_for_user(account.id)
    assert starter_ship.ship_id == 1

    assert_email_sent(fn email ->
      assert email.subject == "Confirm your Space Nova pilot account"
      assert email.text_body =~ "/verify-account?"
      assert email.text_body =~ "token="
      assert email.text_body =~ account.verification["hash"]
    end)

    assert {:error, :unverified} =
      Accounts.authenticate_by_username_and_password(attrs.username, attrs.password)

    token = account.verification["hash"]
    verified = get(build_conn(), ~p"/verify-account?#{%{id: account.id, token: token}}")
    assert redirected_to(verified) == ~p"/login"
    assert Accounts.get_by_username(attrs.username).verification["verified"] == true

    login =
      post(build_conn(), ~p"/login", %{
        "session" => %{"username" => attrs.username, "password" => attrs.password}
      })
    assert redirected_to(login) == ~p"/play"
  end

  test "rejected fields never echo the password into rendered HTML", %{conn: conn} do
    attrs = unique_account_attributes(%{username: "bad user", password: "private-DO-NOT-ECHO"})
    conn = post(conn, ~p"/register", %{"registration" => attrs})
    html = html_response(conn, 422)

    assert html =~ ~s(id="pilot-registration-form")
    refute html =~ "private-DO-NOT-ECHO"
    assert Accounts.get_by_username("bad user") == nil
  end

  test "public signup ignores client-controlled ship and progression fields", %{conn: conn} do
    attrs =
      unique_account_attributes(%{
        ship_id: 999, credits: 100_000,
        faction_id: 3, verification: %{"verified" => true}
      })

    assert redirected_to(post(conn, ~p"/register", %{"registration" => attrs})) ==
             ~p"/register/success"

    account = Accounts.get_by_username(attrs.username)
    assert account.ship_id == 1
    assert account.credits == 0
    assert account.faction_id == 0
    assert account.verification["verified"] == false
  end

  test "invalid verification links never activate a pilot", %{conn: conn} do
    attrs = unique_account_attributes()
    account = player_account_fixture(attrs)

    assert redirected_to(get(conn, ~p"/verify-account?#{%{id: account.id, token: "forged"}}")) ==
             ~p"/login"
    assert Accounts.get_by_username(attrs.username).verification["verified"] == false

    assert redirected_to(get(build_conn(), ~p"/verify-account?id=invalid&token=forged")) ==
             ~p"/login"
  end
end
