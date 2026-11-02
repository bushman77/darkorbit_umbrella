defmodule Core.NPC.CatalogTest do
  use ExUnit.Case, async: true

  alias Core.NPC.Catalog

  test "Sector 1-1 contains one original-inspired Dart and no skirmishers" do
    assert {:ok, definition} = Catalog.fetch("dart")
    assert definition.display_name == "Dart"
    assert definition.max_hull == 245
    assert definition.max_shields == 120
    assert :error == Catalog.fetch("rift_skirmisher")
    assert Enum.map(Catalog.for_map("1-1"), & &1.id) == ["dart"]
    assert definition.max_hull > 0
    assert definition.max_shields >= 0
    assert definition.shield_absorption >= 0.0
    assert definition.shield_absorption <= 1.0
    assert definition.movement_speed > 0
    assert definition.laser_damage > 0
    assert definition.attack_range > 0
    assert definition.attack_cooldown_ms > 0
    assert definition.detection_radius >= definition.attack_range
    assert definition.spawn.map_id == "1-1"
    assert definition.spawn.positions == [%Core.World.Position{x: 1_480.0, y: 1_000.0}]
    assert definition.spawn.respawn_delay_ms > 0
    assert Catalog.for_map("9-9") == []
  end
end
