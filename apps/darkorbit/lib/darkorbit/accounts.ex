defmodule Darkorbit.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Darkorbit.Repo

  alias Darkorbit.Accounts.PlayerAccount
  alias Darkorbit.Fleet

  @doc """
  Returns the list of player_accounts.

  ## Examples

      iex> list_player_accounts()
      [%PlayerAccount{}, ...]

  """
  def list_player_accounts do
    Repo.all(PlayerAccount)
  end

  @doc """
  Gets a single player_account.

  Raises `Ecto.NoResultsError` if the Player account does not exist.

  ## Examples

      iex> get_player_account!(123)
      %PlayerAccount{}

      iex> get_player_account!(456)
      ** (Ecto.NoResultsError)

  """
  def get_player_account!(id), do: Repo.get!(PlayerAccount, id)

  def register_account(attrs) do
    alias Ecto.Multi
    alias Darkorbit.Inventory
    alias Darkorbit.Preferences
    alias Darkorbit.Titles

    verification = %{
      "verified" => false,
      "hash" => :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    }

    data = %{}

    session_id =
      :crypto.strong_rand_bytes(32)
      |> Base.encode16(case: :lower)

    attrs =
      attrs
      |> Map.put("password_hash", Bcrypt.hash_pwd_salt(attrs["password"]))
      |> Map.put("verification", verification)
      |> Map.put("data", data)
      |> Map.put("session_id", session_id)
      |> Map.put("faction_id", 0)
      |> Map.put("clan_id", 0)
      |> Map.put("old_pilot_names", %{"history" => []})
      |> Map.put("ship_id", 1)
      |> Map.put("rank_id", 1)
      |> Map.put("experience", 0)
      |> Map.put("honor", 0)
      |> Map.put("credits", 0)
      |> Map.put("uridium", 0)
      |> Map.put("level", 1)
      |> Map.put("version", "live")

    Multi.new()
    |> Multi.insert(
      :player_account,
      PlayerAccount.changeset(%PlayerAccount{}, attrs)
    )
    |> Multi.run(:player_ships, fn _repo, %{player_account: account} ->
      Fleet.create_starter_ships_for_account(account.id)
    end)
    |> Multi.run(:player_equipment, fn _repo, %{player_account: account} ->
      Inventory.create_default_equipment_for_account(account.id)
    end)
    |> Multi.run(:player_settings, fn _repo, %{player_account: account} ->
      Preferences.create_default_settings_for_account(account.id)
    end)
    |> Multi.run(:player_titles, fn _repo, %{player_account: account} ->
      Titles.create_default_titles_for_account(account.id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok,
       %{
         player_account: account,
         player_equipment: _equipment,
         player_settings: _settings,
         player_titles: _titles
       }} ->
        {:ok, account}

      {:error, :player_account, changeset, _changes_so_far} ->
        {:error, changeset}

      {:error, _step, reason, _changes_so_far} ->
        {:error, reason}
    end
  end

  def get_by_username(username) when is_binary(username) do
    Repo.get_by(PlayerAccount, username: username)
  end

  @doc """
  Updates a player_account.

  ## Examples

      iex> update_player_account(player_account, %{field: new_value})
      {:ok, %PlayerAccount{}}

      iex> update_player_account(player_account, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_player_account(%PlayerAccount{} = player_account, attrs) do
    player_account
    |> PlayerAccount.changeset(attrs)
    |> Repo.update()
  end

  def authenticate_by_username_and_password(username, password)
      when is_binary(username) and is_binary(password) do
    case get_by_username(username) do
      %PlayerAccount{} = account ->
        cond do
          not Bcrypt.verify_pass(password, account.password_hash) ->
            {:error, :invalid_credentials}

          get_in(account.verification, ["verified"]) != true ->
            {:error, :unverified}

          true ->
            {:ok, account}
        end

      nil ->
        {:error, :invalid_credentials}
    end
  end

  def verify_account(user_id, hash) when is_integer(user_id) and is_binary(hash) do
    case Repo.get(PlayerAccount, user_id) do
      %PlayerAccount{} = account ->
        verification = account.verification || %{}

        cond do
          verification["verified"] == true ->
            {:error, :already_verified}

          verification["hash"] != hash ->
            {:error, :invalid_hash}

          true ->
            new_verification =
              verification
              |> Map.put("verified", true)

            account
            |> PlayerAccount.changeset(%{"verification" => new_verification})
            |> Repo.update()
        end

      nil ->
        {:error, :not_found}
    end
  end

  def login_account(username, password)
      when is_binary(username) and is_binary(password) do
    case authenticate_by_username_and_password(username, password) do
      {:ok, %PlayerAccount{} = account} ->
        new_session_id =
          :crypto.strong_rand_bytes(32)
          |> Base.encode16(case: :lower)

        account
        |> PlayerAccount.changeset(%{"session_id" => new_session_id})
        |> Repo.update()

      {:error, reason} ->
        {:error, reason}
    end
  end

  def select_company(%PlayerAccount{} = account, company) when is_binary(company) do
    faction_id =
      case company do
        "mmo" -> 1
        "eic" -> 2
        "vru" -> 3
        _ -> nil
      end

    cond do
      faction_id == nil ->
        {:error, :invalid_company}

      account.faction_id in [1, 2, 3] ->
        {:error, :already_selected}

      true ->
        account
        |> PlayerAccount.changeset(%{"faction_id" => faction_id})
        |> Repo.update()
    end
  end
end
