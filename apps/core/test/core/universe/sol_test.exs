defmodule Core.Universe.SolTest do
  use ExUnit.Case, async: true
  alias Core.Universe.Sol

  test "Sol has one star, all eight planets and Pluto in AU order" do
    names = Sol.all() |> Enum.map(& &1.name)
    assert names == ~w(Sun Mercury Venus Earth Mars Jupiter Saturn Uranus Neptune Pluto)
    assert {:ok, %{kind: :dwarf_planet, au: 39.482}} = Sol.fetch("pluto")
    assert Sol.destination?("pluto")
    assert Sol.destination?("earth")
    refute Sol.destination?("sun")
    refute Sol.destination?("nowhere")
    assert :error == Sol.fetch(nil)
  end

  test "demo travel durations are positive and bounded, not ship combat XY" do
    assert Sol.travel_duration_ms("earth", "mars") >= 12_000
    assert Sol.travel_duration_ms("earth", "pluto") <= 120_000
    assert Sol.travel_duration_ms("earth", "pluto") >
             Sol.travel_duration_ms("earth", "mars")
  end
end
