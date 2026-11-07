defmodule DarkorbitWeb.WorldStreamPolicy do
  @moduledoc """
  Per-subscriber presentation policy for world replication.

  Nearby actors and the pilot's own ship receive every authoritative
  simulation update. Motion for distant actors is replicated at most every
  500 ms; condition, combat, spawning and navigation changes are never
  delayed by this policy. Simulation physics remain 100% server-owned.
  """

  @near_radius 5_000.0
  @near_radius_squared @near_radius * @near_radius

  @motion_fields [
    :position, :position_3d, :velocity, :angular_velocity,
    :attitude, :orientation, :angle, :throttle, :forward_speed
  ]

  # Changes requiring immediate replication, regardless of distance.
  @urgent_fields [
    :hull, :shields, :max_hull, :max_shields, :status, :state,
    :target_id, :engaged_target_id, :next_attack_tick, :navigation_mode,
    :flight_mode, :destination, :destination_3d, :route_waypoints,
    :route_waypoints_3d, :ship_instance_id
  ]

  @spec project(map(), map(), term()) :: map()
  def project(%{entities: entities, tick: tick, tick_ms: tick_ms} = current,
              %{entities: old_entities}, player_id)
      when is_list(entities) and is_list(old_entities) and is_integer(tick) do
    interval = max(1, ceil_ticks(500, tick_ms))

    if rem(tick, interval) == 0 do
      current
    else
      own = Enum.find(entities, &(Map.get(&1, :player_id) == player_id))
      previous = Map.new(old_entities, &{&1.id, &1})

      if own do
        projected =
          Enum.map(entities, fn entity ->
            previous_actor = Map.get(previous, entity.id)
            cond do
              entity.id == own.id or is_nil(previous_actor) ->
                entity

              near?(own, entity) or urgent_change?(previous_actor, entity) ->
                entity

              true ->
                Map.merge(entity, Map.take(previous_actor, @motion_fields))
            end
          end)

        %{current | entities: projected}
      else
        current
      end
    end
  end

  @spec near?(map(), map()) :: boolean()
  def near?(%{position_3d: origin}, %{position_3d: destination}) do
    with %{x: x1, y: y1, z: z1} <- origin,
         %{x: x2, y: y2, z: z2} <- destination,
         true <- Enum.all?([x1, y1, z1, x2, y2, z2], &is_number/1) do
      (x2 - x1) * (x2 - x1) +
        (y2 - y1) * (y2 - y1) +
        (z2 - z1) * (z2 - z1) <= @near_radius_squared
    else
      _ -> true
    end
  end

  def near?(_own, _other), do: true

  # No-op tick suppression: at least one tick heartbeat per second
  # to update the client's world clock and detect stalled feeds.
  @spec transmit?(map(), pos_integer()) :: boolean()
  def transmit?(%{entities: changed, removed: removed, changes: metadata,
                  base_tick: base, tick: tick}, tick_ms)
      when tick_ms > 0 do
    changed != [] or removed != [] or metadata != %{} or
      tick - base >= max(1, ceil_ticks(1_000, tick_ms))
  end

  # Compatible with Elixir 1.15+ (Integer.ceil_div/2 requires 1.20+).
  defp ceil_ticks(milliseconds, tick_ms) when tick_ms > 0,
    do: max(1, div(milliseconds + tick_ms - 1, tick_ms))

  defp urgent_change?(previous, current) do
    Enum.any?(@urgent_fields, fn key ->
      Map.get(previous, key) != Map.get(current, key)
    end)
  end
end
