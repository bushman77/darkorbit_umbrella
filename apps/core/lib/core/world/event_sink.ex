defmodule Core.World.EventSink do
  @moduledoc """
  Optional delivery boundary for world events.

  A sink can be a module implementing this behaviour or a three-argument
  function. Failures are isolated from the authoritative map process.
  """

  @callback broadcast(String.t(), atom(), map()) :: :ok | term()

  @spec dispatch(module() | (String.t(), atom(), map() -> term()), String.t(), atom(), map()) ::
          :ok
  def dispatch(sink, map_id, event, payload) when is_function(sink, 3) do
    safe_dispatch(fn -> sink.(map_id, event, payload) end)
  end

  def dispatch(sink, map_id, event, payload) when is_atom(sink) do
    safe_dispatch(fn -> sink.broadcast(map_id, event, payload) end)
  end

  defp safe_dispatch(dispatch) do
    dispatch.()
    :ok
  rescue
    _exception -> :ok
  catch
    _kind, _reason -> :ok
  end
end
