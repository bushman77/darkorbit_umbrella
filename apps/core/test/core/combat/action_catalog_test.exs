defmodule Core.Combat.ActionCatalogTest do
  use ExUnit.Case, async: true

  alias Core.Combat.ActionCatalog

  test "defines a ten-slot future-ready hotbar with only the pulse emitter assigned" do
    hotbar = ActionCatalog.hotbar()

    assert Enum.map(hotbar, & &1.key) == ~w(1 2 3 4 5 6 7 8 9 0)
    assert [%{slot: 1, action: %{id: "pulse_emitter", kind: :weapon}} | empty] = hotbar
    assert Enum.all?(empty, &is_nil(&1.action))
    assert {:ok, nil} = ActionCatalog.fetch_slot(10)
    assert {:error, :invalid_action_slot} = ActionCatalog.fetch_slot(0)
    assert {:error, :invalid_action_slot} = ActionCatalog.fetch_slot("1")
  end
end
