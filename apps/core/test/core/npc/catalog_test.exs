defmodule Core.NPC.CatalogTest do
  use ExUnit.Case, async: true

  alias Core.NPC.Catalog

  test "provides the original, configurable starting-sector NPC" do
    assert {:ok, definition} = Catalog.fetch("rift_skirmisher")
    assert definition.display_name == "Rift Skirmisher"
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
    assert length(definition.spawn.positions) == 3
    assert definition.spawn.respawn_delay_ms > 0
    assert Catalog.for_map("9-9") == []
  end
end
