defmodule Core.Equipment.Catalog do
  @moduledoc """
  Configurable laser, speed-generator, and shield definitions.

  Values are placeholders until balancing is verified. Override the complete
  list with `config :core, :equipment_catalog, items`.
  """

  alias Core.Equipment.Item

  @default_items [
    %Item{id: "lf1", name: "LF-1", category: :laser, damage: 40},
    %Item{id: "lf2", name: "LF-2", category: :laser, damage: 60},
    %Item{id: "lf3", name: "LF-3", category: :laser, damage: 150},
    %Item{id: "lf4", name: "LF-4", category: :laser, damage: 200},
    %Item{id: "g1", name: "G3N-1010", category: :generator, speed: 2},
    %Item{id: "g2", name: "G3N-2010", category: :generator, speed: 4},
    %Item{id: "g3", name: "G3N-3210", category: :generator, speed: 7},
    %Item{
      id: "sg1",
      name: "SG3N-A01",
      category: :shield,
      shields: 1_000,
      shield_absorption: 0.4,
      shield_regeneration: 4
    },
    %Item{
      id: "sg2",
      name: "SG3N-A02",
      category: :shield,
      shields: 2_000,
      shield_absorption: 0.5,
      shield_regeneration: 8
    },
    %Item{
      id: "bo2",
      name: "B02 Shield",
      category: :shield,
      shields: 10_000,
      shield_absorption: 0.8,
      shield_regeneration: 25
    }
  ]

  @spec all() :: [Item.t()]
  def all do
    Application.get_env(:core, :equipment_catalog, @default_items)
  end

  @spec fetch(String.t(), [Item.t()] | %{optional(String.t()) => Item.t()}) ::
          {:ok, Item.t()} | :error
  def fetch(id, catalog \\ all()) when is_binary(id) do
    case catalog do
      catalog when is_list(catalog) -> Enum.find_value(catalog, :error, &matching_item(&1, id))
      catalog when is_map(catalog) -> Map.fetch(catalog, id)
    end
  end

  @spec fetch!(String.t(), [Item.t()] | %{optional(String.t()) => Item.t()}) :: Item.t()
  def fetch!(id, catalog \\ all()) do
    case fetch(id, catalog) do
      {:ok, item} -> item
      :error -> raise KeyError, key: id, term: catalog
    end
  end

  @spec inventory_bucket(Item.t()) :: String.t()
  def inventory_bucket(%Item{category: :laser}), do: "lasers"
  def inventory_bucket(%Item{category: :generator}), do: "generators"
  def inventory_bucket(%Item{category: :shield}), do: "shields"

  defp matching_item(%Item{id: id} = item, id), do: {:ok, item}
  defp matching_item(_item, _id), do: false
end
