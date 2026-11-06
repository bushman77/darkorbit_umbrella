defmodule Darkorbit.AccountsTest do
  use Darkorbit.DataCase

  import Darkorbit.AccountsFixtures

  alias Darkorbit.Accounts
  alias Darkorbit.Accounts.PlayerAccount
  alias Darkorbit.Fleet
  alias Darkorbit.Inventory
  alias Darkorbit.Loadouts
  alias Darkorbit.Preferences
  alias Darkorbit.Repo
  alias Darkorbit.Titles

  describe "register_account/1" do
    test "atomically provisions all starter state" do
      attrs = unique_account_attributes()

      assert {:ok, %PlayerAccount{} = account} = Accounts.register_account(attrs)
      assert account.username == attrs.username
      assert account.faction_id == 0
      assert account.ship_id == 1
      assert account.credits == 0
      assert account.uridium == 0
      assert account.level == 1
      assert account.password == nil
      assert Bcrypt.verify_pass(attrs.password, account.password_hash)

      assert Inventory.get_equipment_by_user_id(account.id)
      assert Preferences.get_setting_by_user_id(account.id)
      assert Titles.get_title_by_user_id(account.id)

      assert [starter_ship] = Fleet.list_ships_for_user(account.id)
      assert starter_ship.ship_id == 1
      assert Core.Ships.Catalog.fetch!(1).name == "Sunracer"

      assert [configuration_one, configuration_two] =
               Loadouts.list_loadouts_for_player_ship(starter_ship.id)

      assert configuration_one.config_no == 1
      assert configuration_two.config_no == 2
    end

    test "ignores client attempts to set authoritative state" do
      attrs =
        unique_account_attributes(%{
          credits: 99_999,
          uridium: 99_999,
          experience: 99_999,
          faction_id: 3,
          ship_id: 999,
          password_hash: "client-controlled"
        })

      assert {:ok, account} = Accounts.register_account(attrs)
      assert account.credits == 0
      assert account.uridium == 0
      assert account.experience == 0
      assert account.faction_id == 0
      assert account.ship_id == 1
      refute account.password_hash == "client-controlled"
    end

    test "returns a changeset and persists nothing for invalid input" do
      before_count = Repo.aggregate(PlayerAccount, :count)

      assert {:error, changeset} =
               Accounts.register_account(%{
                 username: "bad value",
                 email: "not-an-email",
                 pilot_name: "x",
                 password: "short"
               })

      refute changeset.valid?
      assert Repo.aggregate(PlayerAccount, :count) == before_count
    end

    test "rejects passwords longer than bcrypt's byte limit" do
      attrs = unique_account_attributes(%{password: String.duplicate("🚀", 19)})

      assert {:error, changeset} = Accounts.register_account(attrs)
      assert "should be at most 72 bytes" in errors_on(changeset).password
    end

    test "enforces unique identity fields" do
      attrs = unique_account_attributes()
      assert {:ok, _account} = Accounts.register_account(attrs)
      assert {:error, changeset} = Accounts.register_account(attrs)
      assert "has already been taken" in errors_on(changeset).username
    end
  end

  describe "authentication and onboarding" do
    test "requires verification, validates credentials, and rotates the session on login" do
      attrs = unique_account_attributes()
      account = player_account_fixture(attrs)

      assert {:error, :unverified} =
               Accounts.authenticate_by_username_and_password(attrs.username, attrs.password)

      assert {:error, :invalid_credentials} =
               Accounts.authenticate_by_username_and_password(attrs.username, "wrong-password")

      token = account.verification_token
      assert {:ok, verified} = Accounts.verify_account(account.id, token)
      assert verified.verification["verified"]
      assert {:error, :already_verified} = Accounts.verify_account(account.id, token)

      old_session_id = verified.session_id
      assert {:ok, logged_in} = Accounts.login_account(attrs.username, attrs.password)
      refute logged_in.session_id == old_session_id
    end

    test "verification tokens are hashed at rest, expire, and are single-use" do
      account = player_account_fixture()
      stored = Accounts.get_by_username(account.username)

      assert is_binary(account.verification_token)
      assert byte_size(stored.verification["hash"]) == 64
      refute stored.verification["hash"] == account.verification_token
      assert is_nil(stored.verification_token)
      assert {:error, :invalid_or_expired_token} =
               Accounts.verify_account(account.id, "wrong-token")

      expired =
        Map.put(stored.verification, "expires_at", System.system_time(:second) - 1)

      stored
      |> PlayerAccount.system_changeset(%{"verification" => expired})
      |> Repo.update!()

      assert {:error, :invalid_or_expired_token} =
               Accounts.verify_account(account.id, account.verification_token)

      assert {:ok, resent} = Accounts.request_verification_email(account.email)
      assert {:ok, verified} = Accounts.verify_account(account.id, resent.verification_token)
      assert verified.verification["verified"] == true
      refute Map.has_key?(verified.verification, "hash")
      assert {:error, :already_verified} =
               Accounts.verify_account(account.id, resent.verification_token)
    end

    test "resend rotates tokens, throttles repeat requests, and hides account existence" do
      account = player_account_fixture()
      old_token = account.verification_token

      assert {:ok, :ignored} =
               Accounts.request_verification_email("missing@example.test")

      assert {:ok, resent} = Accounts.request_verification_email(account.email)
      assert resent.verification_token != old_token

      assert {:error, :invalid_or_expired_token} =
               Accounts.verify_account(account.id, old_token)

      assert {:ok, :ignored} = Accounts.request_verification_email(account.email)
      assert Accounts.get_by_username(account.username).verification["resend_count"] == 1

      assert {:ok, _verified} =
               Accounts.verify_account(account.id, resent.verification_token)

      assert {:ok, :ignored} = Accounts.request_verification_email(account.email)
    end

    test "caps resend requests at five per rolling 24-hour window" do
      account = player_account_fixture()
      now = System.system_time(:second)

      for attempt <- 1..5 do
        if attempt > 1 do
          current = Accounts.get_by_username(account.username)
          record = Map.put(current.verification, "resend_requested_at", now - 61)

          current
          |> PlayerAccount.system_changeset(%{"verification" => record})
          |> Repo.update!()
        end

        assert {:ok, %PlayerAccount{}} =
                 Accounts.request_verification_email(account.email)
      end

      current = Accounts.get_by_username(account.username)
      record = Map.put(current.verification, "resend_requested_at", now - 61)

      current
      |> PlayerAccount.system_changeset(%{"verification" => record})
      |> Repo.update!()

      assert {:ok, :ignored} = Accounts.request_verification_email(account.email)
    end

    test "active loadout configuration persists, defaults to C-1 and rejects invalid choices" do
      account = player_account_fixture()
      assert Darkorbit.World.active_configuration(account.id) == 1
      assert {:error, :invalid_configuration} =
        Accounts.activate_configuration(account.id, 3)
      assert {:ok, _} = Accounts.activate_configuration(account.id, 2)
      assert Darkorbit.World.active_configuration(account.id) == 2
      assert {:ok, status} = Darkorbit.World.player_status(account.id,
        Darkorbit.World.active_configuration(account.id))
      assert status.configuration.number == 2
    end

    test "selects a company only once" do
      account = player_account_fixture()

      assert {:error, :invalid_company} = Accounts.select_company(account.id, "unknown")
      assert {:ok, selected} = Accounts.select_company(account.id, "eic")
      assert selected.faction_id == 2
      assert {:error, :already_selected} = Accounts.select_company(selected.id, "mmo")
    end
  end
end
