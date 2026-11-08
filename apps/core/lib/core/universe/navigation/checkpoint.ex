defmodule Core.Universe.Navigation.Checkpoint do
  @moduledoc """
  Versioned, validated SOL voyage. Only durable navigation fields cross this
  boundary: transient NPC encounter decisions and tactical leases are never
  restored after process loss.
  """
  alias Core.Universe.Sol
  @limit 1.0e12

  def dump(v) do
    %{
      "version" => 1, "status" => Atom.to_string(v.status),
      "location_id" => v.location_id, "origin_id" => v.origin_id,
      "arrival_origin_id" => v.arrival_origin_id,
      "destination_id" => v.destination_id,
      "voyage_number" => v.voyage_number, "free_flight" => v.free_flight,
      "position_km" => v.position_km, "origin_position_km" => v.origin_position_km,
      "destination_position_km" => v.destination_position_km,
      "cruise_speed_km_s" => v.cruise_speed_km_s,
      "travel_distance_km" => v.travel_distance_km,
      "distance_travelled_km" => v.distance_travelled_km,
      "elapsed_ms" => v.elapsed_ms, "duration_ms" => v.duration_ms
    }
  end

  def load(%{"version" => 1} = data) do
    status = case data["status"] do
      "idle" -> :idle
      "traveling" -> :traveling
      _ -> nil
    end
    location = data["location_id"]
    origin = data["origin_id"]
    arrival = data["arrival_origin_id"]
    destination = data["destination_id"]
    position = point(data["position_km"])
    from = point(data["origin_position_km"])
    to = point(data["destination_position_km"])
    voyage = data["voyage_number"]
    free? = data["free_flight"]
    speed = data["cruise_speed_km_s"]
    distance = data["travel_distance_km"]
    travelled = data["distance_travelled_km"]
    elapsed = data["elapsed_ms"]
    duration = data["duration_ms"]

    good? = status in [:idle, :traveling] and
      Enum.all?([location, origin, arrival, destination], &body_or_nil?/1) and
      is_map(position) and is_map(from) and
      is_integer(voyage) and voyage >= 0 and is_boolean(free?) and
      Enum.all?([speed, distance, travelled], &nonnegative?/1) and
      is_integer(elapsed) and elapsed >= 0 and
      is_integer(duration) and duration >= 0 and
      ((status == :idle and not free? and is_nil(destination) and
         (is_nil(location) or at_body?(position, location))) or
       (status == :traveling and is_map(to) and speed > 0 and distance > 0 and
         duration > 0 and elapsed <= duration and travelled <= distance))

    if good? do
      {:ok, %{
        system_id: "sol", status: status, location_id: location,
        origin_id: origin, arrival_origin_id: arrival, destination_id: destination,
        voyage_number: voyage, free_flight: free?,
        propulsion_mode: if(status == :traveling and not free?,
          do: :interplanetary_cruise, else: :conventional),
        position_km: position, origin_position_km: from,
        destination_position_km: to, cruise_speed_km_s: speed,
        travel_distance_km: distance, distance_travelled_km: travelled,
        elapsed_ms: elapsed, duration_ms: duration,
        pending_encounter: nil, tactical_encounter: nil
      }}
    else
      {:error, :invalid_checkpoint}
    end
  end
  def load(_), do: {:error, :invalid_checkpoint}

  defp point(nil), do: nil
  defp point(map) when is_map(map) do
    x = Map.get(map, "x", Map.get(map, :x))
    y = Map.get(map, "y", Map.get(map, :y))
    z = Map.get(map, "z", Map.get(map, :z))
    if Enum.all?([x, y, z], &finite?/1), do: %{x: x, y: y, z: z}, else: nil
  end
  defp point(_), do: nil

  defp finite?(n) when is_number(n), do: n == n and abs(n) < @limit
  defp finite?(_), do: false
  defp nonnegative?(n), do: finite?(n) and n >= 0
  defp body_or_nil?(nil), do: true
  defp body_or_nil?(id), do: Sol.destination?(id)
  defp at_body?(position, id) do
    case Sol.game_position_km(id) do
      {:ok, center} ->
        :math.sqrt(:math.pow(position.x - center.x, 2) +
          :math.pow(position.y - center.y, 2) +
          :math.pow(position.z - center.z, 2)) < 1.0e-5
      _ -> false
    end
  end
end
