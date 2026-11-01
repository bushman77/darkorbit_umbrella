defmodule Darkorbit.Titles do
  @moduledoc """
  Player title provisioning and ownership-scoped updates.
  """

  alias Darkorbit.Repo
  alias Darkorbit.Titles.PlayerTitle

  def get_title_by_user_id(user_id) when is_integer(user_id) do
    Repo.get_by(PlayerTitle, user_id: user_id)
  end

  def create_default_titles_for_account(user_id) when is_integer(user_id) do
    attrs = %{titles: %{"selected" => nil, "owned" => []}}

    %PlayerTitle{}
    |> PlayerTitle.creation_changeset(user_id, attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:user_id], returning: true)
    |> case do
      {:ok, %PlayerTitle{id: nil}} ->
        {:ok, Repo.get_by!(PlayerTitle, user_id: user_id)}

      result ->
        result
    end
  end

  def select_title(user_id, title) when is_integer(user_id) and is_binary(title) do
    case get_title_by_user_id(user_id) do
      %PlayerTitle{} = player_title ->
        titles = player_title.titles || %{}

        if title in Map.get(titles, "owned", []) do
          player_title
          |> PlayerTitle.titles_changeset(%{titles: Map.put(titles, "selected", title)})
          |> Repo.update()
        else
          {:error, :title_not_owned}
        end

      nil ->
        {:error, :titles_not_found}
    end
  end
end
