defmodule Core.Universe.SpaceBasesTest do
  use ExUnit.Case, async: true

  alias Core.Universe.{Sol, SpaceBases, Traffic}

  test "every registered SOL destination owns one operational orbital base and refinery" do
    bases = SpaceBases.seed()
    assert Map.keys(bases) |> Enum.sort() ==
      Enum.map(Sol.planets(), & &1.id) |> Enum.sort()
    assert length(SpaceBases.catalog()) == 9

    for planet <- Sol.planets() do
      base = bases[planet.id]
      assert base.id == "sol:base:" <> planet.id
      assert base.refinery_id == "sol:refinery:" <> planet.id
      assert base.berth_count == 3
      assert base.berths == %{}
      assert Enum.all?(base.stock, fn {_good, qty} -> qty >= 0 end)
      assert %{occupied_berths: 0, refinery_status: :operational} =
        SpaceBases.public(bases, planet.id)
    end
    assert SpaceBases.public(bases, "sun") == nil
  end

  test "merchant unloads into the Mars forward refinery and loads a real return manifest" do
    bases = SpaceBases.seed()
    fleet = Traffic.seed()
    meridian = fleet["traffic:sol:meridian-01"]
    mars_before = SpaceBases.produce(bases, meridian.duration_ms)["mars"].stock

    {at_mars, bases} =
      Traffic.advance_with_bases(fleet, meridian.duration_ms, bases)
    ship = at_mars[meridian.id]
    assert ship.state == :docked
    assert ship.location_id == "mars"
    assert ship.cargo == %{"refined_minerals" => 85}
    assert SpaceBases.public(bases, "mars").occupied_berths == 1

    # The refinery receives precisely the inbound industrial machinery and
    # loses precisely the 85 refined-mineral units actually loaded.
    assert bases["mars"].stock["industrial_machinery"] == 120
    assert bases["mars"].stock["refined_minerals"] ==
      mars_before["refined_minerals"] - 85

    {returned, bases} = Traffic.advance_with_bases(at_mars, 45_000, bases)
    departing = returned[meridian.id]
    assert departing.state == :in_transit
    assert departing.origin_id == "mars"
    assert departing.destination_id == "earth"
    assert departing.cargo == %{"refined_minerals" => 85}
    assert departing.voyage_number == 2
    assert SpaceBases.public(bases, "mars").occupied_berths == 0
  end

  test "full berths queue a fourth physical merchant without unloading its cargo" do
    {bases, fleet} =
      Enum.reduce(1..4, {SpaceBases.seed(), %{}}, fn serial, {bases, fleet} ->
        {:ok, new} = Traffic.launch_scheduled_trader(
          %{}, "earth", "mars", serial)
        vessel = new["traffic:sol:cruise-" <> Integer.to_string(serial)]
        # A new merchant's initial load is withdrawn from the base.
        {bases, loaded} = SpaceBases.dispatch(bases, vessel)
        {bases, Map.put(fleet, loaded.id, loaded)}
      end)

    duration =
      fleet |> Map.values() |> hd() |> Map.fetch!(:duration_ms)
    {arrived, bases} = Traffic.advance_with_bases(fleet, duration, bases)
    assert Enum.count(arrived, fn {_, ship} -> ship.state == :docked end) == 3
    [{waiting_id, waiting}] = Enum.filter(arrived, fn {_, ship} ->
      ship.state == :awaiting_berth
    end)
    assert waiting.cargo == %{"industrial_parts" => 32}
    assert SpaceBases.public(bases, "mars").occupied_berths == 3
    assert bases["mars"].stock["industrial_parts"] == 150 + 3 * 32

    # Departure frees three bays; the waiting trader takes a newly freed
    # bay in the same clock advancement, without duplicating its cargo.
    {departed, bases} = Traffic.advance_with_bases(arrived, 45_000, bases)
    assert departed[waiting_id].state == :docked
    assert SpaceBases.public(bases, "mars").occupied_berths == 1
    assert bases["mars"].stock["industrial_parts"] == 150 + 4 * 32

    {redocked, bases} = Traffic.advance_with_bases(departed, 1_000, bases)
    assert redocked[waiting_id].state == :docked
    assert SpaceBases.public(bases, "mars").occupied_berths == 1
  end

  test "refinery stocks do not fabricate goods and local production occurs once per minute" do
    initial = SpaceBases.seed()
    {remaining, dispatched} = SpaceBases.dispatch(initial,
      %{id: "test-ship", kind: :commercial_freighter,
        origin_id: "earth", cargo: %{"industrial_parts" => 10_000}})
    assert dispatched.cargo == %{"industrial_parts" => 900}
    assert remaining["earth"].stock["industrial_parts"] == 0

    produced = remaining |> SpaceBases.produce(59_999)
    assert produced["earth"].stock["industrial_parts"] == 0
    produced = SpaceBases.produce(produced, 1)
    assert produced["earth"].stock["industrial_parts"] == 16
    assert produced["earth"].production_elapsed_ms == 0
    assert SpaceBases.produce(produced, 0) == produced
  end

  test "disabled traffic preserves remaining cargo and never enters a bay" do
    fleet = Traffic.seed()
    disabled = %{fleet["traffic:sol:meridian-01"] | state: :disabled}
    fleet = Map.put(fleet, disabled.id, disabled)
    bases = SpaceBases.seed()

    {later, unchanged} = Traffic.advance_with_bases(fleet, 1_000_000, bases)
    assert later[disabled.id] == disabled
    assert SpaceBases.public(unchanged, "mars").occupied_berths == 0
    assert unchanged["mars"].stock ==
      SpaceBases.produce(bases, 1_000_000)["mars"].stock
  end
end
