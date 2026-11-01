defmodule Core.World.SessionManager do
  @moduledoc "Owns live player sessions and prevents duplicate connections."

  use GenServer

  alias Core.World.Session

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.fetch!(opts, :name))
  end

  @spec open(GenServer.server(), term(), String.t()) ::
          {:ok, Session.t()} | {:error, :already_connected}
  def open(server, player_id, map_id) when is_binary(map_id) do
    GenServer.call(server, {:open, player_id, map_id})
  end

  @spec fetch(GenServer.server(), pos_integer()) :: {:ok, Session.t()} | :error
  def fetch(server, session_id), do: GenServer.call(server, {:fetch, session_id})

  @spec fetch_player(GenServer.server(), term()) :: {:ok, Session.t()} | :error
  def fetch_player(server, player_id), do: GenServer.call(server, {:fetch_player, player_id})

  @spec close(GenServer.server(), pos_integer()) :: {:ok, Session.t()} | :error
  def close(server, session_id), do: GenServer.call(server, {:close, session_id})

  @impl true
  def init(:ok), do: {:ok, %{by_id: %{}, by_player: %{}}}

  @impl true
  def handle_call({:open, player_id, map_id}, _from, state) do
    if Map.has_key?(state.by_player, player_id) do
      {:reply, {:error, :already_connected}, state}
    else
      session_id = System.unique_integer([:positive, :monotonic])

      session = %Session{
        id: session_id,
        player_id: player_id,
        map_id: map_id,
        entity_id: player_id
      }

      new_state = %{
        by_id: Map.put(state.by_id, session_id, session),
        by_player: Map.put(state.by_player, player_id, session_id)
      }

      {:reply, {:ok, session}, new_state}
    end
  end

  def handle_call({:fetch, session_id}, _from, state) do
    {:reply, Map.fetch(state.by_id, session_id), state}
  end

  def handle_call({:fetch_player, player_id}, _from, state) do
    result =
      with {:ok, session_id} <- Map.fetch(state.by_player, player_id) do
        Map.fetch(state.by_id, session_id)
      end

    {:reply, result, state}
  end

  def handle_call({:close, session_id}, _from, state) do
    case Map.pop(state.by_id, session_id) do
      {nil, _by_id} ->
        {:reply, :error, state}

      {%Session{} = session, by_id} ->
        new_state = %{
          by_id: by_id,
          by_player: Map.delete(state.by_player, session.player_id)
        }

        {:reply, {:ok, session}, new_state}
    end
  end
end
