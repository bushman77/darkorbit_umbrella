defmodule Core.World.PlanetaryProximity do
  @moduledoc """
  Authoritative orbital proximity warnings, separate from fatal collision.

  Levels are based on the distance to the planet's *lethal exclusion radius*
  rather than the rendered sphere. No warning in legacy maps without a planet.
  Recalculate from live server positions; do not accept coordinates or warning
  state from the client. A status transition emits one event, not one per tick.
  """

  alias Core.World.MapDefinition

  @caution_factor 1.55
  @critical_factor 1.20

  @type level :: :clear | :caution | :critical

  @spec warning(map(), MapDefinition.t()) :: map() | nil
  def warning(_position, %MapDefinition{planet: nil}), do: nil

  def warning(%{x: x, y: y, z: z},
              %MapDefinition{planet: %{body_id: id, center: center,
                                       exclusion_radius: boundary}})
      when is_number(boundary) and boundary > 0 do
    dx = x - center.x
    dy = y - center.y
    dz = z - center.z
    distance = :math.sqrt(dx * dx + dy * dy + dz * dz)

    level =
      cond do
        distance <= boundary * @critical_factor -> :critical
        distance <= boundary * @caution_factor -> :caution
        true -> :clear
      end

    if level == :clear do
      nil
    else
      %{
        planet_id: id,
        level: level,
        clearance_km: max(0.0, distance - boundary),
        distance_km: distance,
        lethal_radius_km: boundary
      }
    end
  end

  @spec level(map() | nil) :: level()
  def level(nil), do: :clear
  def level(%{level: value}), do: value

  @doc "Emitted only when a live pilot crosses a warning-band boundary."
  @spec transition(term(), map() | nil, map() | nil, non_neg_integer()) ::
          map() | nil
  def transition(_id, previous, current, _tick)
      when previous == current and previous == nil, do: nil

  def transition(id, previous, current, tick) do
    old_level = level(previous)
    next_level = level(current)

    if old_level == next_level do
      nil
    else
      %{
        entity_id: id,
        planet_id: (current || previous).planet_id,
        previous_level: old_level,
        level: next_level,
        clearance_km: if(current, do: current.clearance_km, else: nil),
        tick: tick
      }
    end
  end
end
