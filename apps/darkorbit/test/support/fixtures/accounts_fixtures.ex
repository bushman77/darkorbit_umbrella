defmodule Darkorbit.AccountsFixtures do
  @moduledoc false

  def unique_account_attributes(attrs \\ %{}) do
    unique = System.unique_integer([:positive, :monotonic])

    Map.merge(
      %{
        username: "user#{unique}",
        email: "user#{unique}@example.test",
        pilot_name: "pilot#{unique}",
        password: "valid-password-#{unique}"
      },
      attrs
    )
  end

  def player_account_fixture(attrs \\ %{}) do
    {:ok, player_account} =
      attrs
      |> unique_account_attributes()
      |> Darkorbit.Accounts.register_account()

    player_account
  end

  def verified_player_account_fixture(attrs \\ %{}) do
    player_account = player_account_fixture(attrs)
    hash = get_in(player_account.verification, ["hash"])
    {:ok, verified_account} = Darkorbit.Accounts.verify_account(player_account.id, hash)
    verified_account
  end
end
