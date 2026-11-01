defmodule Darkorbit.Accounts do
  @moduledoc """
  Account registration, authentication, and server-owned account lifecycle.

  Registration provisions the complete starter state in one database
  transaction. Player-controlled input is restricted to identity credentials.
  """

  import Ecto.Query, warn: false

  alias Darkorbit.Accounts.PlayerAccount
  alias Darkorbit.Fleet
  alias Darkorbit.Inventory
  alias Darkorbit.Preferences
  alias Darkorbit.Repo
  alias Darkorbit.Titles
  alias Ecto.Multi

  def list_player_accounts, do: Repo.all(PlayerAccount)

  def get_player_account!(id), do: Repo.get!(PlayerAccount, id)

  def get_by_username(username) when is_binary(username) do
    Repo.get_by(PlayerAccount, username: username)
  end

  def get_by_session_id(session_id) when is_binary(session_id) do
    Repo.get_by(PlayerAccount, session_id: session_id)
  end

  def get_player_accounts(ids) when is_list(ids) do
    ids = Enum.uniq(ids)

    from(account in PlayerAccount,
      where: account.id in ^ids,
      order_by: [asc: account.id]
    )
    |> Repo.all()
  end

  @doc """
  Registers an account and atomically provisions its inventory, settings,
  titles, starter ship, and both starter loadouts.
  """
  def register_account(attrs) when is_map(attrs) do
    account = %PlayerAccount{
      session_id: random_token(32),
      verification: %{"verified" => false, "hash" => random_token(16)}
    }

    Multi.new()
    |> Multi.insert(:player_account, PlayerAccount.registration_changeset(account, attrs))
    |> Multi.run(:player_ships, fn _repo, %{player_account: player_account} ->
      Fleet.create_starter_ships_for_account(player_account.id)
    end)
    |> Multi.run(:player_equipment, fn _repo, %{player_account: player_account} ->
      Inventory.create_default_equipment_for_account(player_account.id)
    end)
    |> Multi.run(:player_settings, fn _repo, %{player_account: player_account} ->
      Preferences.create_default_settings_for_account(player_account.id)
    end)
    |> Multi.run(:player_titles, fn _repo, %{player_account: player_account} ->
      Titles.create_default_titles_for_account(player_account.id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{player_account: player_account}} ->
        {:ok, %{player_account | password: nil}}

      {:error, :player_account, changeset, _changes_so_far} ->
        {:error, changeset}

      {:error, step, reason, _changes_so_far} ->
        {:error, {:provisioning_failed, step, reason}}
    end
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
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  def verify_account(user_id, hash) when is_integer(user_id) and is_binary(hash) do
    Repo.transaction(fn ->
      account = lock_account(user_id)

      if account do
        verify_locked_account(account, hash)
      else
        Repo.rollback(:not_found)
      end
    end)
  end

  def login_account(username, password)
      when is_binary(username) and is_binary(password) do
    with {:ok, %PlayerAccount{} = account} <-
           authenticate_by_username_and_password(username, password) do
      account
      |> PlayerAccount.system_changeset(%{"session_id" => random_token(32)})
      |> Repo.update()
    end
  end

  def logout_account(user_id, session_id)
      when is_integer(user_id) and is_binary(session_id) do
    case Repo.get_by(PlayerAccount, id: user_id, session_id: session_id) do
      %PlayerAccount{} = account ->
        account
        |> PlayerAccount.system_changeset(%{"session_id" => random_token(32)})
        |> Repo.update()

      nil ->
        {:error, :invalid_session}
    end
  end

  def select_company(user_id, company) when is_integer(user_id) and is_binary(company) do
    faction_id = Map.get(%{"mmo" => 1, "eic" => 2, "vru" => 3}, company)

    if is_nil(faction_id) do
      {:error, :invalid_company}
    else
      Repo.transaction(fn ->
        case lock_account(user_id) do
          nil ->
            Repo.rollback(:not_found)

          %PlayerAccount{faction_id: current_faction} when current_faction in [1, 2, 3] ->
            Repo.rollback(:already_selected)

          %PlayerAccount{} = account ->
            account
            |> PlayerAccount.system_changeset(%{"faction_id" => faction_id})
            |> Repo.update()
            |> case do
              {:ok, updated_account} -> updated_account
              {:error, changeset} -> Repo.rollback(changeset)
            end
        end
      end)
    end
  end

  defp verify_locked_account(account, hash) do
    verification = account.verification || %{}

    cond do
      verification["verified"] == true ->
        Repo.rollback(:already_verified)

      verification["hash"] != hash ->
        Repo.rollback(:invalid_hash)

      true ->
        account
        |> PlayerAccount.system_changeset(%{
          "verification" => Map.put(verification, "verified", true)
        })
        |> Repo.update()
        |> case do
          {:ok, verified_account} -> verified_account
          {:error, changeset} -> Repo.rollback(changeset)
        end
    end
  end

  defp lock_account(user_id) do
    from(account in PlayerAccount, where: account.id == ^user_id, lock: "FOR UPDATE")
    |> Repo.one()
  end

  defp random_token(bytes) do
    bytes
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end
end
