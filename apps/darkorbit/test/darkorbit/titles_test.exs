defmodule Darkorbit.TitlesTest do
  use Darkorbit.DataCase

  alias Darkorbit.Titles

  describe "player_titles" do
    alias Darkorbit.Titles.PlayerTitle

    import Darkorbit.TitlesFixtures

    @invalid_attrs %{titles: nil}

    test "list_player_titles/0 returns all player_titles" do
      player_title = player_title_fixture()
      assert Titles.list_player_titles() == [player_title]
    end

    test "get_player_title!/1 returns the player_title with given id" do
      player_title = player_title_fixture()
      assert Titles.get_player_title!(player_title.id) == player_title
    end

    test "create_player_title/1 with valid data creates a player_title" do
      valid_attrs = %{titles: %{}}

      assert {:ok, %PlayerTitle{} = player_title} = Titles.create_player_title(valid_attrs)
      assert player_title.titles == %{}
    end

    test "create_player_title/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Titles.create_player_title(@invalid_attrs)
    end

    test "update_player_title/2 with valid data updates the player_title" do
      player_title = player_title_fixture()
      update_attrs = %{titles: %{}}

      assert {:ok, %PlayerTitle{} = player_title} = Titles.update_player_title(player_title, update_attrs)
      assert player_title.titles == %{}
    end

    test "update_player_title/2 with invalid data returns error changeset" do
      player_title = player_title_fixture()
      assert {:error, %Ecto.Changeset{}} = Titles.update_player_title(player_title, @invalid_attrs)
      assert player_title == Titles.get_player_title!(player_title.id)
    end

    test "delete_player_title/1 deletes the player_title" do
      player_title = player_title_fixture()
      assert {:ok, %PlayerTitle{}} = Titles.delete_player_title(player_title)
      assert_raise Ecto.NoResultsError, fn -> Titles.get_player_title!(player_title.id) end
    end

    test "change_player_title/1 returns a player_title changeset" do
      player_title = player_title_fixture()
      assert %Ecto.Changeset{} = Titles.change_player_title(player_title)
    end
  end
end
