defmodule Core.Ships.CatalogTest do
  use ExUnit.Case, async: true

  alias Core.Equipment.Catalog, as: EquipmentCatalog
  alias Core.Ships.Catalog, as: ShipCatalog

  test "provides initial ships with all authoritative base statistics" do
    assert {:ok, sunracer} = ShipCatalog.fetch(1)
    assert sunracer.name == "Sunracer"
    assert sunracer.hit_points == 300
    assert sunracer.shields == 0
    assert sunracer.speed == 320
    assert sunracer.damage == 10
    assert sunracer.cargo_capacity == 4
    assert sunracer.forward_shield_class == 1
    assert sunracer.aft_shield_class == 0
    assert sunracer.missile_tube
    assert sunracer.cargo_pods == 4
    assert sunracer.laser_slots == 1
    assert sunracer.generator_slots == 1
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
