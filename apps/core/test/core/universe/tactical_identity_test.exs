defmodule Core.Universe.TacticalIdentityTest do
  use ExUnit.Case, async: true

  alias Core.Universe.Navigation

  test "only the pilot holding a live claim can read strategic cargo and faction" do
    server = :"#{__MODULE__}.#{System.unique_integer([:positive])}"

    start_supervised!({Navigation,
      name: server,
      auto_tick: false,
      tick_ms: 1_000,
      event_sink: fn _map_id, _event, _payload -> :ok end
    })

    assert {:ok, _} = Navigation.set_course(server, 700, "venus")

    pending =
      Enum.find_value(1..160, fn _ ->
        assert :ok = Navigation.tick(server)
        {:ok, voyage} = Navigation.snapshot(server, 700)
        voyage.pending_encounter
      end)

    assert %{id: encounter_id, classification: :neutral_flyby} = pending
    assert {:ok, %{tactical_encounter: tactical}} =
      Navigation.enter_tactical(server, 700, encounter_id)
    assert tactical.id == encounter_id

    assert {:ok, contact} = Navigation.tactical_contact(server, 700, encounter_id)
    assert contact.encounter_id == encounter_id
    assert contact.contact_id == tactical.contact_id
    assert contact.voyage_number == tactical.voyage_number
    assert contact.faction_id == "helios_couriers"
    assert contact.cargo["medical_supplies"] == 48
    assert contact.ship_class == "scow"

    assert {:error, :no_tactical_encounter} =
      Navigation.tactical_contact(server, 701, encounter_id)
    assert {:error, :no_tactical_encounter} =
      Navigation.tactical_contact(server, 700, "forged-id")

    assert :ok = Navigation.set_faction_standing(server, 700, "helios_couriers", -30)
    assert :sys.get_state(server).pilot_reputations[700]["helios_couriers"] == -30
    assert :sys.get_state(server).pilot_reputations[701] == %{} or
           not Map.has_key?(:sys.get_state(server).pilot_reputations, 701)
  end
end
