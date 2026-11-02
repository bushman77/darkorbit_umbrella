defmodule Core.Combat.ActionCatalogTest do
  use ExUnit.Case, async: true

  alias Core.Combat.ActionCatalog

  test "defines X1 ammunition separately from the server pulse emitter weapon" do
    hotbar = ActionCatalog.hotbar()

    assert Enum.map(hotbar, & &1.key) == ~w(1 2 3 4 5 6 7 8 9 0)

    assert [
             %{
               slot: 1,
               action: %{
                 id: "x1_laser",
                 type: :ammunition,
                 activation_mode: :toggle,
                 weapon_id: "pulse_emitter"
               }
             }
             | empty
           ] = hotbar

    assert %{
             id: "pulse_emitter",
             type: :weapon,
             cooldown_ms: 700
           } = ActionCatalog.pulse_emitter()

    assert ActionCatalog.x1_laser() == List.first(hotbar).action
    assert Enum.all?(empty, &is_nil(&1.action))
    assert {:ok, nil} = ActionCatalog.fetch_slot(10)
    assert {:error, :invalid_action_slot} = ActionCatalog.fetch_slot(0)
    assert {:error, :invalid_action_slot} = ActionCatalog.fetch_slot("1")
  end
end
