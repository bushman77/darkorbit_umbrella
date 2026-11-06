defmodule Darkorbit.Piracy do
  @moduledoc """
  Database-backed consequences for authenticated, map-verified SOL encounters.

  Source identities and manifests MUST originate in Core.Universe.Navigation;
  never call these mutations with a Phoenix/client-supplied manifest.
  Account -> equipment is the global lock ordering for cargo transactions.
  A source vessel/voyage can yield at most one cargo receipt across all pilots.

  V1 exchange rate: ten abstract strategic manifest units equal one one-tonne
  player cargo crate. Remainders remain aboard the strategic vessel.
  """

  import Ecto.Query, warn: false

  alias Core.Factions
  alias Core.Ships.Catalog, as: ShipCatalog
  alias Darkorbit.Accounts.PlayerAccount
  alias Darkorbit.Cargo.Catalog, as: CargoCatalog
  alias Darkorbit.Inventory.PlayerEquipment
  alias Darkorbit.Piracy.{CargoClaim, FactionEvent, FactionStanding}
  alias Darkorbit.Repo

  @strategic_units_per_crate 10
  @attack_delta -12
  @seizure_delta -18

  @doc "Persistent standings keyed by SOL faction ID, independent of MMO company."
  def reputations(user_id) when is_integer(user_id) and user_id > 0 do
    from(s in FactionStanding, where: s.user_id == ^user_id,
      select: {s.faction_id, s.standing})
    |> Repo.all()
    |> Map.new()
  end

  def reputations(_), do: %{}

  @doc "One lawful penalty per confirmed hostile attack on a neutral vessel/voyage."
  def record_attack(user_id, verified)
      when is_integer(user_id) and user_id > 0 and is_map(verified) do
    with :ok <- valid_identity(verified),
         true <- verified.disposition == :neutral,
         true <- verified.classification == :neutral_flyby do
      Repo.transaction(fn ->
        lock_account!(user_id)
        event_key = "solar:attack:#{verified.contact_id}:#{verified.voyage_number}:#{user_id}"
        apply_faction_event!(user_id, verified.faction_id, event_key,
          "unlawful_attack", @attack_delta)
      end)
    else
      false -> {:error, :no_civilian_faction_penalty}
      error -> error
    end
  end

  def record_attack(_user_id, _verified), do: {:error, :invalid_identity}

  @doc """
  Claim the first valid surrender of this real strategic ship/voyage.
  Caller must have map-verified surrender and the matching server-held claim.

  No client chooses cargo contents or amounts. A full hold aborts without
  consuming the receipt; duplicates return the original receipt unchanged.
  """
  def seize_surrender(user_id, verified)
      when is_integer(user_id) and user_id > 0 and is_map(verified) do
    with :ok <- valid_identity(verified),
         true <- is_map(verified.cargo) do
      Repo.transaction(fn ->
        account = lock_account!(user_id)

        existing =
          from(c in CargoClaim,
            where: c.contact_id == ^verified.contact_id and
                   c.voyage_number == ^verified.voyage_number,
            lock: "FOR UPDATE")
          |> Repo.one()

        cond do
          existing != nil and
              existing.user_id == user_id and
              existing.encounter_id == verified.encounter_id ->
            claim_result(existing, faction_standing(user_id, existing.faction_id))

          existing != nil ->
            Repo.rollback(:cargo_already_claimed)

          true ->
            equipment =
              from(e in PlayerEquipment,
                where: e.user_id == ^user_id, lock: "FOR UPDATE")
              |> Repo.one()

            with %PlayerEquipment{} <- equipment,
                 {:ok, ship} <- ShipCatalog.fetch(account.ship_id),
                 {:ok, used} <- hold_mass(Map.get(equipment.items || %{}, "cargo", %{})) do
              remaining = max(0, ship.cargo_capacity - used)
              {claimed, debit} = allocate(verified.cargo, remaining)

              if map_size(claimed) == 0, do: Repo.rollback(:no_cargo_space_or_stock)

              # In the same transaction as the uniqueness receipt and faction
              # event, guaranteeing a retry never double-credits inventory.
              old = Map.get(equipment.items || %{}, "cargo", %{})
              updated = Enum.reduce(claimed, old, fn {id, n}, acc ->
                Map.update(acc, id, n, &(&1 + n))
              end)

              case Repo.update(Ecto.Changeset.change(equipment,
                     items: Map.put(equipment.items || %{}, "cargo", updated))) do
                {:ok, _} -> :ok
                {:error, reason} -> Repo.rollback(reason)
              end

              changeset = Ecto.Changeset.change(%CargoClaim{},
                user_id: user_id, contact_id: verified.contact_id,
                voyage_number: verified.voyage_number,
                encounter_id: verified.encounter_id,
                faction_id: verified.faction_id, source_manifest: verified.cargo,
                cargo_units: claimed, strategic_debit: debit)

              case Repo.insert(changeset, on_conflict: :nothing,
                     conflict_target: [:contact_id, :voyage_number], returning: true) do
                {:ok, %{id: id} = row} when is_integer(id) ->
                  standing =
                    if verified.disposition == :neutral and
                         verified.classification == :neutral_flyby do
                      consequence = apply_faction_event!(user_id, verified.faction_id,
                        "solar:seizure:#{verified.contact_id}:#{verified.voyage_number}:#{user_id}",
                        "cargo_seizure", @seizure_delta)
                      consequence.standing
                    else
                      faction_standing(user_id, verified.faction_id)
                    end

                  claim_result(row, standing)

                {:ok, _} -> Repo.rollback(:cargo_already_claimed)
                {:error, reason} -> Repo.rollback(reason)
              end
            else
              nil -> Repo.rollback(:cargo_hold_unavailable)
              :error -> Repo.rollback(:unknown_ship)
              {:error, reason} -> Repo.rollback(reason)
              _ -> Repo.rollback(:cargo_hold_unavailable)
            end
        end
      end)
    else
      false -> {:error, :invalid_manifest}
      error -> error
    end
  end

  def seize_surrender(_user_id, _verified), do: {:error, :invalid_identity}

  @doc "Read-only, pilot-scoped claim receipt for a completed encounter."
  def claim_receipt(user_id, encounter_id)
      when is_integer(user_id) and user_id > 0 and is_binary(encounter_id) do
    case Repo.get_by(CargoClaim, user_id: user_id, encounter_id: encounter_id) do
      %CargoClaim{} = row -> {:ok, claim_result(row, faction_standing(user_id, row.faction_id))}
      nil -> {:error, :claim_not_found}
    end
  end

  def claim_receipt(_, _), do: {:error, :claim_not_found}

  @doc "Last five server-verified cargo claims for an authenticated account."
  def recent_claims(user_id) when is_integer(user_id) and user_id > 0 do
    from(c in CargoClaim, where: c.user_id == ^user_id,
      order_by: [desc: c.inserted_at], limit: 5,
      select: %{contact_id: c.contact_id, voyage_number: c.voyage_number,
        faction_id: c.faction_id, cargo: c.cargo_units, at: c.inserted_at})
    |> Repo.all()
  end

  def recent_claims(_), do: []

  @doc "Read-only account stance; no implicit faction creation."
  def faction_standing(user_id, faction_id) do
    case Repo.one(from(s in FactionStanding,
           where: s.user_id == ^user_id and s.faction_id == ^faction_id,
           select: s.standing)) do
      nil -> 0
      value -> value
    end
  end

  defp valid_identity(%{
         contact_id: contact_id, voyage_number: voyage, encounter_id: encounter_id,
         faction_id: faction, disposition: disposition, classification: classification
       })
       when is_binary(contact_id) and byte_size(contact_id) > 0 and
            is_integer(voyage) and voyage > 0 and
            is_binary(encounter_id) and byte_size(encounter_id) > 0 and
            is_binary(faction) and
            is_atom(disposition) and is_atom(classification) do
    if Factions.exists?(faction), do: :ok, else: {:error, :unknown_faction}
  end

  defp valid_identity(_), do: {:error, :invalid_identity}

  defp lock_account!(user_id) do
    case from(a in PlayerAccount, where: a.id == ^user_id, lock: "FOR UPDATE")
         |> Repo.one() do
      %PlayerAccount{} = account -> account
      nil -> Repo.rollback(:unknown_pilot)
    end
  end

  defp hold_mass(manifest) when is_map(manifest) do
    Enum.reduce_while(manifest, {:ok, 0}, fn {id, count}, {:ok, used} ->
      case CargoCatalog.fetch(id) do
        {:ok, item} when is_integer(count) and count >= 0 ->
          {:cont, {:ok, used + item.mass_tonnes * count}}
        _ ->
          {:halt, {:error, :invalid_cargo_hold}}
      end
    end)
  end

  defp hold_mass(_), do: {:error, :invalid_cargo_hold}

  defp allocate(manifest, remaining_tonnes) do
    manifest
    |> Enum.sort_by(fn {id, _} -> to_string(id) end)
    |> Enum.reduce({%{}, %{}, remaining_tonnes}, fn {id, units}, {loaded, debit, available} ->
      case CargoCatalog.fetch(id) do
        {:ok, item} when is_integer(units) and units >= @strategic_units_per_crate ->
          amount = min(div(units, @strategic_units_per_crate),
            div(available, item.mass_tonnes))
          if amount > 0 do
            {Map.put(loaded, id, amount),
             Map.put(debit, id, amount * @strategic_units_per_crate),
             available - amount * item.mass_tonnes}
          else
            {loaded, debit, available}
          end

        _ ->
          {loaded, debit, available}
      end
    end)
    |> then(fn {loaded, debit, _} -> {loaded, debit} end)
  end

  defp apply_faction_event!(user_id, faction, key, kind, delta) do
    changeset = Ecto.Changeset.change(%FactionEvent{},
      user_id: user_id, faction_id: faction, event_key: key,
      kind: kind, delta: delta)

    case Repo.insert(changeset, on_conflict: :nothing, conflict_target: [:event_key],
           returning: true) do
      {:ok, %{id: id}} when is_integer(id) ->
        standing =
          from(s in FactionStanding,
            where: s.user_id == ^user_id and s.faction_id == ^faction,
            lock: "FOR UPDATE")
          |> Repo.one()

        current = if standing, do: standing.standing, else: 0
        next = max(-100, min(100, current + delta))

        if standing do
          Repo.update!(Ecto.Changeset.change(standing, standing: next))
        else
          Repo.insert!(Ecto.Changeset.change(%FactionStanding{},
            user_id: user_id, faction_id: faction, standing: next))
        end

        %{applied?: true, delta: next - current, standing: next, faction_id: faction}

      {:ok, _} ->
        %{applied?: false, delta: 0, standing: faction_standing(user_id, faction),
          faction_id: faction}

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp claim_result(claim, standing) do
    %{cargo: claim.cargo_units, strategic_debit: claim.strategic_debit,
      contact_id: claim.contact_id, voyage_number: claim.voyage_number,
      faction_id: claim.faction_id, standing: standing}
  end
end
