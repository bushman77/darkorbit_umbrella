defmodule Core.Ships.CatalogTest do
  use ExUnit.Case, async: true

  alias Core.Equipment.Catalog, as: EquipmentCatalog
  alias Core.Ships.Catalog, as: ShipCatalog

  test "provides initial ships with all authoritative base statistics" do
    assert {:ok, phoenix} = ShipCatalog.fetch(1)
    assert phoenix.name == "Phoenix"
    assert phoenix.hit_points == 4_000
    assert phoenix.shields == 0
    assert phoenix.speed == 320
    assert phoenix.damage == 40
    assert phoenix.cargo_capacity == 100
    assert phoenix.laser_slots == 1
    assert phoenix.generator_slots == 1
  end

  test "provides laser, speed generator, and shield definitions" do
    assert {:ok, laser} = EquipmentCatalog.fetch("lf3")
    assert laser.category == :laser
    assert laser.damage == 150

    assert {:ok, generator} = EquipmentCatalog.fetch("g2")
    assert generator.category == :generator
    assert generator.speed == 4

    assert {:ok, shield} = EquipmentCatalog.fetch("bo2")
    assert shield.category == :shield
    assert shield.shields == 10_000
  end

  test "reports unknown definitions without inventing fallback data" do
    assert :error = ShipCatalog.fetch(999)
    assert :error = EquipmentCatalog.fetch("unknown")
  end
end
