defmodule Darkorbit.ShipConditionTest do
  use Darkorbit.DataCase

  import Darkorbit.AccountsFixtures

  alias Darkorbit.Fleet
  alias Darkorbit.ShipCondition
  alias Darkorbit.ShipStats

  test "one physical ship retains damage across reconnects and capacity changes" do
    account = player_account_fixture()
    {:ok, ship} = Fleet.get_active_ship(account.id)
    {:ok, stats} = ShipStats.calculate(account.id, ship.id, 1)

    assert {:ok, initial} = ShipCondition.load_or_initialize(account.id, ship.id, stats)
    report = %{initial | hull: initial.hull - 1, shields: 0}
    assert :ok = ShipCondition.save_verified(account.id, ship.id, report)
    assert :ok = ShipCondition.save_verified(account.id, ship.id, report)

    assert {:ok, ^report} =
             ShipCondition.load_or_initialize(account.id, ship.id, stats)

    assert {:error, :unverified_repair} =
             ShipCondition.save_verified(account.id, ship.id, initial)

    assert {:ok, updated} = ShipCondition.load_or_initialize(account.id, ship.id,
      %{hit_points: initial.max_hull + 100, shields: initial.max_shields + 100})
    assert updated.hull == report.hull
    assert updated.shields == report.shields
    assert updated.max_hull == initial.max_hull + 100
  end

  test "ownership is enforced for every read and write" do
    owner = player_account_fixture()
    stranger = player_account_fixture()
    {:ok, ship} = Fleet.get_active_ship(owner.id)
    {:ok, stats} = ShipStats.calculate(owner.id, ship.id, 1)

    assert {:error, :ship_not_owned} =
             ShipCondition.load_or_initialize(stranger.id, ship.id, stats)
    assert {:ok, initial} = ShipCondition.load_or_initialize(owner.id, ship.id, stats)
    assert {:error, :ship_not_owned} =
             ShipCondition.save_verified(stranger.id, ship.id, initial)
  end

  test "destroyed hull does not respawn at full health" do
    owner = player_account_fixture()
    {:ok, ship} = Fleet.get_active_ship(owner.id)
    {:ok, stats} = ShipStats.calculate(owner.id, ship.id, 1)

    assert {:ok, initial} = ShipCondition.load_or_initialize(owner.id, ship.id, stats)
    destroyed = %{initial | hull: 0, shields: 0, status: :destroyed}
    assert :ok = ShipCondition.save_verified(owner.id, ship.id, destroyed)
    assert {:ok, ^destroyed} =
             ShipCondition.load_or_initialize(owner.id, ship.id, stats)
    assert {:error, :invalid_ship_condition} =
             ShipCondition.save_verified(owner.id, ship.id, %{destroyed | hull: 1})
  end
end
