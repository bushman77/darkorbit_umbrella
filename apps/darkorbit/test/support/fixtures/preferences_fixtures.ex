defmodule Darkorbit.PreferencesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Darkorbit.Preferences` context.
  """

  @doc """
  Generate a player_setting.
  """
  def player_setting_fixture(attrs \\ %{}) do
    {:ok, player_setting} =
      attrs
      |> Enum.into(%{
        settings: %{}
      })
      |> Darkorbit.Preferences.create_player_setting()

    player_setting
  end
end
