defmodule Core.FactionsTest do
  use ExUnit.Case, async: true

  alias Core.Factions

  test "each navigable SOL planet has an independent faction, including Pluto" do
    assert Enum.map(Factions.all(), & &1.id) ==
             ~w(mercury venus earth mars jupiter saturn uranus neptune pluto)

    assert Factions.exists?("earth")
    assert Factions.exists?("pluto")
    refute Factions.exists?("sun")
    refute Factions.exists?("mmo")
    refute Factions.exists?(1)
  end

  test "standing thresholds are explicit, inclusive, and deterministic" do
    for {score, tier} <- [
          {-100, :hostile},
          {-60, :hostile},
          {-59, :unfriendly},
          {-20, :unfriendly},
          {-19, :neutral},
          {0, :neutral},
          {19, :neutral},
          {20, :friendly},
          {59, :friendly},
          {60, :allied},
          {100, :allied}
        ] do
      assert {:ok, ^tier} = Factions.band(score)
    end

    for bad <- [-101, 101, 0.5, "0", nil] do
      assert {:error, :invalid_reputation} = Factions.band(bad)
    end
  end

  test "patrol responses never imply an automatic attack" do
    assert {:ok, %{directive: :assist}} = Factions.patrol_directive(100)
    assert {:ok, %{directive: :clear}} = Factions.patrol_directive(40)
    assert {:ok, %{directive: :observe}} = Factions.patrol_directive(0)
    assert {:ok, %{directive: :inspect}} = Factions.patrol_directive(-25)
    assert {:ok, %{directive: :intercept}} = Factions.patrol_directive(-75)
    assert {:ok, %{band: :allied, directive: :pursue}} =
             Factions.patrol_directive(100, wanted: true)
    assert {:error, :invalid_wanted} = Factions.patrol_directive(0, wanted: "true")
  end
end
