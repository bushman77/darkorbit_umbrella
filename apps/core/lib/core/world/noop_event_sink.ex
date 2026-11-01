defmodule Core.World.NoopEventSink do
  @moduledoc false

  @behaviour Core.World.EventSink

  @impl true
  def broadcast(_map_id, _event, _payload), do: :ok
end
