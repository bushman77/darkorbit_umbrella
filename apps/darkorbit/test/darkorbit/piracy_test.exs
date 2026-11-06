defmodule Darkorbit.PiracyTest do
  use Darkorbit.DataCase

  import Darkorbit.AccountsFixtures

  alias Darkorbit.Inventory
  alias Darkorbit.Piracy

  defp contact(attrs \\ %{}) do
    Map.merge(%{
      contact_id: "traffic:sol:test-#{System.unique_integer([:positive])}",
      voyage_number: 1,
      encounter_id: "merchant:one:1",
      faction_id: "sol_merchant_league",
      classification: :neutral_flyby,
      disposition: :neutral,
      cargo: %{"industrial_parts" => 32, "rare_ores" => 26}
    }, attrs)
  end

  test "seizes only the four-tonne capacity and debits ten strategic units per crate" do
    pilot = player_account_fixture()
    source = contact()

    assert {:ok, receipt} = Piracy.seize_surrender(pilot.id, source)
    assert receipt.cargo == %{"industrial_parts" => 3, "rare_ores" => 1}
    assert receipt.strategic_debit == %{"industrial_parts" => 30, "rare_ores" => 10}
    assert receipt.standing == -18
    assert Inventory.cargo_manifest(pilot.id) == receipt.cargo
    assert Inventory.cargo_tonnage(pilot.id) == 4

    assert {:ok, replay} = Piracy.seize_surrender(pilot.id, source)
    assert replay == receipt
    assert Inventory.cargo_tonnage(pilot.id) == 4
    assert Piracy.faction_standing(pilot.id, source.faction_id) == -18

    assert {:ok, scoped} = Piracy.claim_receipt(pilot.id, source.encounter_id)
    assert scoped == receipt
  end

  test "another account cannot double-claim a physical vessel and voyage" do
    first = player_account_fixture()
    second = player_account_fixture()
    source = contact()

    assert {:ok, _} = Piracy.seize_surrender(first.id, source)
    assert {:error, :cargo_already_claimed} =
      Piracy.seize_surrender(second.id, %{source | encounter_id: "merchant:two:1"})
    assert Inventory.cargo_manifest(second.id) == %{}
    assert {:error, :claim_not_found} =
      Piracy.claim_receipt(second.id, source.encounter_id)
  end

  test "full hold never mints cargo or consumes the one-time receipt" do
    pilot = player_account_fixture()
    source = contact()

    assert {:ok, _} = Inventory.add_cargo(pilot.id, "titanium", 4)
    assert {:error, :no_cargo_space_or_stock} =
      Piracy.seize_surrender(pilot.id, source)
    assert Piracy.faction_standing(pilot.id, source.faction_id) == 0

    assert {:ok, _} = Inventory.remove_cargo(pilot.id, "titanium", 1)
    assert {:ok, claimed} = Piracy.seize_surrender(pilot.id, source)
    assert claimed.cargo == %{"industrial_parts" => 1}
    assert Inventory.cargo_tonnage(pilot.id) == 4
  end

  test "neutral assault and cargo seizure are separate once-only faction hits" do
    pilot = player_account_fixture()
    source = contact()

    assert {:ok, %{applied?: true, standing: -12}} =
      Piracy.record_attack(pilot.id, source)
    assert {:ok, %{applied?: false, standing: -12, delta: 0}} =
      Piracy.record_attack(pilot.id, source)

    assert {:ok, %{standing: -30}} = Piracy.seize_surrender(pilot.id, source)
    assert Piracy.reputations(pilot.id)[source.faction_id] == -30

    assert {:error, :no_civilian_faction_penalty} =
      Piracy.record_attack(pilot.id, %{source | classification: :hostile_contact})
    assert {:error, :unknown_faction} =
      Piracy.record_attack(pilot.id, %{source | faction_id: "forged_faction"})
    assert Piracy.faction_standing(pilot.id, source.faction_id) == -30
  end

  test "outlaw or hostile seizure does not penalize a civilian faction" do
    pilot = player_account_fixture()
    hostile = contact(%{
      disposition: :hostile,
      classification: :hostile_contact,
      faction_id: "independent_raiders",
      cargo: %{"industrial_parts" => 40}
    })

    assert {:ok, %{cargo: %{"industrial_parts" => 4}, standing: 0}} =
      Piracy.seize_surrender(pilot.id, hostile)
    assert Piracy.reputations(pilot.id) == %{}
  end

  test "unrecognized or fractional strategic stock cannot create cargo" do
    pilot = player_account_fixture()
    source = contact(%{cargo: %{"arbitrary_super_item" => 200, "industrial_parts" => 9}})

    assert {:error, :no_cargo_space_or_stock} =
      Piracy.seize_surrender(pilot.id, source)
    assert Inventory.cargo_manifest(pilot.id) == %{}
    assert Piracy.faction_standing(pilot.id, source.faction_id) == 0
  end
end
