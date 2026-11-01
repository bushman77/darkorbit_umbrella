defmodule Darkorbit.PreferencesTest do
  use Darkorbit.DataCase

  import Darkorbit.AccountsFixtures

  alias Darkorbit.Preferences

  test "default settings are provisioned idempotently" do
    account = player_account_fixture()
    original = Preferences.get_setting_by_user_id(account.id)

    assert original.settings == %{"version" => "live"}
    assert {:ok, same_setting} = Preferences.create_default_settings_for_account(account.id)
    assert same_setting.id == original.id
  end

  test "updates are scoped by the owning account id" do
    account = player_account_fixture()
    other_account = player_account_fixture()

    assert {:ok, updated} =
             Preferences.update_settings(account.id, %{
               "version" => "live",
               "show_minimap" => false
             })

    refute updated.settings["show_minimap"]
    assert Preferences.get_setting_by_user_id(other_account.id).settings == %{"version" => "live"}
  end
end
