defmodule Core.World.PlanetaryCollision do
  @moduledoc """
  Server-owned fatal planet contact for orbital maps.

  A ship crossing the planetary exclusion sphere is destroyed at the first
  point of contact, even when an entire sphere was traversed between ticks.
  The exclusion radius is defined by the authoritative map, not by the client.
  No atmospheric entry, shield immunity or damage-over-time is simulated yet.
  """

  alias Core.World.Entity
  alias Core.World.MapDefinition
  alias Core.World.Position

  @zero_vector %{x: 0.0, y: 0.0, z: 0.0}
  @zero_rotation %{yaw: 0.0, pitch: 0.0, roll: 0.0}

  @spec resolve(Entity.t(), Entity.t(), MapDefinition.t()) ::
          {:ok, Entity.t()} | {:crashed, Entity.t()}
  def resolve(%Entity{} = previous, %Entity{} = moved, %MapDefinition{planet: nil}),
    do: {:ok, moved}

  def resolve(%Entity{status: :destroyed}, %Entity{} = moved, %MapDefinition{}),
    do: {:ok, moved}

  def resolve(%Entity{} = previous, %Entity{} = moved,
              %MapDefinition{planet: %{center: center, exclusion_radius: radius}})
      when is_number(radius) and radius > 0 do
    case first_contact(previous.position, moved.position, center, radius) do
      :clear ->
        {:ok, moved}

      {:hit, %Position{} = contact} ->
        # Planets are environmental hazards. Contact is fatal regardless of
        # remaining hull or shields, and can never generate NPC kill credit.
        {:crashed,
         %{moved |
           position: contact,
           hull: 0,
           shields: 0,
           status: :destroyed,
           destination: nil,
           route_waypoints: [],
           navigation_mode: :manual,
           throttle: 0.0,
           cruise_speed: 0.0,
           velocity: @zero_vector,
           rotation_input: %{yaw: 0.0, pitch: 0.0, roll: 0.0},
           angular_velocity: @zero_rotation,
           target_id: nil,
           engaged_target_id: nil}}
    end
  end

  @doc """
  First intersection of a 3D path segment with a closed sphere. Returns
  :clear when the segment misses, even if both endpoints are outside.
  Starting already inside is immediately fatal (defensive consistency).
  """
  @spec first_contact(Position.t(), Position.t(), map(), number()) ::
          :clear | {:hit, Position.t()}
  def first_contact(%Position{} = from, %Position{} = to,
                    %{x: cx, y: cy, z: cz}, radius)
      when is_number(radius) and radius > 0 do
    fx = from.x - cx
    fy = from.y - cy
    fz = from.z - cz
    dx = to.x - from.x
    dy = to.y - from.y
    dz = to.z - from.z
    radius_squared = radius * radius
    start_squared = fx * fx + fy * fy + fz * fz

    cond do
      start_squared <= radius_squared ->
        {:hit, from}

      true ->
        a = dx * dx + dy * dy + dz * dz
        b = 2.0 * (fx * dx + fy * dy + fz * dz)
        c = start_squared - radius_squared
        discriminant = b * b - 4.0 * a * c

        if a <= 0.0 or discriminant < 0.0 do
          :clear
        else
          t = (-b - :math.sqrt(discriminant)) / (2.0 * a)

          if t >= 0.0 and t <= 1.0 do
            {:hit, %Position{
              x: from.x + dx * t,
              y: from.y + dy * t,
              z: from.z + dz * t
            }}
          else
            :clear
          end
        end
    end
  end
end
