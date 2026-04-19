defmodule Darkorbit.Titles do
  @moduledoc """
  The Titles context.
  """

  import Ecto.Query, warn: false
  alias Darkorbit.Repo

  alias Darkorbit.Titles.PlayerTitle

  @doc """
  Returns the list of player_titles.

  ## Examples

      iex> list_player_titles()
      [%PlayerTitle{}, ...]

  """
  def list_player_titles do
    Repo.all(PlayerTitle)
  end

  @doc """
  Gets a single player_title.

  Raises `Ecto.NoResultsError` if the Player title does not exist.

  ## Examples

      iex> get_player_title!(123)
      %PlayerTitle{}

      iex> get_player_title!(456)
      ** (Ecto.NoResultsError)

  """
  def get_player_title!(id), do: Repo.get!(PlayerTitle, id)

  @doc """
  Creates a player_title.

  ## Examples

      iex> create_player_title(%{field: value})
      {:ok, %PlayerTitle{}}

      iex> create_player_title(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_player_title(attrs) do
    %PlayerTitle{}
    |> PlayerTitle.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a player_title.

  ## Examples

      iex> update_player_title(player_title, %{field: new_value})
      {:ok, %PlayerTitle{}}

      iex> update_player_title(player_title, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_player_title(%PlayerTitle{} = player_title, attrs) do
    player_title
    |> PlayerTitle.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a player_title.

  ## Examples

      iex> delete_player_title(player_title)
      {:ok, %PlayerTitle{}}

      iex> delete_player_title(player_title)
      {:error, %Ecto.Changeset{}}

  """
  def delete_player_title(%PlayerTitle{} = player_title) do
    Repo.delete(player_title)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking player_title changes.

  ## Examples

      iex> change_player_title(player_title)
      %Ecto.Changeset{data: %PlayerTitle{}}

  """
  def change_player_title(%PlayerTitle{} = player_title, attrs \\ %{}) do
    PlayerTitle.changeset(player_title, attrs)
  end

  def get_title_by_user_id(user_id) when is_integer(user_id) do
    Repo.get_by(PlayerTitle, user_id: user_id)
  end

  def create_default_titles_for_account(user_id) when is_integer(user_id) do
    case get_title_by_user_id(user_id) do
      %PlayerTitle{} = title ->
        {:ok, title}

      nil ->
        titles = %{
          "selected" => nil,
          "owned" => []
        }

        %PlayerTitle{}
        |> PlayerTitle.changeset(%{
          "user_id" => user_id,
          "titles" => titles
        })
        |> Repo.insert()
    end
  end
end
