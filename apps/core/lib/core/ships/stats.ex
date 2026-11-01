defmodule Core.Ships.Stats do
  @moduledoc """
  Pure, deterministic ship-stat calculation from a ship and equipped items.

  No computed value is persisted. Callers supply either the normal catalog ids
  or explicit catalogs in the options, which also makes balancing simulations
  and tests deterministic.
  """

  alias Core.Equipment.Catalog, as: EquipmentCatalog
  alias Core.Equipment.Item
  alias Core.Ships.Catalog, as: ShipCatalog
  alias Core.Ships.Ship

  @enforce_keys [
    :ship_id,
    :hit_points,
    :shields,
    :speed,
    :damage,
    :cargo_capacity,
    :shield_absorption,
    :shield_regeneration
  ]
  defstruct [
    :ship_id,
    :hit_points,
    :shields,
    :speed,
    :damage,
    :cargo_capacity,
    :shield_absorption,
    :shield_regeneration
  ]

  @type t :: %__MODULE__{
          ship_id: pos_integer(),
          hit_points: non_neg_integer(),
          shields: non_neg_integer(),
          speed: non_neg_integer(),
          damage: non_neg_integer(),
          cargo_capacity: non_neg_integer(),
          shield_absorption: float(),
          shield_regeneration: non_neg_integer()
        }

  @spec calculate(pos_integer(), map(), keyword()) :: {:ok, t()} | {:error, term()}
  def calculate(ship_id, loadout, opts \\ []) when is_integer(ship_id) and is_map(loadout) do
    ships = Keyword.get(opts, :ships, ShipCatalog.all())
    equipment = Keyword.get(opts, :equipment, EquipmentCatalog.all())

    with {:ok, ship} <- fetch_ship(ship_id, ships),
         {:ok, lasers} <- equipped_items(loadout, :lasers, ship.laser_slots, :laser, equipment),
         {:ok, generators} <-
           equipped_items(
             loadout,
             :generators,
             ship.generator_slots,
             [:generator, :shield],
             equipment
           ) do
      {:ok, derive(ship, lasers ++ generators)}
    end
  end

  @doc """
  Calculates the required two configurations without allowing one to silently
  substitute for the other.
  """
  @spec calculate_configurations(pos_integer(), map(), keyword()) ::
          {:ok, %{1 => t(), 2 => t()}} | {:error, term()}
  def calculate_configurations(ship_id, configurations, opts \\ [])
      when is_integer(ship_id) and is_map(configurations) do
    with {:ok, configuration_one} <- fetch_configuration(configurations, 1),
         {:ok, configuration_two} <- fetch_configuration(configurations, 2),
         {:ok, stats_one} <- calculate(ship_id, configuration_one, opts),
         {:ok, stats_two} <- calculate(ship_id, configuration_two, opts) do
      {:ok, %{1 => stats_one, 2 => stats_two}}
    end
  end

  defp fetch_ship(ship_id, ships) do
    case ShipCatalog.fetch(ship_id, ships) do
      {:ok, ship} -> {:ok, ship}
      :error -> {:error, {:unknown_ship, ship_id}}
    end
  end

  defp fetch_configuration(configurations, number) do
    case Map.fetch(configurations, number) do
      {:ok, configuration} -> {:ok, configuration}
      :error -> {:error, {:missing_configuration, number}}
    end
  end

  defp equipped_items(loadout, field, capacity, categories, catalog) do
    slots = loadout |> loadout_field(field) |> ship_slots()

    slots
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn
      {nil, _index}, {:ok, items} ->
        {:cont, {:ok, items}}

      {_item_id, index}, {:ok, _items} when index >= capacity ->
        {:halt, {:error, {:slot_locked, field, index}}}

      {item_id, index}, {:ok, items} when is_binary(item_id) ->
        case EquipmentCatalog.fetch(item_id, catalog) do
          {:ok, %Item{category: category} = item} ->
            if category in List.wrap(categories) do
              {:cont, {:ok, [item | items]}}
            else
              {:halt, {:error, {:incompatible_equipment, field, index, item_id}}}
            end

          :error ->
            {:halt, {:error, {:unknown_equipment, item_id}}}
        end

      {_item_id, index}, {:ok, _items} ->
        {:halt, {:error, {:invalid_equipment_id, field, index}}}
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp loadout_field(loadout, field) do
    Map.get(loadout, field, Map.get(loadout, Atom.to_string(field), []))
  end

  defp ship_slots(slots) when is_list(slots), do: slots

  defp ship_slots(slots) when is_map(slots) do
    Map.get(slots, "ship", Map.get(slots, :ship, []))
  end

  defp ship_slots(_slots), do: []

  defp derive(%Ship{} = ship, items) do
    shield_sources =
      [
        {ship.shields, ship.shield_absorption}
        | Enum.map(items, &{&1.shields, &1.shield_absorption})
      ]

    total_shields =
      Enum.reduce(shield_sources, 0, fn {shields, _absorption}, sum -> sum + shields end)

    weighted_absorption =
      if total_shields == 0 do
        0.0
      else
        Enum.reduce(shield_sources, 0.0, fn {shields, absorption}, sum ->
          sum + shields * absorption
        end) / total_shields
      end

    raw_damage = ship.damage + Enum.reduce(items, 0, fn item, sum -> sum + item.damage end)

    damage_multiplier =
      Enum.reduce(items, ship.damage_multiplier, fn item, multiplier ->
        multiplier * item.damage_multiplier
      end)

    %__MODULE__{
      ship_id: ship.id,
      hit_points: ship.hit_points,
      shields: total_shields,
      speed: ship.speed + Enum.reduce(items, 0, fn item, sum -> sum + item.speed end),
      damage: round(raw_damage * damage_multiplier),
      cargo_capacity: ship.cargo_capacity,
      shield_absorption: weighted_absorption,
      shield_regeneration:
        ship.shield_regeneration +
          Enum.reduce(items, 0, fn item, sum -> sum + item.shield_regeneration end)
    }
  end
end
