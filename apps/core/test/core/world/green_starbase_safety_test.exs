defmodule Core.World.GreenStarbaseSafetyTest do
  use ExUnit.Case, async: true

  alias Core.Universe.GreenStarbase
  alias Core.World.{Entity, GreenStarbaseSafety, Position}

  @scale 0.06

  defp at(x, y, z) do
    site = GreenStarbase.local_site()
    %Position{
      x: site.x + x / @scale,
      y: site.y + z / @scale,
      z: site.z + y / @scale
    }
  end

  defp ship(pos) do
    %Entity{
      id: 37, kind: :player, player_id: 37, session_id: 1,
      position: pos, speed: 320.0, hull: 200, max_hull: 200,
      shields: 0, max_shields: 0, shield_absorption: 0.0,
      damage: 10, attack_range: 3_600.0, attack_cooldown_ticks: 1,
      next_attack_tick: 0, status: :alive
    }
  end

  test "server geometry matches a hollow front entrance with solid rear and supports" do
    refute GreenStarbaseSafety.inside?(at(0, 0, -30))
    refute GreenStarbaseSafety.inside?(at(0, 0, -10))
    assert GreenStarbaseSafety.open_approach?(at(0, 0, -30))
    assert GreenStarbaseSafety.open_approach?(at(0, 0, -10))
    refute GreenStarbaseSafety.open_approach?(at(25, 0, -30))
    assert GreenStarbaseSafety.inside?(at(28, 0, 0))
    assert GreenStarbaseSafety.inside?(at(0, 0, 23.5))
    assert GreenStarbaseSafety.inside?(at(0, 30, 0))
    assert GreenStarbaseSafety.inside?(at(0, -30, 0))
  end

  test "caution, critical and aligned approach are independent of refinery data" do
    assert GreenStarbaseSafety.warning(at(0, 0, -200), true) == nil
    assert %{level: :caution, station_id: "sol:starbase:green"} =
      GreenStarbaseSafety.warning(at(0, 0, -110), true)
    assert %{level: :critical} =
      GreenStarbaseSafety.warning(at(28, 0, -30), true)
    assert %{level: :approach, docking_available: false} =
      GreenStarbaseSafety.warning(at(0, 0, -30), true)
    assert GreenStarbaseSafety.warning(at(0, 0, -30), false) == nil
  end

  test "swept passage through open mouth is unobstructed until the rear bulkhead" do
    assert :clear == GreenStarbaseSafety.first_contact(
      at(0, 0, -60), at(0, 0, 10))
    assert {:hit, %{part: :hangar_rear_wall, position: impact}} =
      GreenStarbaseSafety.first_contact(at(0, 0, -60), at(0, 0, 35))
    # Wall begins at local scene Z 23.0. Impact is safely just in front of it.
    assert_in_delta impact.y, GreenStarbase.local_site().y + 23 / @scale, 1.0
    refute GreenStarbaseSafety.inside?(impact)
  end

  test "sidewall and both pyramid solids resist swept high-speed tunnelling" do
    assert {:hit, %{part: part}} =
      GreenStarbaseSafety.first_contact(at(28, 0, -60), at(28, 0, 60))
    assert part in [:left_support, :right_support, :left_brace, :right_brace]
    assert {:hit, %{part: :upper_pyramid}} =
      GreenStarbaseSafety.first_contact(at(0, 65, 0), at(0, 20, 0))
    assert {:hit, %{part: :lower_pyramid}} =
      GreenStarbaseSafety.first_contact(at(0, -65, 0), at(0, -20, 0))
    assert :clear == GreenStarbaseSafety.first_contact(
      at(70, 0, -50), at(70, 0, 50))
  end

  test "manual/autopilot impact stops, damages, and cannot repeat while idle" do
    before = ship(at(28, 0, -28))
    moved = %{before | position: at(28, 0, 5), throttle: 1.0,
      velocity: %{x: 0.0, y: 1_000.0, z: 0.0},
      destination: at(28, 0, 40), navigation_mode: :autopilot}
    assert {:impact, stopped, report} =
      GreenStarbaseSafety.resolve(before, moved, true, 1.0)
    assert report.station_id == "sol:starbase:green"
    assert report.hull_part in [:left_support, :right_support, :left_brace, :right_brace]
    assert stopped.hull < before.hull
    assert stopped.destination == nil
    assert stopped.navigation_mode == :manual
    assert stopped.throttle == 0.0
    assert stopped.velocity == %{x: 0.0, y: 0.0, z: 0.0}
    assert {:ok, ^stopped} = GreenStarbaseSafety.resolve(stopped, stopped, true, 1.0)
    assert {:ok, ^moved} = GreenStarbaseSafety.resolve(before, moved, false, 1.0)
  end

  test "direct fast transit into rear wall always registers impact" do
    before = ship(at(0, 0, -90))
    moved = %{before | position: at(0, 0, 90)}
    assert {:impact, stopped, %{hull_part: :hangar_rear_wall}} =
      GreenStarbaseSafety.resolve(before, moved, true, 0.1)
    assert stopped.hull == 100
  end
end
