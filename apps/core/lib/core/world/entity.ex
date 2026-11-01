defmodule Core.World.Entity do
  @moduledoc "Authoritative runtime state for one connected player ship."

  alias Core.World.Position

  @enforce_keys [:id, :player_id, :session_id, :position, :speed]
  defstruct [:id, :player_id, :session_id, :position, :destination, :speed]

  @type t :: %__MODULE__{
          id: term(),
          player_id: term(),
          session_id: pos_integer(),
          position: Position.t(),
          destination: Position.t() | nil,
          speed: number()
        }
end
