defmodule DarkorbitWeb.HelmetSurrender do
  @moduledoc """
  Pilot-scoped, visual-only surrender state for a paired SBS headset.

  No commands, cargo or reputation data are exposed. Source is the
  authoritative, public world snapshot; the handset never declares surrender.
  """

  @none %{surrendered: false}

  def from_world(%{entities: entities}, player_id)
      when is_list(entities) and not is_nil(player_id) do
    suffix = "-" <> to_string(player_id)

    Enum.find_value(entities, @none, fn
      %{kind: :npc, state: :surrendered, npc_type_id: type_id} = npc
      when is_binary(type_id) ->
        if String.starts_with?(type_id, "solar-") and
             String.ends_with?(type_id, suffix) and
             Map.get(npc, :status) != :destroyed do
          %{surrendered: true, call_sign: Map.get(npc, :display_name) || "CONTACT"}
        end

      _ ->
        nil
    end)
  end

  def from_world(_map, _player_id), do: @none
end
