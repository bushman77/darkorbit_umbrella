defmodule Darkorbit.Cargo.Catalog do
  @moduledoc """
  Typed, fixed-mass trade cargo for owned holds.

  Quantities are 1-tonne units in V1. This intentionally does not interpret
  strategic NPC cargo counts as tonnes until encounter transfer is designed.
  """
  @items %{
    "titanium" => %{name: "Titanium", mass_tonnes: 1},
    "dilithium" => %{name: "Dilithium", mass_tonnes: 1},
    "methane" => %{name: "Methane", mass_tonnes: 1},
    "industrial_parts" => %{name: "Industrial parts", mass_tonnes: 1},
    "salvage" => %{name: "Recovered salvage", mass_tonnes: 1},
    "brandy" => %{name: "Brandy", mass_tonnes: 1},
    # Real SOL traffic manifests. These cargo crates are distinct from the
    # ten-to-one abstract strategic manifest-unit conversion in Darkorbit.Piracy.
    "industrial_machinery" => %{name: "Industrial machinery", mass_tonnes: 1},
    "refined_minerals" => %{name: "Refined minerals", mass_tonnes: 1},
    "medical_supplies" => %{name: "Medical supplies", mass_tonnes: 1},
    "civilian_mail" => %{name: "Civilian mail", mass_tonnes: 1},
    "survey_equipment" => %{name: "Survey equipment", mass_tonnes: 1},
    "rock_samples" => %{name: "Rock samples", mass_tonnes: 1},
    "patrol_supplies" => %{name: "Patrol supplies", mass_tonnes: 1},
    "spare_parts" => %{name: "Spare parts", mass_tonnes: 1},
    "rare_ores" => %{name: "Rare ores", mass_tonnes: 1},
    "hydrogen_cells" => %{name: "Hydrogen cells", mass_tonnes: 1},
    "research_data" => %{name: "Research data", mass_tonnes: 1}
  }

  @spec all() :: map()
  def all, do: @items

  @spec fetch(binary()) :: {:ok, map()} | {:error, :unknown_cargo}
  def fetch(id) when is_binary(id) do
    case Map.fetch(@items, id) do
      {:ok, item} -> {:ok, Map.put(item, :id, id)}
      :error -> {:error, :unknown_cargo}
    end
  end

  def fetch(_id), do: {:error, :unknown_cargo}
end
