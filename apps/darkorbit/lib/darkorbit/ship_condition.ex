defmodule Darkorbit.ShipCondition do
  @moduledoc """
  Durable owner of player ship combat condition.

  Condition updates use a database row lock and accept only verified,
  non-healing server snapshots. The unique player_ship_id identifies a
  physical hull regardless of pilot session or loadout configuration.
  """

  import Ecto.Query, warn: false

  alias Core.Ships.Condition
  alias Darkorbit.Fleet.PlayerShip
  alias Darkorbit.Fleet.PlayerShipCondition
  alias Darkorbit.Repo

  @fields [:hull, :max_hull, :shields, :max_shields, :status]

  @spec load_or_initialize(pos_integer(), pos_integer(), map()) ::
          {:ok, Condition.t()} | {:error, term()}
  def load_or_initialize(player_id, ship_instance_id, stats) do
    Repo.transaction(fn ->
      ensure_owned!(player_id, ship_instance_id)

      case condition_row(ship_instance_id) do
        nil ->
          {:ok, initial} = require_condition!(Condition.initial(stats))
          initial
          |> new_record(ship_instance_id)
          |> persist!()
          |> as_condition()

        existing ->
          {:ok, revised} = require_condition!(Condition.rebase(as_condition(existing), stats))
          if revised == as_condition(existing) do
            revised
          else
            existing
            |> Ecto.Changeset.change(Map.put(revised, :revision, existing.revision + 1))
            |> persist!()
            |> as_condition()
          end
      end
    end)
  end

  @doc "Persist a map-owned combat report; identical retries are safe."
  @spec save_verified(pos_integer(), pos_integer(), map()) :: :ok | {:error, term()}
  def save_verified(player_id, ship_instance_id, combat) do
    case Repo.transaction(fn ->
      ensure_owned!(player_id, ship_instance_id)

      case condition_row(ship_instance_id) do
        nil ->
          Repo.rollback(:ship_condition_missing)

        existing ->
          {:ok, updated} =
            require_condition!(Condition.reconcile(as_condition(existing), combat))

          if updated != as_condition(existing) do
            existing
            |> Ecto.Changeset.change(Map.put(updated, :revision, existing.revision + 1))
            |> persist!()
          end

          :ok
      end
    end) do
      {:ok, :ok} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Repair a server-verified destroyed physical hull during an explicit
  respawn. The authenticated World layer verifies map-owned death first.
  The row lock prevents duplicate resurrection or an unrelated repair.
  """
  @spec repair_for_respawn(pos_integer(), pos_integer(), map()) ::
          {:ok, Condition.t()} | {:error, term()}
  def repair_for_respawn(player_id, ship_instance_id, stats) do
    Repo.transaction(fn ->
      ensure_owned!(player_id, ship_instance_id)

      case condition_row(ship_instance_id) do
        nil ->
          Repo.rollback(:ship_condition_missing)

        existing ->
          if existing.status != :destroyed do
            Repo.rollback(:ship_not_destroyed)
          else
            {:ok, restored} = require_condition!(Condition.initial(stats))

            existing
            |> Ecto.Changeset.change(Map.put(restored, :revision, existing.revision + 1))
            |> persist!()

            restored
          end
      end
    end)
  end

  defp ensure_owned!(player_id, ship_instance_id) do
    query =
      from(ship in PlayerShip,
        where: ship.id == ^ship_instance_id and ship.user_id == ^player_id,
        lock: "FOR UPDATE"
      )

    if Repo.one(query) == nil, do: Repo.rollback(:ship_not_owned)
  end

  defp condition_row(ship_instance_id) do
    from(row in PlayerShipCondition,
      where: row.player_ship_id == ^ship_instance_id,
      lock: "FOR UPDATE"
    )
    |> Repo.one()
  end

  defp require_condition!({:ok, condition}), do: {:ok, condition}
  defp require_condition!({:error, reason}), do: Repo.rollback(reason)

  defp new_record(condition, ship_instance_id) do
    struct!(PlayerShipCondition,
      Map.merge(condition, %{player_ship_id: ship_instance_id}))
  end

  defp persist!(%Ecto.Changeset{} = changeset) do
    case Repo.update(changeset) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp persist!(%PlayerShipCondition{} = record) do
    case Repo.insert(record) do
      {:ok, saved} -> saved
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp as_condition(record), do: Map.take(record, @fields)
end
