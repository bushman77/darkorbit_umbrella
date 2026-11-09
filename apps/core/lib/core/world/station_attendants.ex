defmodule Core.World.StationAttendants do
  @moduledoc """
  Scripted, stationary station personnel. These are conversational service
  contacts, NOT tactical NPC ships. All interaction eligibility is checked
  against a MapServer-owned pilot position and authenticated docked ship.

  No conversation topic can mutate credits, cargo, inventory or ship state.
  Real service transactions will be added as separate validated operations.
  """

  @interaction_radius 12.0
  @contacts [
    %{
      id: "repair", room_id: "repair_bay", name: "Mara Venn",
      role: "Repair Engineer", x: -49.0, z: -143.0, color: 0x68b98a,
      greeting: "Welcome to Repairs. I inspect hull integrity and shield condition before authorizing any work.",
      topics: [
        %{id: "condition", label: "Inspect my ship's condition"},
        %{id: "work", label: "How will repairs work?"}
      ],
      responses: %{
        "work" => "The repair bench is installed, but the paid repair transaction is not active yet. I will not charge credits or alter your ship until that service is verified."
      }
    },
    %{
      id: "trade", room_id: "trade_exchange", name: "Tarek Sol",
      role: "Trade Broker", x: 49.0, z: -143.0, color: 0x56bbcb,
      greeting: "This is the Trade Exchange. Cargo comes and goes with our visiting traders.",
      topics: [
        %{id: "market", label: "What goods do you trade?"},
        %{id: "prices", label: "Can I see live prices?"}
      ],
      responses: %{
        "market" => "Our exchange will handle legal cargo purchases and sales. All inventories and credits will be verified by the station's transaction ledger.",
        "prices" => "The public trading desk is not connected to its live order book yet. I won't quote prices that haven't been supplied by the market."
      }
    },
    %{
      id: "outfitting", room_id: "outfitting", name: "Ilya Quill",
      role: "Ship Outfitter", x: -49.0, z: -181.0, color: 0xb7c86b,
      greeting: "Outfitting counter. Weapons, shields, generators, and equipment belong on the right mounting points.",
      topics: [
        %{id: "equipment", label: "What equipment can I install?"},
        %{id: "fitting", label: "How do fittings work?"}
      ],
      responses: %{
        "equipment" => "This counter will manage compatible ship equipment, but purchasing and installation are not active from this dialogue yet.",
        "fitting" => "A proper fitting checks hull configuration, installed slots, inventory ownership, and power before committing changes."
      }
    },
    %{
      id: "resupply", room_id: "resupply", name: "Sera Vale",
      role: "Supply Officer", x: 49.0, z: -181.0, color: 0x86c775,
      greeting: "Supply depot. We provision spacecraft for the next run.",
      topics: [
        %{id: "stock", label: "What supplies are available?"},
        %{id: "replenish", label: "Can you replenish my ship?"}
      ],
      responses: %{
        "stock" => "This depot will distribute consumables, ammunition, and other stocked provisions as each system becomes available.",
        "replenish" => "Automatic replenishment is not commissioned yet. Nothing will be deducted from your account or applied to your ship."
      }
    },
    %{
      id: "missions", room_id: "mission_office", name: "Juno Rook",
      role: "Mission Liaison", x: -16.0, z: -211.0, color: 0x8ca8dd,
      greeting: "Mission Office. You'll find contracts and assignments here once they are authorized by the station.",
      topics: [
        %{id: "contracts", label: "Do you have any assignments?"},
        %{id: "rewards", label: "How are rewards handled?"}
      ],
      responses: %{
        "contracts" => "Mission listings are not live yet. When they are, you'll be able to review objectives and accept an authorized contract here.",
        "rewards" => "Bounties and mission rewards must be credited by the server after the objectives are verified. No reward can be claimed through dialogue alone."
      }
    },
    %{
      id: "comms", room_id: "communications", name: "Eno Kade",
      role: "Communications Officer", x: 16.0, z: -211.0, color: 0x69c9c5,
      greeting: "Communications desk. I handle station notices, contacts, and operational information.",
      topics: [
        %{id: "contacts", label: "How do I contact other ships?"},
        %{id: "station", label: "Tell me about this starbase"}
      ],
      responses: %{
        "contacts" => "Use your ship's communication systems when you launch. A station contact directory will appear here after its network integration is complete.",
        "station" => "You're inside Green Starbase in the SOL system. The main hangar connects through an airlock to the concourse, trading offices, maintenance, and ship services."
      }
    }
  ]

  @doc "Stable lightweight roster replicated once with the world snapshot."
  def public do
    Enum.map(@contacts, fn entry ->
      Map.take(entry, [:id, :room_id, :name, :role, :x, :z, :color])
    end)
  end

  @doc "Validate room, distance and topic, then return scripted dialogue."
  def talk(pose, ship, attendant_id, topic)
      when is_binary(attendant_id) and is_binary(topic) do
    case Enum.find(@contacts, &(&1.id == attendant_id)) do
      nil -> {:error, :unknown_station_attendant}
      attendant -> talk_to(attendant, pose, ship, topic)
    end
  end
  def talk(_pose, _ship, _attendant_id, _topic),
    do: {:error, :invalid_station_dialogue}

  defp talk_to(attendant, %{room_id: room_id, x: x, z: z}, ship, topic)
       when is_number(x) and is_number(z) do
    dist2 = :math.pow(x - attendant.x, 2) + :math.pow(z - attendant.z, 2)
    cond do
      room_id != attendant.room_id or dist2 > @interaction_radius * @interaction_radius ->
        {:error, :station_attendant_out_of_range}

      topic != "greeting" and not Enum.any?(attendant.topics, &(&1.id == topic)) ->
        {:error, :invalid_station_topic}

      true ->
        message =
          case {attendant.id, topic} do
            {_, "greeting"} -> attendant.greeting
            {"repair", "condition"} ->
              "Your docked ship reports hull #{ship.hull}/#{ship.max_hull} and shields #{ship.shields}/#{ship.max_shields}. This is a live inspection; no repairs have been performed."
            _ -> Map.fetch!(attendant.responses, topic)
          end

        {:ok, %{
          attendant_id: attendant.id,
          name: attendant.name,
          role: attendant.role,
          room_id: attendant.room_id,
          message: message,
          topics: attendant.topics
        }}
    end
  end
  defp talk_to(_attendant, _pose, _ship, _topic),
    do: {:error, :station_attendant_out_of_range}
end
