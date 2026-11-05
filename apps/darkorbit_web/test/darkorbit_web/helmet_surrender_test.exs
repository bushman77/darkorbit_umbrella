defmodule DarkorbitWeb.HelmetSurrenderTest do
  use ExUnit.Case, async: true

  alias DarkorbitWeb.HelmetSurrender

  test "recognizes the paired pilot's surrendered Scow without target selection" do
    map = %{entities: [
      %{kind: :player, state: :active, id: 3},
      %{kind: :npc, state: :surrendered, npc_type_id: "solar-scow-3",
        display_name: "Hauler-2"}
    ]}

    assert HelmetSurrender.from_world(map, 3) ==
             %{surrendered: true, call_sign: "Hauler-2"}
  end

  test "never broadcasts another pilot's surrender" do
    npc = %{kind: :npc, state: :surrendered, npc_type_id: "solar-scow-13",
      display_name: "Hauler-13"}

    assert HelmetSurrender.from_world(%{entities: [npc]}, 3) ==
             %{surrendered: false}
  end

  test "clears on active enemy or missing enemy" do
    npc = %{kind: :npc, state: :evade, npc_type_id: "solar-scow-3",
      display_name: "Hauler-2"}

    assert HelmetSurrender.from_world(%{entities: [npc]}, 3) ==
             %{surrendered: false}
    assert HelmetSurrender.from_world(%{entities: []}, 3) ==
             %{surrendered: false}
    assert HelmetSurrender.from_world(nil, 3) ==
             %{surrendered: false}
  end

  test "supports future solar tactical classes but not unrelated NPCs" do
    dart = %{kind: :npc, state: :surrendered, npc_type_id: "solar-dart-3",
      display_name: "Sentinel"}
    ambient = %{kind: :npc, state: :surrendered, npc_type_id: "ambient-dart-3",
      display_name: "Random"}

    assert HelmetSurrender.from_world(%{entities: [ambient, dart]}, 3) ==
             %{surrendered: true, call_sign: "Sentinel"}
    assert HelmetSurrender.from_world(%{entities: [ambient]}, 3) ==
             %{surrendered: false}
  end
end
