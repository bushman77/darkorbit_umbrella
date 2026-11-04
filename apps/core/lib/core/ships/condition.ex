defmodule Core.Ships.Condition do
  @moduledoc """
  Pure combat condition for a physical ship, independent of its tactical actor.

  Identity and settlement idempotency belong to the ship's authoritative owner.
  This module rejects unverified repair, capacity changes and resurrection.
  """

  @type status :: :alive | :surrendered | :destroyed
  @type t :: %{
          required(:hull) => non_neg_integer(),
          required(:max_hull) => pos_integer(),
          required(:shields) => non_neg_integer(),
          required(:max_shields) => non_neg_integer(),
          required(:status) => status()
        }

  @spec initial(map()) :: {:ok, t()} | {:error, :invalid_ship_condition}
  def initial(%{hit_points: hull, shields: shields}) do
    initial_from_capacities(hull, shields)
  end

  def initial(_), do: {:error, :invalid_ship_condition}

  @spec initial_from_capacities(term(), term()) ::
          {:ok, t()} | {:error, :invalid_ship_condition}
  def initial_from_capacities(max_hull, max_shields) do
    condition = %{
      hull: max_hull,
      max_hull: max_hull,
      shields: max_shields,
      max_shields: max_shields,
      status: :alive
    }

    with :ok <- validate(condition), do: {:ok, condition}
  end

  @spec validate(term()) :: :ok | {:error, :invalid_ship_condition}
  def validate(%{
        hull: hull,
        max_hull: max_hull,
        shields: shields,
        max_shields: max_shields,
        status: status
      })
      when is_integer(hull) and is_integer(max_hull) and
             is_integer(shields) and is_integer(max_shields) and
             max_hull > 0 and max_shields >= 0 and
             hull >= 0 and hull <= max_hull and
             shields >= 0 and shields <= max_shields do
    cond do
      hull == 0 and status == :destroyed -> :ok
      hull > 0 and status in [:alive, :surrendered] -> :ok
      true -> {:error, :invalid_ship_condition}
    end
  end

  def validate(_), do: {:error, :invalid_ship_condition}

  @doc "Accept a verified combat report only if damage and status are monotonic."
  @spec reconcile(t(), t()) :: {:ok, t()} | {:error, atom()}
  def reconcile(previous, reported) do
    with :ok <- validate(previous),
         :ok <- validate(reported),
         :ok <- same_capacities(previous, reported),
         :ok <- nonincreasing(previous, reported),
         :ok <- valid_status_transition(previous.status, reported.status) do
      {:ok, Map.take(reported, [:hull, :max_hull, :shields, :max_shields, :status])}
    end
  end

  @doc "Recalculate capacity after an authorized loadout change without healing."
  @spec rebase(t(), map()) :: {:ok, t()} | {:error, atom()}
  def rebase(previous, %{hit_points: max_hull, shields: max_shields}) do
    with :ok <- validate(previous),
         {:ok, _} <- initial_from_capacities(max_hull, max_shields) do
      revised = %{
        hull: min(previous.hull, max_hull),
        max_hull: max_hull,
        shields: min(previous.shields, max_shields),
        max_shields: max_shields,
        status: previous.status
      }

      with :ok <- validate(revised), do: {:ok, revised}
    end
  end

  def rebase(_previous, _stats), do: {:error, :invalid_ship_condition}

  defp same_capacities(a, b) do
    if a.max_hull == b.max_hull and a.max_shields == b.max_shields,
      do: :ok,
      else: {:error, :capacity_mismatch}
  end

  defp nonincreasing(a, b) do
    if b.hull <= a.hull and b.shields <= a.shields,
      do: :ok,
      else: {:error, :unverified_repair}
  end

  defp valid_status_transition(:alive, status)
       when status in [:alive, :surrendered, :destroyed], do: :ok
  defp valid_status_transition(status, status) when status in [:destroyed, :surrendered], do: :ok
  defp valid_status_transition(_, _), do: {:error, :invalid_ship_status_transition}
end
