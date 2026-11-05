# Space Nova HUD / first implementation pass

Visual direction: dark navy / near-black command deck, cyan edge illumination,
fine orbital-grid detail, compact monospace instrument labels, beveled panels,
and a persistent navigation frame. Designed to feel like an interactive game,
not a centered responsive marketing page.

## Implemented on `sbs`

- Atlas: full-window HUD rail, active navigation mode, functional ship-loadout
  link, left operations + real-time traffic feed, central SVG orbital chart,
  right celestial catalog and transit console, compact controls and key strip.
- Pilot authorization and recruitment: split command-deck briefing and form
  console, preserving server-owned POST actions, CSRF and verification.
- Registration confirmation: matching command-deck visuals.
- Website: shared brand treatment and stronger nav / feature panel chrome.
- Tauri: matching integrated launcher frame, retaining local/live server origin
  validation, browser session redirects and all existing button bindings.

The new interface intentionally does **not** invent missions, credits, hull
percentages, pilot status or contacts. The original mockup is a visual target,
not proof that corresponding backend systems exist.

## Technical guardrails

- Shared CSS variables `--nova-*` and `hud-*` classes live in
  `apps/darkorbit_web/assets/css/app.css`; launcher equivalents are in
  `clients/tauri/ui/launcher.css` because the Tauri launcher is standalone.
- Existing IDs used by `navigation_computer.mjs` and the world client remain
  intact. Navigation and combat logic are not altered.
- No Tauri IPC capabilities are added; the remote Phoenix page remains
  sandboxed. HTTP is loopback-only in the Tauri launcher.
- The left Atlas panel displays live sensor contacts from the existing DOM
  node, not hard-coded sample content.
- Atlas is responsive: three zones on wide displays, two at mid-size,
  stacked on compact screens. Respect reduced-motion preferences.
- The cockpit WebGL canvas and SBS eye presentation remain authoritative
  and visually separate from the flat Atlas overlay.

## Next visual passes

1. Validate actual Linux WebKitGTK rendering and input behavior at 1360×860.
2. Add live ship telemetry and verified mission data only when those APIs are
   available; do not substitute fake data.
3. Update equipment, encounter prompts, cockpit floating HUD, disconnected
   state and telemetry readouts using the same shared tokens.
4. User-test keyboard focus, accessibility, text overflow, zoom and VR/SBS
   comfort, then refine spacing against the reference concept.
