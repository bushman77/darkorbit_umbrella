defmodule Core.Universe.SecurityTest do
  use ExUnit.Case, async: true

  alias Core.Universe.Security

  defp zone(id, x, radius) do
    %{
      id: id,
      faction_id: id,
      center_km: %{x: x, y: 0.0, z: 0.0},
      radius_km: radius
    }
  end

  test "patrol presence declines from planetary core to border" do
    earth = zone("earth", 0.0, 10.0)

    assert {:ok, core} = Security.assess({0, 0, 0}, zones: [earth])
    assert {:ok, middle} = Security.assess({5, 0, 0}, zones: [earth])
    assert {:ok, rim} = Security.assess({10, 0, 0}, zones: [earth])

    assert core.status == :controlled
    assert hd(core.patrols).pressure > hd(middle.patrols).pressure
    assert hd(middle.patrols).pressure > hd(rim.patrols).pressure
    assert hd(rim.patrols).pressure > 0.0
    assert hd(core.patrols).band == :neutral
    assert hd(core.patrols).directive == :observe

    assert core.independent_pressure < middle.independent_pressure
    assert middle.independent_pressure < rim.independent_pressure
  end

  test "contested space generates independent patrol weights and directives per faction" do
    zones = [zone("earth", 0.0, 6.0), zone("mars", 8.0, 6.0)]

    assert {:ok, result} =
             Security.assess({4, 0, 0},
               zones: zones,
               reputations: %{"earth" => 75, "mars" => -70},
               wanted_factions: %{"earth" => true}
             )

    assert result.status == :contested
    assert result.independent_pressure == 0.35
    assert Enum.sort(Enum.map(result.patrols, & &1.faction_id)) == ["earth", "mars"]

    earth = Enum.find(result.patrols, &(&1.faction_id == "earth"))
    mars = Enum.find(result.patrols, &(&1.faction_id == "mars"))

    assert {earth.band, earth.directive} == {:allied, :pursue}
    assert {mars.band, mars.directive} == {:hostile, :intercept}
    assert_in_delta earth.pressure, mars.pressure, 0.000_001
    assert earth.pressure > 0
  end

  test "shipping-lane activity increases local patrol presence without changing jurisdiction" do
    zones = [zone("earth", 0, 10)]

    assert {:ok, quiet} =
             Security.assess({3, 0, 0}, zones: zones, shipping_lane_density: 0.0)

    assert {:ok, busy} =
             Security.assess({3, 0, 0}, zones: zones, shipping_lane_density: 1.0)

    assert quiet.status == busy.status
    assert quiet.claims == busy.claims
    assert hd(busy.patrols).pressure > hd(quiet.patrols).pressure

    assert {:ok, unpatrolled} =
             Security.assess({3, 0, 0},
               zones: zones,
               security_strength: %{"earth" => 0.0}
             )

    assert hd(unpatrolled.patrols).pressure == 0.0
    assert unpatrolled.status == :controlled
  end

  test "unclaimed space has independent activity without inventing a pirate owner" do
    assert {:ok, result} =
             Security.assess({50, 0, 0}, zones: [zone("earth", 0, 10)])

    assert result.status == :unclaimed
    assert result.claims == []
    assert result.patrols == []
    assert result.independent_pressure == 0.7
  end

  test "rejects spoofed or malformed reputations, warrants and security parameters" do
    zone = zone("earth", 0, 10)

    assert {:error, :invalid_reputations} =
             Security.assess({0, 0, 0}, zones: [zone], reputations: %{"earth" => -101})

    assert {:error, :invalid_reputations} =
             Security.assess({0, 0, 0}, zones: [zone], reputations: %{1 => 100})

    assert {:error, :invalid_wanted_factions} =
             Security.assess({0, 0, 0}, zones: [zone], wanted_factions: %{"mars" => "yes"})

    assert {:error, :invalid_security_strength} =
             Security.assess({0, 0, 0}, zones: [zone], security_strength: %{"earth" => 2})

    assert {:error, :invalid_shipping_lane_density} =
             Security.assess({0, 0, 0}, zones: [zone], shipping_lane_density: -0.1)

    assert {:error, :invalid_position} = Security.assess({0, 0}, zones: [zone])
    assert {:error, :invalid_security_options} = Security.assess({0, 0, 0}, :invalid)
  end
end
