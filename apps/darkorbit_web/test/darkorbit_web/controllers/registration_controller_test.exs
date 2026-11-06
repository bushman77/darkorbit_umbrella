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

      [token] =
        Regex.run(~r/token=([a-zA-Z0-9_-]+)/, email.text_body,
          capture: :all_but_first
        )

      refute account.verification["hash"] == token

      assert {:error, :unverified} =
               Accounts.authenticate_by_username_and_password(attrs.username, attrs.password)

      pending =
        get(build_conn(), ~p"/verify-account?#{%{id: account.id, token: token}}")

      assert html_response(pending, 200) =~ ~s(id="pilot-verification-form")
      assert Accounts.get_by_username(attrs.username).verification["verified"] == false

      verified =
        post(build_conn(), ~p"/verify-account", %{
          "verification" => %{"id" => Integer.to_string(account.id), "token" => token}
        })

      assert redirected_to(verified) == ~p"/login"
      assert Accounts.get_by_username(attrs.username).verification["verified"] == true
    end)

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
    assert html =~ ~s(value="bad user")
    assert html =~ ~s(name="registration[password]" id="registration_password" value="")
    refute html =~ "private-DO-NOT-ECHO"
    assert Accounts.get_by_username("bad user") == nil
  end

  test "duplicate registration never reflects a submitted password", %{conn: conn} do
    attrs = unique_account_attributes()
    player_account_fixture(attrs)

    attempted_password = "duplicate-SECRET-DO-NOT-ECHO"

    conn =
      post(conn, ~p"/register", %{
        "registration" => Map.put(attrs, :password, attempted_password)
      })

    html = html_response(conn, 422)
    assert html =~ ~s(id="pilot-registration-form")
    assert html =~ "has already been taken"
    assert html =~ ~s(name="registration[password]" id="registration_password" value="")
    refute html =~ attempted_password
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

    forged = get(conn, ~p"/verify-account?#{%{id: account.id, token: "forged"}}")
    assert html_response(forged, 200) =~ ~s(id="pilot-confirm-button")
    assert Accounts.get_by_username(attrs.username).verification["verified"] == false

    malformed = get(build_conn(), ~p"/verify-account?id=invalid&token=forged")
    assert html_response(malformed, 200) =~ ~s(id="pilot-confirm-button")
  end

  test "GET verification links do not activate an account, and invalid POSTs are rejected", %{conn: conn} do
    account = player_account_fixture()
    token = account.verification_token

    conn = get(conn, ~p"/verify-account?#{%{id: account.id, token: token}}")
    assert html_response(conn, 200) =~ ~s(id="pilot-confirm-button")
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
    assert Accounts.get_by_username(account.username).verification["verified"] == false

    invalid =
      post(build_conn(), ~p"/verify-account", %{
        "verification" => %{"id" => Integer.to_string(account.id), "token" => "forged"}
      })

    assert redirected_to(invalid) == ~p"/register/resend"
    assert Accounts.get_by_username(account.username).verification["verified"] == false
  end

  test "resend offers a neutral public response, rotates the token, and throttles retries", %{conn: conn} do
    account = player_account_fixture()

    page = get(conn, ~p"/register/resend")
    assert html_response(page, 200) =~ ~s(id="pilot-resend-form")

    requested =
      post(build_conn(), ~p"/register/resend", %{
        "resend" => %{"email" => account.email}
      })

    assert redirected_to(requested) == ~p"/register/success"
    assert_email_sent(fn email ->
      assert email.to != []
      assert email.text_body =~ "/verify-account?"
    end)

    first_hash = Accounts.get_by_username(account.username).verification["hash"]
    assert first_hash != account.verification["hash"]

    throttled =
      post(build_conn(), ~p"/register/resend", %{
        "resend" => %{"email" => account.email}
      })

    assert redirected_to(throttled) == ~p"/register/success"
    assert Accounts.get_by_username(account.username).verification["hash"] == first_hash

    missing =
      post(build_conn(), ~p"/register/resend", %{
        "resend" => %{"email" => "no-such-pilot@example.test"}
      })

    assert redirected_to(missing) == ~p"/register/success"
  end

  test "failed email delivery leaves a recoverable unverified account", %{conn: conn} do
    original = Application.get_env(:darkorbit_web, :registration_mailer)

    on_exit(fn ->
      if original do
        Application.put_env(:darkorbit_web, :registration_mailer, original)
      else
        Application.delete_env(:darkorbit_web, :registration_mailer)
      end
    end)

    Application.put_env(
      :darkorbit_web,
      :registration_mailer,
      DarkorbitWeb.FailingRegistrationMailer
    )

    attrs = unique_account_attributes()
    response = post(conn, ~p"/register", %{"registration" => attrs})
    assert redirected_to(response) == ~p"/register/success"

    account = Accounts.get_by_username(attrs.username)
    assert account.verification["verified"] == false
    assert [starter_ship] = Fleet.list_ships_for_user(account.id)
    assert starter_ship.ship_id == 1

    Application.delete_env(:darkorbit_web, :registration_mailer)

    retry =
      post(build_conn(), ~p"/register/resend", %{
        "resend" => %{"email" => attrs.email}
      })

    assert redirected_to(retry) == ~p"/register/success"
    assert_email_sent(fn email ->
      assert email.text_body =~ "/verify-account?"
    end)
  end

  test "legacy unverified tokens without expiry must be replaced by resend" do
    account = player_account_fixture()
    legacy = %{"verified" => false, "hash" => "legacy-plaintext"}

    account
    |> Darkorbit.Accounts.PlayerAccount.system_changeset(%{"verification" => legacy})
    |> Darkorbit.Repo.update!()

    assert {:error, :invalid_or_expired_token} =
             Accounts.verify_account(account.id, "legacy-plaintext")

    assert {:ok, resent} = Accounts.request_verification_email(account.email)
    assert {:ok, _verified} =
             Accounts.verify_account(account.id, resent.verification_token)
  end
end

defmodule DarkorbitWeb.FailingRegistrationMailer do
  @moduledoc false
  def deliver(_email), do: {:error, :simulated_mail_failure}
end
