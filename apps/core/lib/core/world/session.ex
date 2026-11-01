defmodule Core.World.Session do
  @moduledoc "An in-memory player connection bound to one map and entity."

  @enforce_keys [:id, :player_id, :map_id, :entity_id]
  defstruct [:id, :player_id, :map_id, :entity_id]

  @type t :: %__MODULE__{
          id: pos_integer(),
          player_id: term(),
          map_id: String.t(),
          entity_id: term()
        }
end
