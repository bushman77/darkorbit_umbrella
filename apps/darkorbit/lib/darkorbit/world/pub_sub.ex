defmodule Darkorbit.World.PubSub do
  @moduledoc "Phoenix PubSub delivery adapter for core world events."

  @behaviour Core.World.EventSink

  @impl true
  def broadcast(map_id, event, payload) do
    Phoenix.PubSub.broadcast(Darkorbit.PubSub, topic(map_id), {event, payload})
  end

  @spec topic(String.t()) :: String.t()
  def topic(map_id), do: "world:#{map_id}"
end
