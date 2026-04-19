defmodule Darkorbit.TitlesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Darkorbit.Titles` context.
  """

  @doc """
  Generate a player_title.
  """
  def player_title_fixture(attrs \\ %{}) do
    {:ok, player_title} =
      attrs
      |> Enum.into(%{
        titles: %{}
      })
      |> Darkorbit.Titles.create_player_title()

    player_title
  end
end
