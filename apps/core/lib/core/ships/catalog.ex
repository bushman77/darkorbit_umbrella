defmodule Core.Ships.Catalog do
  @moduledoc """
  Configurable catalog of playable ship definitions.

  The built-in values are intentionally conservative placeholder data. A
  deployment can replace the list with `config :core, :ship_catalog, ships`
  without changing the deterministic statistics engine.
  """

  alias Core.Ships.Ship

  @default_ships [
    %Ship{
      id: 1,
      name: "Phoenix",
      hit_points: 4_000,
      shields: 0,
      speed: 320,
      damage: 0,
      cargo_capacity: 100,
      laser_slots: 1,
      generator_slots: 1
    },
    %Ship{
      id: 2,
      name: "Yamato",
      hit_points: 8_000,
      shields: 1_000,
      speed: 340,
      damage: 10,
      cargo_capacity: 200,
      laser_slots: 2,
      generator_slots: 2,
      shield_absorption: 0.2,
      shield_regeneration: 5
    },
    %Ship{
      id: 3,
      name: "Leonov",
      hit_points: 12_000,
      shields: 2_000,
      speed: 360,
      damage: 20,
      cargo_capacity: 500,
      laser_slots: 3,
      generator_slots: 3,
      shield_absorption: 0.3,
      shield_regeneration: 10
    }
  ]

  @spec all() :: [Ship.t()]
  def all do
    Application.get_env(:core, :ship_catalog, @default_ships)
  end

  @spec fetch(pos_integer(), [Ship.t()] | %{optional(pos_integer()) => Ship.t()}) ::
          {:ok, Ship.t()} | :error
  def fetch(id, catalog \\ all()) when is_integer(id) do
    case catalog do
      catalog when is_list(catalog) -> Enum.find_value(catalog, :error, &matching_ship(&1, id))
      catalog when is_map(catalog) -> Map.fetch(catalog, id)
    end
  end

  @spec fetch!(pos_integer(), [Ship.t()] | %{optional(pos_integer()) => Ship.t()}) :: Ship.t()
  def fetch!(id, catalog \\ all()) do
    case fetch(id, catalog) do
      {:ok, ship} -> ship
      :error -> raise KeyError, key: id, term: catalog
    end
  end

  defp matching_ship(%Ship{id: id} = ship, id), do: {:ok, ship}
  defp matching_ship(_ship, _id), do: false
end
