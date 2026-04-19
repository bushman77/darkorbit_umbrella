defmodule Darkorbit.Preferences do
  @moduledoc """
  The Preferences context.
  """

  import Ecto.Query, warn: false
  alias Darkorbit.Repo

  alias Darkorbit.Preferences.PlayerSetting

  @doc """
  Returns the list of player_settings.

  ## Examples

      iex> list_player_settings()
      [%PlayerSetting{}, ...]

  """
  def list_player_settings do
    Repo.all(PlayerSetting)
  end

  @doc """
  Gets a single player_setting.

  Raises `Ecto.NoResultsError` if the Player setting does not exist.

  ## Examples

      iex> get_player_setting!(123)
      %PlayerSetting{}

      iex> get_player_setting!(456)
      ** (Ecto.NoResultsError)

  """
  def get_player_setting!(id), do: Repo.get!(PlayerSetting, id)

  @doc """
  Creates a player_setting.

  ## Examples

      iex> create_player_setting(%{field: value})
      {:ok, %PlayerSetting{}}

      iex> create_player_setting(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_player_setting(attrs) do
    %PlayerSetting{}
    |> PlayerSetting.changeset(attrs)
    |> Repo.insert()
  end

  def get_setting_by_user_id(user_id) when is_integer(user_id) do
    Repo.get_by(PlayerSetting, user_id: user_id)
  end

  def create_default_settings_for_account(user_id) when is_integer(user_id) do
    case get_setting_by_user_id(user_id) do
      %PlayerSetting{} = setting ->
        {:ok, setting}

      nil ->
        settings = %{
          "version" => "live"
        }

        %PlayerSetting{}
        |> PlayerSetting.changeset(%{
          "user_id" => user_id,
          "settings" => settings
        })
        |> Repo.insert()
    end
  end

  @doc """
  Updates a player_setting.

  ## Examples

      iex> update_player_setting(player_setting, %{field: new_value})
      {:ok, %PlayerSetting{}}

      iex> update_player_setting(player_setting, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_player_setting(%PlayerSetting{} = player_setting, attrs) do
    player_setting
    |> PlayerSetting.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a player_setting.

  ## Examples

      iex> delete_player_setting(player_setting)
      {:ok, %PlayerSetting{}}

      iex> delete_player_setting(player_setting)
      {:error, %Ecto.Changeset{}}

  """
  def delete_player_setting(%PlayerSetting{} = player_setting) do
    Repo.delete(player_setting)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking player_setting changes.

  ## Examples

      iex> change_player_setting(player_setting)
      %Ecto.Changeset{data: %PlayerSetting{}}

  """
  def change_player_setting(%PlayerSetting{} = player_setting, attrs \\ %{}) do
    PlayerSetting.changeset(player_setting, attrs)
  end
end
