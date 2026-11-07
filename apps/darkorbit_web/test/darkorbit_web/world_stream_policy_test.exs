defmodule DarkorbitWeb.WorldStreamPolicyTest do
  use ExUnit.Case, async: true

  alias DarkorbitWeb.{WorldStreamDelta, WorldStreamPolicy}

  defp pilot(x \\ 0) do
    %{id: 3, player_id: 3, kind: :player, hull: 200,
      position_3d: %{x: x, y: 0, z: 0}, position: %{x: x, y: 0},
      velocity: %{x: 0, y: 0, z: 0}, attitude: %{yaw: 0, pitch: 0, roll: 0}}
  end

  defp remote(id, x, hull \\ 100) do
    %{id: id, kind: :npc, hull: hull, state: :cruise, status: :alive,
      position_3d: %{x: x, y: 0, z: 0}, position: %{x: x, y: 0},
      velocity: %{x: 20, y: 0, z: 0}, attitude: %{yaw: 0, pitch: 0, roll: 0}}
  end

  defp state(tick, entities) do
    %{tick: tick, tick_ms: 100, map_id: "sol:earth",
      planetary_warnings: [], entities: entities}
  end

  test "pilot and nearby enemies keep every 100ms position update" do
    old = state(0, [pilot(), remote("near", 100), remote("far", 10_000)])
    current = state(1, [pilot(8), remote("near", 125), remote("far", 10_050)])

    projected = WorldStreamPolicy.project(current, old, 3)
    assert Enum.find(projected.entities, &(&1.id == 3)).position_3d.x == 8
    assert Enum.find(projected.entities, &(&1.id == "near")).position_3d.x == 125
    assert Enum.find(projected.entities, &(&1.id == "far")).position_3d.x == 10_000

    delta = WorldStreamDelta.between(old, projected)
    assert WorldStreamPolicy.transmit?(delta, 100)
  end

  test "far enemy movement arrives every 500ms without baseline drift" do
    old = state(0, [pilot(), remote("far", 10_000)])

    for tick <- 1..4 do
      current = state(tick, [pilot(), remote("far", 10_000 + tick * 25)])
      projected = WorldStreamPolicy.project(current, old, 3)
      assert WorldStreamDelta.between(old, projected).entities == []
    end

    current = state(5, [pilot(), remote("far", 10_125)])
    delta = WorldStreamDelta.between(old, WorldStreamPolicy.project(current, old, 3))
    assert [%{id: "far", position_3d: %{x: 10_125}}] = delta.entities
  end

  test "far target hull loss and surrender are never held back" do
    old = state(0, [pilot(), remote("scow", 12_000)])
    current = state(1, [pilot(), %{remote("scow", 12_025, 40) | state: :surrendered}])
    projected = WorldStreamPolicy.project(current, old, 3)
    delta = WorldStreamDelta.between(old, projected)
    assert [%{id: "scow", hull: 40, state: :surrendered}] =
             Enum.map(delta.entities, &Map.take(&1, [:id, :hull, :state]))
  end

  test "new contacts and removals are immediate; no actor is silently hidden" do
    old = state(0, [pilot(), remote("scow", 12_000)])
    current = state(1, [pilot(), remote("dart", 30_000)])
    delta = WorldStreamDelta.between(old, WorldStreamPolicy.project(current, old, 3))
    assert delta.removed == ["scow"]
    assert [%{id: "dart", position_3d: %{x: 30_000}}] = delta.entities
  end

  test "idle ticks suppress packets but send heartbeat every second" do
    old = state(0, [pilot()])
    for tick <- 1..9 do
      delta = WorldStreamDelta.between(old, state(tick, [pilot()]))
      refute WorldStreamPolicy.transmit?(delta, 100)
    end
    delta = WorldStreamDelta.between(old, state(10, [pilot()]))
    assert WorldStreamPolicy.transmit?(delta, 100)
    assert delta.entities == []
  end

  test "synthetic traffic budget: far-moving actors transmit a small fraction of full frames" do
    actors = Enum.map(1..24, fn id -> remote("remote:#{id}", 10_000 + id * 300) end)
    baseline = state(0, [pilot() | actors])

    {sent_bytes, full_bytes, packet_count, _baseline} =
      Enum.reduce(1..50, {0, 0, 0, baseline}, fn tick, {sent, full, packets, last_sent} ->
        moving = Enum.map(1..24, fn id ->
          remote("remote:#{id}", 10_000 + id * 300 + tick * 16)
        end)
        current = state(tick, [pilot() | moving])
        projected = WorldStreamPolicy.project(current, last_sent, 3)
        delta = WorldStreamDelta.between(last_sent, projected)
        full_bytes = full + byte_size(Jason.encode!(current))

        if WorldStreamPolicy.transmit?(delta, current.tick_ms) do
          {sent + byte_size(Jason.encode!(delta)), full_bytes, packets + 1, projected}
        else
          {sent, full_bytes, packets, last_sent}
        end
      end)

    # Illustrative application-JSON sizes; not wire bytes including
    # WebSocket headers, TLS framing, other gameplay events or compression.
    assert packet_count == 10
    assert sent_bytes < full_bytes * 0.3
  end

  test "undefined own position is fail-open to normal replication" do
    old = state(0, [pilot(), remote("far", 12_000)])
    current = state(1, [%{pilot() | position_3d: nil}, remote("far", 12_100)])
    projected = WorldStreamPolicy.project(current, old, 3)
    assert Enum.find(projected.entities, &(&1.id == "far")).position_3d.x == 12_100
  end
end
