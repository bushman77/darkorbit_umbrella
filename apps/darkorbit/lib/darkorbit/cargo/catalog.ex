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
    "brandy" => %{name: "Brandy", mass_tonnes: 1}
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
