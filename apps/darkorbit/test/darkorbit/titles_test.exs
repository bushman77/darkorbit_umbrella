defmodule Darkorbit.TitlesTest do
  use Darkorbit.DataCase

  import Darkorbit.AccountsFixtures

  alias Darkorbit.Titles

  test "default title state is provisioned idempotently" do
    account = player_account_fixture()
    original = Titles.get_title_by_user_id(account.id)

    assert original.titles == %{"selected" => nil, "owned" => []}
    assert {:ok, same_titles} = Titles.create_default_titles_for_account(account.id)
    assert same_titles.id == original.id
  end

  test "cannot select a title the account does not own" do
    account = player_account_fixture()

    assert {:error, :title_not_owned} = Titles.select_title(account.id, "veteran")
    assert Titles.get_title_by_user_id(account.id).titles["selected"] == nil
  end
end
