defmodule Core.NPC.CruiseRoute do
  @moduledoc """
  Project an already established SOL traffic route into a short tactical lane.

  The strategic cruise remains owned by Core.Universe.Navigation and continues
  independently. This is a local-space *representation* of its authoritative
  direction, not a new SOL route or a player-chosen NPC destination.

  In a planet-centred combat map a straight line towards a nearby planet can
  intersect its collision sphere. In that case we use the smallest safe
  lateral deflection, never a square patrol or a new arbitrary destination.
  """
  alias Core.Universe.Sol
  alias Core.World.MapDefinition
  alias Core.World.Movement
  alias Core.World.PlanetaryCollision
  alias Core.World.Position

  @lane_length 6_000.0
  @planet_buffer 350.0
  @deviations [0.0, 0.35, -0.35, 0.70, -0.70, 1.05, -1.05, 1.57, -1.57]

  @spec project(String.t(), String.t(), Position.t(), MapDefinition.t()) ::
          {:ok, map()} | {:error, atom()}
  def project(origin_id, destination_id, %Position{} = position, %MapDefinition{} = map) do
    with true <- origin_id != destination_id,
         {:ok, origin} <- Sol.game_position_km(origin_id),
         {:ok, destination} <- Sol.game_position_km(destination_id),
         {dx, dy} <- {destination.x - origin.x, destination.y - origin.y},
         length when length > 0.0 <- :math.sqrt(dx * dx + dy * dy) do
      ux = dx / length
      uy = dy / length

      route =
        Enum.find_value(@deviations, fn angle ->
          x = ux * :math.cos(angle) - uy * :math.sin(angle)
          y = ux * :math.sin(angle) + uy * :math.cos(angle)

          target = %Position{
            x: position.x + x * @lane_length,
            y: position.y + y * @lane_length,
            z: position.z
          }

          if safe_segment?(map, position, target) do
            %{origin_id: origin_id, destination_id: destination_id,
              destination: target, heading: %{x: x, y: y, z: 0.0},
              deflected?: angle != 0.0}
          end
        end)

      if route, do: {:ok, route}, else: {:error, :no_safe_cruise_lane}
    else
      _ -> {:error, :invalid_cruise_route}
    end
  end

  def project(_from, _to, _position, _map), do: {:error, :invalid_cruise_route}

  @spec lane_length() :: float()
  def lane_length, do: @lane_length

  defp safe_segment?(map, from, destination) do
    match?({:ok, _}, Movement.destination(map, destination)) and
      case map.planet do
        %{center: center, exclusion_radius: exclusion} ->
          PlanetaryCollision.first_contact(from, destination, center,
            exclusion + @planet_buffer) == :clear

        _ ->
          true
      end
  end
end
