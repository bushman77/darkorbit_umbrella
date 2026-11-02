defmodule Core.Combat do
  @moduledoc """
  Pure, deterministic combat rules shared by players and NPCs.

  Callers provide authoritative entity state and the current simulation tick.
  This module never reads wall-clock time or accepts client-provided weapon
  values.
  """

  @player_attack_range 720.0
  @type damage_result :: %{
          requested_damage: non_neg_integer(),
          shield_damage: non_neg_integer(),
          hull_damage: non_neg_integer(),
          destroyed: boolean()
        }

  @spec player_weapon(map(), pos_integer()) :: %{
          damage: non_neg_integer(),
          attack_range: float(),
          attack_cooldown_ticks: pos_integer()
        }
  def player_weapon(stats, tick_ms) do
    action = Core.Combat.ActionCatalog.pulse_emitter()

    %{
      damage: non_negative_integer(Map.get(stats, :damage, 0)),
      attack_range: @player_attack_range,
      attack_cooldown_ticks: cooldown_ticks(action.cooldown_ms, tick_ms)
    }
  end

  @spec cooldown_ticks(pos_integer(), pos_integer()) :: pos_integer()
  def cooldown_ticks(cooldown_ms, tick_ms)
      when is_integer(cooldown_ms) and cooldown_ms > 0 and is_integer(tick_ms) and tick_ms > 0 do
    max(1, ceil(cooldown_ms / tick_ms))
  end

  @spec validate_attack(map(), map(), non_neg_integer()) :: :ok | {:error, atom()}
  def validate_attack(attacker, target, current_tick) do
    cond do
      not alive?(attacker) ->
        {:error, :attacker_destroyed}

      not alive?(target) ->
        {:error, :target_destroyed}

      not valid_target?(attacker, target) ->
        {:error, :invalid_target}

      non_negative_integer(Map.get(attacker, :damage, 0)) == 0 ->
        {:error, :weapon_unarmed}

      not cooldown_ready?(current_tick, Map.get(attacker, :next_attack_tick, 0)) ->
        {:error, :weapon_cooldown}

      not in_range?(attacker, target, Map.get(attacker, :attack_range, 0)) ->
        {:error, :out_of_range}

      true ->
        :ok
    end
  end

  @spec valid_target?(map(), map()) :: boolean()
  def valid_target?(%{kind: :player}, %{kind: :npc} = target), do: alive?(target)
  def valid_target?(%{kind: :npc}, %{kind: :player} = target), do: alive?(target)
  def valid_target?(_attacker, _target), do: false

  @spec cooldown_ready?(integer(), integer()) :: boolean()
  def cooldown_ready?(current_tick, next_attack_tick)
      when is_integer(current_tick) and is_integer(next_attack_tick) do
    current_tick >= next_attack_tick
  end

  def cooldown_ready?(_current_tick, _next_attack_tick), do: false

  @spec in_range?(map(), map(), number()) :: boolean()
  def in_range?(attacker, target, range) when is_number(range) and range >= 0 do
    with %{x: attacker_x, y: attacker_y} <- Map.get(attacker, :position),
         %{x: target_x, y: target_y} <- Map.get(target, :position),
         true <- finite_number?(attacker_x) and finite_number?(attacker_y),
         true <- finite_number?(target_x) and finite_number?(target_y) do
      delta_x = target_x - attacker_x
      delta_y = target_y - attacker_y
      attacker_z = Map.get(attacker.position, :z, 0.0)
      target_z = Map.get(target.position, :z, 0.0)
      delta_z = target_z - attacker_z

      finite_number?(attacker_z) and finite_number?(target_z) and
        delta_x * delta_x + delta_y * delta_y + delta_z * delta_z <= range * range
    else
      _invalid_position -> false
    end
  end

  def in_range?(_attacker, _target, _range), do: false

  @spec apply_damage(map(), number()) :: {map(), damage_result()}
  def apply_damage(target, raw_damage) do
    damage = non_negative_integer(raw_damage)
    shields = non_negative_integer(Map.get(target, :shields, 0))
    hull = non_negative_integer(Map.get(target, :hull, 0))
    absorption = target |> Map.get(:shield_absorption, 0.0) |> normalized_absorption()
    shield_damage = min(shields, round(damage * absorption))
    hull_damage = min(hull, max(0, damage - shield_damage))
    remaining_shields = max(0, shields - shield_damage)
    remaining_hull = max(0, hull - hull_damage)
    destroyed? = remaining_hull == 0

    updated_target =
      target
      |> Map.put(:shields, remaining_shields)
      |> Map.put(:hull, remaining_hull)
      |> maybe_destroy(destroyed?)

    {updated_target,
     %{
       requested_damage: damage,
       shield_damage: shield_damage,
       hull_damage: hull_damage,
       destroyed: destroyed?
     }}
  end

  @spec alive?(map()) :: boolean()
  def alive?(entity) when is_map(entity) do
    Map.get(entity, :status, :alive) == :alive and
      non_negative_integer(Map.get(entity, :hull, 0)) > 0
  end

  def alive?(_entity), do: false

  @spec next_attack_tick(map(), non_neg_integer()) :: non_neg_integer()
  def next_attack_tick(attacker, current_tick) do
    current_tick + max(1, non_negative_integer(Map.get(attacker, :attack_cooldown_ticks, 1)))
  end

  defp maybe_destroy(target, false), do: target

  defp maybe_destroy(target, true) do
    target =
      target
      |> Map.put(:status, :destroyed)
      |> Map.put(:destination, nil)
      |> Map.put(:target_id, nil)
      |> maybe_clear_engagement()

    if Map.has_key?(target, :state), do: Map.put(target, :state, :destroyed), else: target
  end

  defp maybe_clear_engagement(target) do
    if Map.has_key?(target, :engaged_target_id),
      do: Map.put(target, :engaged_target_id, nil),
      else: target
  end

  defp non_negative_integer(value) when is_integer(value), do: max(0, value)
  defp non_negative_integer(value) when is_float(value), do: max(0, round(value))
  defp non_negative_integer(_value), do: 0

  defp normalized_absorption(value) when is_number(value), do: min(1.0, max(0.0, value * 1.0))
  defp normalized_absorption(_value), do: 0.0

  defp finite_number?(value) when is_integer(value), do: true

  defp finite_number?(value) when is_float(value),
    do: value == value and value not in [:infinity, :neg_infinity]

  defp finite_number?(_value), do: false
end
