defmodule Darkorbit.PreferencesTest do
  use Darkorbit.DataCase

  alias Darkorbit.Preferences

  describe "player_settings" do
    alias Darkorbit.Preferences.PlayerSetting

    import Darkorbit.PreferencesFixtures

    @invalid_attrs %{settings: nil}

    test "list_player_settings/0 returns all player_settings" do
      player_setting = player_setting_fixture()
      assert Preferences.list_player_settings() == [player_setting]
    end

    test "get_player_setting!/1 returns the player_setting with given id" do
      player_setting = player_setting_fixture()
      assert Preferences.get_player_setting!(player_setting.id) == player_setting
    end

    test "create_player_setting/1 with valid data creates a player_setting" do
      valid_attrs = %{settings: %{}}

      assert {:ok, %PlayerSetting{} = player_setting} = Preferences.create_player_setting(valid_attrs)
      assert player_setting.settings == %{}
    end

    test "create_player_setting/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Preferences.create_player_setting(@invalid_attrs)
    end

    test "update_player_setting/2 with valid data updates the player_setting" do
      player_setting = player_setting_fixture()
      update_attrs = %{settings: %{}}

      assert {:ok, %PlayerSetting{} = player_setting} = Preferences.update_player_setting(player_setting, update_attrs)
      assert player_setting.settings == %{}
    end

    test "update_player_setting/2 with invalid data returns error changeset" do
      player_setting = player_setting_fixture()
      assert {:error, %Ecto.Changeset{}} = Preferences.update_player_setting(player_setting, @invalid_attrs)
      assert player_setting == Preferences.get_player_setting!(player_setting.id)
    end

    test "delete_player_setting/1 deletes the player_setting" do
      player_setting = player_setting_fixture()
      assert {:ok, %PlayerSetting{}} = Preferences.delete_player_setting(player_setting)
      assert_raise Ecto.NoResultsError, fn -> Preferences.get_player_setting!(player_setting.id) end
    end

    test "change_player_setting/1 returns a player_setting changeset" do
      player_setting = player_setting_fixture()
      assert %Ecto.Changeset{} = Preferences.change_player_setting(player_setting)
    end
  end
end
