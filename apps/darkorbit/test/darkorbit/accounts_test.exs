defmodule Darkorbit.AccountsTest do
  use Darkorbit.DataCase

  alias Darkorbit.Accounts

  describe "player_accounts" do
    alias Darkorbit.Accounts.PlayerAccount

    import Darkorbit.AccountsFixtures

    @invalid_attrs %{data: nil, username: nil, session_id: nil, verification: nil, email: nil, password_hash: nil, pilot_name: nil, faction_id: nil, clan_id: nil, old_pilot_names: nil}

    test "list_player_accounts/0 returns all player_accounts" do
      player_account = player_account_fixture()
      assert Accounts.list_player_accounts() == [player_account]
    end

    test "get_player_account!/1 returns the player_account with given id" do
      player_account = player_account_fixture()
      assert Accounts.get_player_account!(player_account.id) == player_account
    end

    test "create_player_account/1 with valid data creates a player_account" do
      valid_attrs = %{data: %{}, username: "some username", session_id: "some session_id", verification: %{}, email: "some email", password_hash: "some password_hash", pilot_name: "some pilot_name", faction_id: 42, clan_id: 42, old_pilot_names: %{}}

      assert {:ok, %PlayerAccount{} = player_account} = Accounts.create_player_account(valid_attrs)
      assert player_account.data == %{}
      assert player_account.username == "some username"
      assert player_account.session_id == "some session_id"
      assert player_account.verification == %{}
      assert player_account.email == "some email"
      assert player_account.password_hash == "some password_hash"
      assert player_account.pilot_name == "some pilot_name"
      assert player_account.faction_id == 42
      assert player_account.clan_id == 42
      assert player_account.old_pilot_names == %{}
    end

    test "create_player_account/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Accounts.create_player_account(@invalid_attrs)
    end

    test "update_player_account/2 with valid data updates the player_account" do
      player_account = player_account_fixture()
      update_attrs = %{data: %{}, username: "some updated username", session_id: "some updated session_id", verification: %{}, email: "some updated email", password_hash: "some updated password_hash", pilot_name: "some updated pilot_name", faction_id: 43, clan_id: 43, old_pilot_names: %{}}

      assert {:ok, %PlayerAccount{} = player_account} = Accounts.update_player_account(player_account, update_attrs)
      assert player_account.data == %{}
      assert player_account.username == "some updated username"
      assert player_account.session_id == "some updated session_id"
      assert player_account.verification == %{}
      assert player_account.email == "some updated email"
      assert player_account.password_hash == "some updated password_hash"
      assert player_account.pilot_name == "some updated pilot_name"
      assert player_account.faction_id == 43
      assert player_account.clan_id == 43
      assert player_account.old_pilot_names == %{}
    end

    test "update_player_account/2 with invalid data returns error changeset" do
      player_account = player_account_fixture()
      assert {:error, %Ecto.Changeset{}} = Accounts.update_player_account(player_account, @invalid_attrs)
      assert player_account == Accounts.get_player_account!(player_account.id)
    end

    test "delete_player_account/1 deletes the player_account" do
      player_account = player_account_fixture()
      assert {:ok, %PlayerAccount{}} = Accounts.delete_player_account(player_account)
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_player_account!(player_account.id) end
    end

    test "change_player_account/1 returns a player_account changeset" do
      player_account = player_account_fixture()
      assert %Ecto.Changeset{} = Accounts.change_player_account(player_account)
    end
  end
end
