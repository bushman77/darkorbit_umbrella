defmodule DarkorbitWeb.WorldStreamDelta do
  @moduledoc """
  Transport-only sparse delta between authoritative simulation snapshots.
  The channel maintains a per-subscriber baseline. No client state is trusted.
  """

  @spec between(map(), map()) :: map()
  def between(%{entities: before, tick: base_tick} = old,
              %{entities: after_entities, tick: tick} = current)
      when is_list(before) and is_list(after_entities) do
    previous = Map.new(before, &{&1.id, &1})
    active = MapSet.new(after_entities, & &1.id)

    updated =
      Enum.flat_map(after_entities, fn entity ->
        case Map.fetch(previous, entity.id) do
          :error -> [entity]
          {:ok, prior} ->
            changes = changed_fields(prior, entity)
            if changes == %{}, do: [], else: [Map.put(changes, :id, entity.id)]
        end
      end)

    removed = for entity <- before, not MapSet.member?(active, entity.id), do: entity.id

    %{
      base_tick: base_tick,
      tick: tick,
      entities: updated,
      removed: removed,
      changes: changed_fields(
        Map.drop(old, [:entities, :tick]),
        Map.drop(current, [:entities, :tick])
      )
    }
  end

  defp changed_fields(old, current) do
    Enum.reduce(current, %{}, fn {key, value}, acc ->
      if Map.has_key?(old, key) and Map.get(old, key) == value,
        do: acc,
        else: Map.put(acc, key, value)
    end)
  end
end
