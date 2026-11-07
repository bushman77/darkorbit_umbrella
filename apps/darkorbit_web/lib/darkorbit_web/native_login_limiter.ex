defmodule DarkorbitWeb.NativeLoginLimiter do
  @moduledoc """
  Bounded in-memory authentication attempt counter for the native API.
  It is deliberately scoped to each username (not the Caddy loopback IP).
  """
  use GenServer

  @window_seconds 300
  @max_attempts 8

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  @impl true
  def init(state), do: {:ok, state}

  def allow?(username) when is_binary(username) do
    GenServer.call(__MODULE__, {:attempt, String.downcase(username)})
  end

  def clear(username) when is_binary(username) do
    GenServer.cast(__MODULE__, {:clear, String.downcase(username)})
  end

  @impl true
  def handle_call({:attempt, key}, _from, state) do
    now = System.monotonic_time(:second)

    {count, expires_at} =
      case Map.get(state, key) do
        {count, expires_at} when expires_at > now -> {count + 1, expires_at}
        _ -> {1, now + @window_seconds}
      end

    # Periodic prune prevents an unbounded map from accumulating old usernames.
    state =
      if map_size(state) > 1_000 do
        Enum.reduce(state, %{}, fn {k, {n, expiry}}, acc ->
          if expiry > now, do: Map.put(acc, k, {n, expiry}), else: acc
        end)
      else
        state
      end

    {:reply, count <= @max_attempts, Map.put(state, key, {count, expires_at})}
  end

  @impl true
  def handle_cast({:clear, key}, state), do: {:noreply, Map.delete(state, key)}
end
