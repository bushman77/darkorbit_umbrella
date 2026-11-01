defmodule Darkorbit.TransactionConcurrencyTest do
  use Darkorbit.DataCase

  import Darkorbit.AccountsFixtures
  import Ecto.Query

  alias Darkorbit.Accounts.PlayerAccount
  alias Darkorbit.Fleet
  alias Darkorbit.Inventory
  alias Darkorbit.Loadouts
  alias Darkorbit.Repo
  alias Ecto.Adapters.SQL.Sandbox

  @moduletag :unboxed

  test "simultaneous withdrawals cannot consume the same laser twice" do
    account = create_committed_account()
    delete_account_on_exit(account.id)

    unboxed(fn ->
      assert {:ok, _equipment} = Inventory.add_lasers(account.id, "lf1", 1)
    end)

    results =
      run_concurrently([
        fn -> Inventory.remove_laser(account.id, "lf1", 1) end,
        fn -> Inventory.remove_laser(account.id, "lf1", 1) end
      ])

    assert Enum.count(results, &match?({:ok, _equipment}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :not_enough_lasers})) == 1
    assert unboxed(fn -> Inventory.laser_count(account.id, "lf1") end) == 0
  end

  test "simultaneous equips cannot duplicate one inventory item across configurations" do
    account = create_committed_account()
    delete_account_on_exit(account.id)

    {configuration_one, configuration_two} =
      unboxed(fn ->
        [ship] = Fleet.list_ships_for_user(account.id)
        [configuration_one, configuration_two] = Loadouts.list_loadouts_for_player_ship(ship.id)
        assert {:ok, _equipment} = Inventory.add_lasers(account.id, "lf1", 1)
        {configuration_one, configuration_two}
      end)

    results =
      run_concurrently([
        fn ->
          Loadouts.equip_laser_from_inventory(
            account.id,
            configuration_one.id,
            "ship",
            0,
            "lf1"
          )
        end,
        fn ->
          Loadouts.equip_laser_from_inventory(
            account.id,
            configuration_two.id,
            "ship",
            0,
            "lf1"
          )
        end
      ])

    assert Enum.count(results, &match?({:ok, _loadout}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :not_enough_lasers})) == 1

    equipped_count =
      unboxed(fn ->
        [configuration_one, configuration_two]
        |> Enum.map(&Loadouts.get_player_ship_loadout!(&1.id))
        |> Enum.count(&(Enum.at(&1.lasers["ship"], 0) == "lf1"))
      end)

    assert equipped_count == 1
    assert unboxed(fn -> Inventory.laser_count(account.id, "lf1") end) == 0
  end

  defp create_committed_account do
    unboxed(fn -> player_account_fixture() end)
  end

  defp delete_account_on_exit(account_id) do
    on_exit(fn ->
      unboxed(fn ->
        Repo.delete_all(from(account in PlayerAccount, where: account.id == ^account_id))
      end)
    end)
  end

  defp run_concurrently(operations) do
    parent = self()
    supervisor = start_supervised!(Task.Supervisor)

    tasks =
      Enum.map(operations, fn operation ->
        Task.Supervisor.async_nolink(supervisor, fn ->
          send(parent, {:ready, self()})

          receive do
            :run -> unboxed(operation)
          end
        end)
      end)

    Enum.each(tasks, fn task ->
      assert_receive {:ready, task_pid} when task_pid == task.pid
    end)

    Enum.each(tasks, &send(&1.pid, :run))
    Enum.map(tasks, &Task.await/1)
  end

  defp unboxed(operation), do: Sandbox.unboxed_run(Repo, operation)
end
