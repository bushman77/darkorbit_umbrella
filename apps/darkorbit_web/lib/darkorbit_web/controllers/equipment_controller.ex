defmodule DarkorbitWeb.EquipmentController do
  use DarkorbitWeb, :controller

  alias Core.Equipment.Catalog, as: EquipmentCatalog
  alias Darkorbit.Accounts
  alias Darkorbit.World
  alias Core.Ships.Catalog, as: ShipCatalog
  alias Darkorbit.Cargo.Catalog, as: CargoCatalog
  alias Darkorbit.Fleet
  alias Darkorbit.Inventory
  alias Darkorbit.Loadouts
  alias Darkorbit.ShipStats

  @doc "Authenticated equipment locker for the active ship."
  def show(conn, params) do
    account = conn.assigns.current_player
    configuration = requested_configuration(params)

    with {:ok, owned} <- Fleet.get_active_ship(account.id),
         {:ok, ship} <- ShipCatalog.fetch(owned.ship_id),
         %{} = loadout <- Loadouts.get_loadout(owned.id, configuration),
         {:ok, stats} <- ShipStats.calculate(account.id, owned.id, configuration),
         %{} = inventory <- Inventory.get_equipment_by_user_id(account.id) do
      items =
        EquipmentCatalog.all()
        |> Enum.map(fn item ->
          %{id: item.id, name: item.name, category: item.category,
            count: Inventory.equipment_count(account.id, item.id)}
        end)

      render(conn, :show,
        page_title: "Ship equipment · " <> ship.name,
        ship: ship,
        pilot: account,
        stats: stats,
        configuration: configuration,
        active_configuration: World.active_configuration(account.id),
        loadout: loadout,
        inventory: inventory,
        inventory_items: items,
        cargo_tonnage: Inventory.cargo_tonnage(account.id),
        cargo_manifest: Inventory.cargo_manifest(account.id),
        cargo_catalog: CargoCatalog.all(),
        lasers: Enum.filter(items, &(&1.category == :laser)),
        generators: Enum.filter(items, &(&1.category in [:generator, :shield])),
        laser_slots: loadout.lasers["ship"] |> Enum.take(ship.laser_slots) |> Enum.with_index(),
        generator_slots: loadout.generators["ship"] |> Enum.take(ship.generator_slots) |> Enum.with_index()
      )
    else
      _ -> conn |> put_flash(:error, "Equipment locker unavailable.") |> redirect(to: ~p"/play")
    end
  end

  @doc "Activate one of the two owned configurations for the next cockpit session."
  def activate(conn, %{"config" => cfg}) do
    case parse_configuration(cfg) do
      {:ok, configuration} ->
        case Accounts.activate_configuration(conn.assigns.current_player.id, configuration) do
          {:ok, _} ->
            conn
            |> put_flash(:info, "Configuration #{configuration} selected. Return to cockpit to apply it.")
            |> redirect(to: ~p"/equipment?config=#{configuration}")

          {:error, _} ->
            conn |> put_flash(:error, "Could not activate configuration.")
                 |> redirect(to: ~p"/equipment")
        end

      _ ->
        conn |> put_flash(:error, "Invalid configuration.") |> redirect(to: ~p"/equipment")
    end
  end

  def activate(conn, _params) do
    conn |> put_flash(:error, "Invalid configuration.") |> redirect(to: ~p"/equipment")
  end

  @doc "An equip/unequip transfer is performed only for this account's active ship."
  def update(conn, %{"config" => cfg, "field" => field, "slot" => slot,
                     "item_id" => item_id}) do
    account = conn.assigns.current_player

    with {:ok, configuration} <- parse_configuration(cfg),
         true <- is_binary(slot),
         {index, ""} when index >= 0 <- Integer.parse(slot),
         true <- field in ["lasers", "generators"],
         true <- is_binary(item_id),
         {:ok, owned} <- Fleet.get_active_ship(account.id),
         %{} = loadout <- Loadouts.get_loadout(owned.id, configuration) do
      item = if item_id == "", do: nil, else: item_id

      result =
        case {field, item} do
          {"lasers", nil} ->
            Loadouts.unequip_laser_to_inventory(account.id, loadout.id, "ship", index)

          {"lasers", id} ->
            Loadouts.equip_laser_from_inventory(account.id, loadout.id, "ship", index, id)

          {"generators", nil} ->
            Loadouts.unequip_generator_to_inventory(account.id, loadout.id, "ship", index)

          {"generators", id} ->
            Loadouts.equip_generator_from_inventory(account.id, loadout.id, "ship", index, id)
        end

      case result do
        {:ok, _} -> put_flash(conn, :info, "Configuration saved. Reopen the cockpit to apply it.")
        {:error, reason} -> put_flash(conn, :error, "Unable to fit equipment: #{inspect(reason)}")
      end
      |> redirect(to: ~p"/equipment?config=#{configuration}")
    else
      _ -> conn |> put_flash(:error, "Invalid equipment command.") |> redirect(to: ~p"/equipment")
    end
  end

  def update(conn, _params) do
    conn |> put_flash(:error, "Invalid equipment command.") |> redirect(to: ~p"/equipment")
  end

  defp requested_configuration(%{"config" => value}) do
    case parse_configuration(value) do
      {:ok, config} -> config
      _ -> 1
    end
  end

  defp requested_configuration(_), do: 1

  defp parse_configuration("1"), do: {:ok, 1}
  defp parse_configuration("2"), do: {:ok, 2}
  defp parse_configuration(_), do: {:error, :invalid_configuration}
end
