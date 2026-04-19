defmodule Darkorbit.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Darkorbit.Accounts` context.
  """

  @doc """
  Generate a player_account.
  """
  def player_account_fixture(attrs \\ %{}) do
    {:ok, player_account} =
      attrs
      |> Enum.into(%{
        clan_id: 42,
        data: %{},
        email: "some email",
        faction_id: 42,
        old_pilot_names: %{},
        password_hash: "some password_hash",
        pilot_name: "some pilot_name",
        session_id: "some session_id",
        username: "some username",
        verification: %{}
      })
      |> Darkorbit.Accounts.create_player_account()

    player_account
  end
end
