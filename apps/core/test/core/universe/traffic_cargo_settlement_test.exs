defmodule Core.Universe.TrafficCargoSettlementTest do
  use ExUnit.Case, async: true

  alias Core.Universe.Traffic

  defp evidence do
    ship = Traffic.seed()["traffic:sol:vesper-02"]
    identity = %{
      contact_id: ship.id, voyage_number: ship.voyage_number,
      encounter_id: "combat:test:1"
    }
    report = %{ship.combat | status: :surrendered, hull: ship.combat.hull - 1}
    {ship, identity, report}
  end

  test "surrender deducts only the units from the canonical traffic manifest" do
    {ship, identity, report} = evidence()
    ships = %{ship.id => ship}
    assert {:ok, updated} =
      Traffic.settle(ships, identity, report, :surrender, %{"medical_supplies" => 20})
    vessel = updated[ship.id]
    assert vessel.cargo["medical_supplies"] == ship.cargo["medical_supplies"] - 20
    assert vessel.cargo["civilian_mail"] == ship.cargo["civilian_mail"]
    assert vessel.state == :disabled

    assert {:error, :already_settled} =
      Traffic.settle(updated, identity, report, :surrender, %{"medical_supplies" => 20})
  end

  test "rejects nonexistent, excessive, negative and non-surrender cargo debits" do
    {ship, identity, report} = evidence()
    ships = %{ship.id => ship}

    for debit <- [%{"medical_supplies" => 50_000},
                   %{"unknown" => 1},
                   %{"medical_supplies" => -1},
                   %{"medical_supplies" => 0}] do
      assert {:error, :invalid_cargo_debit} =
        Traffic.settle(ships, identity, report, :surrender, debit)
    end

    assert {:error, :invalid_cargo_debit} =
      Traffic.settle(ships, identity, %{report | status: :alive},
        :retreat, %{"medical_supplies" => 10})
    assert ships[ship.id].cargo == ship.cargo
  end
end
