defmodule Darkorbit.Preferences do
  @moduledoc """
  Player preference provisioning and ownership-scoped updates.
  """

  alias Darkorbit.Preferences.PlayerSetting
  alias Darkorbit.Repo

  def get_setting_by_user_id(user_id) when is_integer(user_id) do
    Repo.get_by(PlayerSetting, user_id: user_id)
  end

  def create_default_settings_for_account(user_id) when is_integer(user_id) do
    %PlayerSetting{}
    |> PlayerSetting.creation_changeset(user_id, %{settings: %{"version" => "live"}})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:user_id], returning: true)
    |> case do
      {:ok, %PlayerSetting{id: nil}} ->
        {:ok, Repo.get_by!(PlayerSetting, user_id: user_id)}

      result ->
        result
    end
  end

  def update_settings(user_id, settings) when is_integer(user_id) and is_map(settings) do
    case get_setting_by_user_id(user_id) do
      %PlayerSetting{} = player_setting ->
        player_setting
        |> PlayerSetting.settings_changeset(%{settings: settings})
        |> Repo.update()

      nil ->
        {:error, :settings_not_found}
    end
  end
end
