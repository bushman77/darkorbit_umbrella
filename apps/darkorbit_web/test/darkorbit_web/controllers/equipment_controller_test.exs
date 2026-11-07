defmodule DarkorbitWeb.EquipmentControllerTest do
  use DarkorbitWeb.ConnCase

  import Darkorbit.AccountsFixtures

  alias Darkorbit.Fleet
  alias Darkorbit.Inventory
  alias Darkorbit.Loadouts
  alias Darkorbit.ShipStats

  test "equipment locker requires an authenticated account", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/equipment")) == ~p"/login"
    assert redirected_to(post(conn, ~p"/equipment", %{})) == ~p"/login"
  end

  test "Sunracer shows authentic starter systems and two independent configurations", %{conn: conn} do
    account = verified_player_account_fixture()
    conn = signed_in(conn, account)
    response = html_response(get(conn, ~p"/equipment"), 200)
    doc = LazyHTML.from_document(response)

    assert response =~ "Sunracer"
    assert response =~ "Garnet"
    assert response =~ "Forward-1"
    assert response =~ "300"
    assert response =~ "4 tonnes"
    assert Enum.count(LazyHTML.query(doc, "#equipment-locker")) == 1
    assert Enum.count(LazyHTML.query(doc, "#laser-0")) == 1
    assert Enum.count(LazyHTML.query(doc, "#generator-0")) == 1
    assert Enum.count(LazyHTML.query(doc, "[name='_csrf_token']")) == 3

    response = html_response(get(signed_in(build_conn(), account),
      ~p"/equipment?config=2"), 200)
    assert response =~ "Configuration 2"
  end

  test "server-owned inventory transfers change the selected Sunracer beam", %{conn: conn} do
    account = verified_player_account_fixture()
    assert {:ok, _} = Inventory.add_equipment(account.id, "beryl", 1)
    conn = signed_in(conn, account)

    response = html_response(get(conn, ~p"/equipment"), 200)
    assert response =~ "Beryl beam (15)"

    request = %{"config" => "1", "field" => "lasers",
                "slot" => "0", "item_id" => "beryl"}

    result = post(signed_in(build_conn(), account), ~p"/equipment", request)
    assert redirected_to(result) == ~p"/equipment?config=1"

    assert {:ok, stats} = ShipStats.for_active_ship(account.id, 1)
    assert stats.damage == 15
    assert Inventory.equipment_count(account.id, "beryl") == 0

    {:ok, active} = Fleet.get_active_ship(account.id)
    assert hd(Loadouts.get_loadout(active.id, 1).lasers["ship"]) == "beryl"
    assert {:ok, original} = ShipStats.for_active_ship(account.id, 2)
    assert original.damage == 10

    unequip = %{"config" => "1", "field" => "lasers",
                "slot" => "0", "item_id" => ""}
    result = post(signed_in(build_conn(), account), ~p"/equipment", unequip)
    assert redirected_to(result) == ~p"/equipment?config=1"
    assert Inventory.equipment_count(account.id, "beryl") == 1
    assert {:ok, restored} = ShipStats.for_active_ship(account.id, 1)
    assert restored.damage == 10
  end

  test "switching the active equipment configuration is server-owned", %{conn: conn} do
    account = verified_player_account_fixture()
    conn = signed_in(conn, account)

    assert Darkorbit.World.active_configuration(account.id) == 1
    res = post(conn, ~p"/equipment/activate", %{"config" => "2"})
    assert redirected_to(res) == ~p"/equipment?config=2"
    assert Darkorbit.World.active_configuration(account.id) == 2

    {:ok, status} = Darkorbit.World.player_status(account.id,
      Darkorbit.World.active_configuration(account.id))
    assert status.configuration.number == 2

    res = post(signed_in(build_conn(), account),
      ~p"/equipment/activate", %{"config" => "3"})
    assert redirected_to(res) == ~p"/equipment"
    assert Darkorbit.World.active_configuration(account.id) == 2
  end

  test "fabricated inventory and unusable slots cannot grant gear", %{conn: _conn} do
    account = verified_player_account_fixture()
    other = verified_player_account_fixture()
    {:ok, _} = Inventory.add_equipment(other.id, "sapphire", 1)
    for params <- [
      %{"config" => "1", "field" => "lasers", "slot" => "0", "item_id" => "sapphire"},
      %{"config" => "1", "field" => "lasers", "slot" => "1", "item_id" => "beryl"},
      %{"config" => "1", "field" => "lasers", "slot" => "-1", "item_id" => "beryl"},
      %{"config" => "1", "field" => "lasers", "slot" => "not-a-number", "item_id" => "beryl"},
      %{"config" => "42", "field" => "lasers", "slot" => "0", "item_id" => "beryl"}
    ] do
      assert redirected_to(post(signed_in(build_conn(), account),
        ~p"/equipment", params)) =~ "/equipment"
    end

    assert {:ok, unchanged} = ShipStats.for_active_ship(account.id, 1)
    assert unchanged.damage == 10
    assert Inventory.equipment_count(other.id, "sapphire") == 1
  end

  defp signed_in(conn, account) do
    Plug.Test.init_test_session(conn,
      player_id: account.id, account_session_id: account.session_id)
  end
end
