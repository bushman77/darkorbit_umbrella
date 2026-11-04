defmodule DarkorbitWeb.WorldStreamDeltaTest do
  use ExUnit.Case, async: true

  alias DarkorbitWeb.WorldStreamDelta

  defp snapshot do
    %{
      tick: 40, tick_ms: 100, map_id: "sol:earth",
      boundaries: %{width: 20_000, height: 12_000},
      planetary_warnings: [],
      entities: [
        %{id: 1, kind: :player, ship_instance_id: 99, hull: 200, max_hull: 300,
          shields: 15, speed: 320, damage: 10, position_3d: %{x: 5, y: 6, z: 7}},
        %{id: "scow:1", kind: :npc, ship_class: "scow", hull: 210,
          shields: 45, position_3d: %{x: 20, y: 30, z: 40}}
      ]
    }
  end

  test "movement sends changed fields without static metadata" do
    before = snapshot()
    [player, scow] = before.entities
    after_state = %{before | tick: 41,
      entities: [%{player | position_3d: %{x: 6, y: 6, z: 7}}, scow]}
    delta = WorldStreamDelta.between(before, after_state)
    assert delta == %{base_tick: 40, tick: 41,
      entities: [%{id: 1, position_3d: %{x: 6, y: 6, z: 7}}],
      removed: [], changes: %{}}
    assert byte_size(Jason.encode!(delta)) < div(byte_size(Jason.encode!(after_state)), 2)
  end

  test "damage, spawns, removals and warnings" do
    before = snapshot()
    [player, _] = before.entities
    dart = %{id: "dart", kind: :npc, hull: 40}
    after_state = %{before | tick: 41,
      entities: [%{player | hull: 180}, dart],
      planetary_warnings: [%{entity_id: 1, level: :danger}]}
    delta = WorldStreamDelta.between(before, after_state)
    assert delta.entities == [%{id: 1, hull: 180}, dart]
    assert delta.removed == ["scow:1"]
    assert delta.changes == %{planetary_warnings: [%{entity_id: 1, level: :danger}]}
  end
end
