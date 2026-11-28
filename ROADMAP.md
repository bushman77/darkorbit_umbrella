## 2026-11-28 — SBS token comparison maintenance

- Replaced the deprecated ring comparison API in both invitation and session token verification with subtle::ConstantTimeEq; retained ring secure randomness and the existing token lifetime, single-use and TLS checks. Promoted the already locked subtle 2.6.1 to a direct dependency, without updating other Cargo packages.
- Added token comparison regression coverage (matching, mismatched, truncated and extended tokens). Cargo/Mix unavailable in editing environment; locked build, Rust tests, Mix precommit and manual SBS pairing remain pending. No release or deployment.

## 2026-11-27 — Docked repair HUD synchronization

- Local native playtest reported stale upper-left hull after complimentary repair. The server already returns its repaired parked condition; the native client now renders those confirmed values independently of the dialogue lifecycle. Join includes the authenticated ship's private condition, including docked reconnects; fitting reuses the same HUD presenter. Stale flight entities cannot overwrite docked health. No gameplay economy or repair authorization changes.
- Added JS regression coverage for damaged/repaired values, shield capacity, absent telemetry, repair callback ordering and reconnect wiring. Manual native repair/restart/launch and Elixir suite pending. No production deployment.

## 2026-11-27 — Leaked Routes: Secure the Record implementation candidate

- Extended existing chapter through step 10: Nadia's explicit local Venus offer, private Breaker-09 on a verified Venus-origin Earth-bound cruise (12% or later), attempt identity bound to pilot and voyage, map-verified surrender/victory, failure/retry and Juno's final 600-credit receipt. Records remain non-cargo. No new faction or system unlock; Chapter 2 remains design-only. Reuses existing tactical settlement and native UI, disables Breaker cargo seizure.
- Follow the Copy was manually played through stage 7 in the native client, with Earth/Venus communications, reconnect state, location and 1,100-credit inventory observed. Earlier local tests reported passing; latest native-only and M3 changes still require full Mix/Node/precommit and stock-ship playthrough. Wrong-planet and duplicate payout manual verification remain pending. Recovery uses runtime settlement receipt when present; if unavailable, retry a new voyage, never infer victory. No release/deployment.

## 2026-11-27 — Native-only gameplay entry

- Retired the hosted /play cockpit for authenticated and anonymous visitors; legacy links redirect to the landing page with a desktop-client notice. Browser login now returns to account/home services; landing offers the official GitHub release download. Retained registration, verification, recovery, equipment management, SBS /helmet and native JSON/socket APIs. Kept the shared HEEx cockpit template and renderer because the Tauri staging pipeline consumes them locally.
- Updated controller regressions for retired gameplay, account sessions and download links. Native markup tests retain cockpit coverage. This is product-surface retirement, not native-client attestation or an API access-control change. Existing native clients and production v0.3.9 are unchanged; local Mix/Node and manual native/SBS verification pending.

## 2026-11-27 — Leaked Routes: Follow the Copy implementation candidate

- Extends steps 4–7, exact Juno offer, Earth dispatch and Venus audit contacts, durable evidence and 400-credit receipt; validates session, voyage, destination, live entity and tactical state; reuses the shared dispatcher UI. M3 disabled; no migration, new cargo, faction or roster changes.
- Added pure transition, contact predicate, reward persistence and HUD tests. M1 production playthrough confirmed +200 credits and reconnect persistence. Elixir/Mix unavailable in editing environment; no automated execution claimed. Concurrent reward, channel integration, native/SBS and manual M2 playthrough remain pending. M2 pause not enabled. No release/deployment.

## 2026-11-27 — Leaked Routes: Distribution List implementation

- Added a chapter-specific pure transition module and additive progress row on authenticated acceptance, preserving the original prologue row and receipt. M1 uses existing Juno/Eno/Tarek positions, channel-bound offer/accept, two verified records in either order and transactional 200-credit receipt; HUD and radio identify Leaked Routes. Stops at step 4, incomplete, awaiting Follow the Copy. M2/M3, remote contacts and Breaker-09 are not enabled. No schema migration or new roster. Added regression tests; Mix/JS execution and manual playthrough pending (no Elixir runtime in editing environment).

## 2026-11-26 — Leaked Routes chapter design (design only)

- Drafted `docs/story/01-sol/01-leaked-routes.md` revision 0.1: three separately accepted main-campaign missions, local Green Starbase investigation, Earth dispatch and proposed Venus auditor Nadia Pell, private Breaker-09 return intercept, authored evidence provenance, full dialogue/HUD, proposed 200/400/600 credit receipts, ten-step compatibility mapping and recovery/test/playthrough plan. Culprit unresolved; lead is a clearing account for Following the Money. Cross-checked current station topics, dispatcher, private traffic, tactical outcomes, progress and reward code; local remote contacts, chapter dispatch and new encounter remain implementation dependencies. No gameplay, schema, roster or travel changes. Owner review required before implementation; no runtime tests executed.

## 2026-11-26 — Main-campaign mission design contract (design only)

- Added `docs/story/MISSION_DESIGN.md` revision 0.1: story-first scope, NPC acceptance, verified event and evidence contracts, per-pilot progression, transactional rewards, failure recovery, compatibility, chapter template and verification gates. Cross-checked current Prologue/Story modules and migration: prologue-specific dispatch, progress step range 1–10 and unique progress/reward receipts. Deferred optional, repeatable, epic equipment, faction and cooperative quests; no generic quest engine or runtime implementation. Linked story bible and updated agent guidance. Next: review and write Leaked Routes. Documentation only; no runtime tests run.

## 2026-11-26 — Approved historical timeline (design only)

- Added `docs/story/TIMELINE.md` revision 0.1 following owner approval: First Crossing year 0, Frontier Century 1–100, Great Expansion 100–250, Prosperity 250–400, Growing Tensions 400–480, Fracture 480–500, First Run year 500. Retained the four overarching ages; left exact incidents, founding dates, calendar and the Architects' chronology open. Distinguished shared historical chronology from live simulation and personal campaign progress. Updated lore, campaign, faction/character references, story index and agent guidance. Next: MISSION_DESIGN.md. Documentation only; no gameplay or runtime tests.

## 2026-11-26 — Persistent character and quest design (documentation only)

- Added `docs/story/CHARACTERS.md` revision 0.1 recording the agreed limited-sandbox MMO rule: permanent stationary NPCs remain at their home and service location while per-pilot narrative options evolve. Recorded all six existing Green Starbase contacts (including Tarek Sol and Sera Vale), local keys, rooms, positions, existing model mappings, Earth-orbit Ross, and Vesper-02/Corsair-17 encounter scope. Aligned campaign and faction references, added agent guidance and proposed additive/versioned mission design. No new roster, runtime behavior, service changes or travel permissions; source roster and placement cross-checked, no runtime tests executed.

## 2026-11-26 — Faction design bible (design only)

- Created `docs/story/FACTIONS.md` revision 0.1: six existing commercial/civilian organization IDs, nine SOL territorial authorities, Green Starbase neutrality, proposed economic dependencies, Directorate ideology and internal currents, relationship tensions, coalition and mission design constraints. Preserved `Core.Factions` identity and standing/warrant policies and First Run continuity. New profiles and slogans are proposals, not approved registry or gameplay changes; leaker, Directorate founding and leadership remain open. Linked campaign/lore/index and updated agent guidance. Documentation only; source identity and standing policy cross-checked, no runtime tests executed.

## 2026-11-26 — Accepted lore foundations (design only)

- Added `docs/story/LORE.md` revision 0.1 following owner approval of the historical premise and 500 years since humanity's first successful interstellar transit to Alpha Centauri. Recorded four ages, technological limitations, the gradual ancient-engineering revelation, and the distinction between accepted canon, working interpretations and open decisions. Updated campaign index, agent guidance and campaign references. No gameplay, travel permissions or database changes; documentation-only, no runtime tests run.

## 2026-11-26 — Galactic campaign bible (design only)

- Created `docs/story/CAMPAIGN.md` revision 0.1, story index and SOL workspace. Proposed five acts, 29 ordered system campaigns, a revelation ladder, recurring cast continuity, six SOL chapters including the implemented First Run, and narrative-to-gameplay constraints. The Directorate, ancient-network explanation, future settlements and endings are draft lore pending review. Existing prologue, catalogue, live travel lock and game code unchanged. Next milestone: approve campaign premise, then write and review Leaked Routes before implementation. Documentation-only; catalogue order checked, no runtime tests executed.

## 2026-11-26 — Opt-in remembered login

- Browser: unchecked by default; signed 30-day HttpOnly SameSite=Lax cookie (Secure on HTTPS), restores verified existing session, removed on logout. Desktop: distinct 30-day native-purpose credential exchanged at /api/native/resume for existing 900-second game-socket token. No password or bearer stored in web storage. Native vault scoped to validated server origin (Linux Secret Service via secret-tool; Windows Credential Manager). If unavailable, manual login works and user is informed; no plaintext fallback. Session rotation on login, logout and password reset revokes remembered credentials; resume does not extend their expiry. Offline logout clears local vault where available but cannot guarantee server revocation. Existing single-session-per-account policy unchanged. Added browser/native API, transport, markup and vault wrapper regressions. Full Mix, Node, Cargo and Linux/Windows vault validation pending; requires updated server and native build.

## 2026-11-26 — Correct SOL wormhole bearing

- User corrected the mouth direction to east-southeast to align with the schematic Galactic Atlas. SOL mouth now (+84,000,000, +35,000,000, 0) game-km; radius and Pluto clearance unchanged. Updated placement and selection regressions. Paired mouth, transit lock and flight lab unchanged. Full runtime verification pending.

## 2026-11-26 — SOL frontier wormhole location

- Moved the SOL-side Alpha Centauri mouth to (-84,000,000, +35,000,000, 0) compressed game-km, radius 91 million, approximately 8.2 million beyond Pluto's orbital ring at west-southwest on the overhead Atlas (positive Y is down). The paired Alpha Centauri mouth is unchanged. Navigation publishes charted mouths with transit_available false. Both overhead and 3D Atlas display a distinct locked wormhole marker, selectable as its exact server-owned approach waypoint using existing SOL navigation; no jump or live portal interaction granted. Hidden in inner focus. Added placement and selection regressions. Full runtime validation pending; tunnel remains development-only.

## 2026-11-26 — Sharper wormhole turns

- Increased horizontal/vertical bend amplitude to 980/620 units and frequencies to 4π/7π, with five narrower choke points (minimum radius 230; entrance/exit remain 460). Existing 193-section geometry, steering authority, throttle, turbulence, exposure and ejection rules are unchanged. Renderer consumes the revised server geometry automatically. Strengthened geometry and unsteered-ejection regression; existing centerline steering regression retained. Independent numerical mirror: full-throttle unsteered ejection at 6.5 seconds; steered arrival at 40 seconds with 220/300 hull, minimum clearance about 68 units. Actual ExUnit and manual flight validation pending. Development lab only.

## 2026-11-26 — Wormhole visual and piloting refinement

- Replaced static wall colors with animated procedural plasma, flowing particle filaments, stronger cyan/gold 3D guidance rings, and a luminous exit ring instead of an opaque disc. Successful arrival reveals a procedural Alpha Centauri binary-star sky preview via a short fading transition; ejection/abort shows a SOL exterior preview. Neither changes actual pilot location. Increased centerline bends (740/480 units) and narrowed minimum radius from 350 to 270 units; geometry sampling doubled to 193 sections. Server still owns all geometry, collision, exposure and ejection; damage/cooldown constants unchanged. Added clearance telemetry and regressions for unsteered failure, steered success, mesh UV seam and arrival scene gating. Isolated lab only. Native/SBS and persistent transfer remain deferred; visual/GPU and full Mix/Node verification pending.

## 2026-11-26 — Wormhole boundary breach and ejection

- Removed the simulated tunnel wall clamp. Three continuous seconds outside the geometric radius triggers SOL entrance ejection, with ordinary accelerating hull exposure and 12 HP/s wall damage continuing through the recovery window. Steering back inside resets the countdown, never refunds damage. Zero hull wins over ejection or arrival. Voluntary abort also returns to the origin. Returned simulated ships stop taking exposure damage and have a server-owned ten-second re-entry cooldown; retry preserves current/max hull and shields while resetting the new transit timer. Lab shows boundary warnings, red viewport edge, countdown and re-entry controls, with a return-facing camera pose. Added core tests for breach/recovery/ejection/cooldown/retry/destruction/exit rejection. Still an isolated development lab: browser refresh explicitly resets the simulated ship; persisted disconnect recovery, live ship damage settlement and actual system transfer remain unimplemented. Full Mix/Node and visual validation pending.

## 2026-11-26 — SOL / Alpha Centauri wormhole flight lab

- Added an isolated development-only `/dev/wormhole` LiveView and a server-owned deterministic transit model. Existing FlightControls emits signed input; Three.js renders curved, narrowing sections, luminous filaments, guide rings and the exit from server-provided geometry. Lab steering is lateral pitch/yaw, not yet full ship attitude physics. Exposure bypasses shields: cumulative hull loss floor(t + 0.025*t²), t in seconds, plus 12 HP/s of wall contact. 9,600-unit tunnel at 240 units/s takes about 40 seconds at full thrust; zero hull destroys the simulated ship, abort retains simulated damage. Tests cover exposure, stationary destruction, forged input, wall contact, steering and abort. No pilot persistence, live warp authorization, destination map transfer, native cockpit or SBS integration; production routing remains disabled. Full Mix/Node and visual lab validation pending.

## 2026-11-26 — v0.3.8 release compiler gate

- Corrected consecutive `@doc` attributes in `Sunracer.World` by moving the existing story-event documentation to `story_event/2`. No executable code changed. Release, communications and EC2 package jobs failed at `mix compile --warnings-as-errors` on 8f77b40; fresh CI validation pending. Keep the strict compiler gate and retry the existing v0.3.8 version, not a new patch bump.

## 2026-11-26 — Release regression alignment

- Updated the Atlas HUD markup regression to require only hull and shield in the movable floating ship-status panel, forbid the retired `hud-speed` element and client selector, and confirm the physical dashboard renders actual velocity. No runtime code or UI changes. Existing dashboard model tests cover velocity calculation. Full local release test rerun pending.

## 2026-11-26 — Sequential galactic campaign road

- All 29 systems now have a server-owned campaign phase; the first six retain the agreed SOL → Alpha Centauri → Barnard's Star → Sirius → Epsilon Eridani → Tau Ceti order. Later phases are provisional and arranged to reduce crossings on the existing schematic map. The SVG draws 28 directed, dashed planned connections behind interactive markers, labels phases, and shows previous/next systems. First leg gold means next campaign, not available travel. Replaced the provisional Alpha Centauri–Tau Ceti mouth pair with Alpha Centauri–Barnard's Star to match the chain; remaining physical mouths and unlock/transit logic are not implemented. Artwork and all marker positions unchanged. Added catalogue and renderer tests. Full Mix/precommit and native visual verification pending.

## 2026-11-26 — Galactic Atlas artwork

- Replaced schematic spiral strokes with a local, photographic-style galaxy art layer inside the interactive SVG. Guide rings, system marker coordinates, labels, selection and zoom remain independent of the image. The approved mockup's clean artwork derivative is supplied separately as `spacenova-galaxy-assets.zip`; extract at repository root and commit `apps/sunracer_web/priv/static/images/game/galaxy/milky-way.webp` before publishing a release. Existing native staging recursively copies game images. A missing asset displays a visible warning without disabling marker interaction. No live travel or catalogue changes. Focused renderer test added; native visual acceptance pending.

## 2026-11-26 — Galactic Atlas

- Added a three-scale Atlas (Galaxy, Star System, Local Space), procedural vector Milky Way art, 29 real named systems including SOL, selectable schematic markers, zoom/reset and read-only system inspection. Server sends catalogue once per world join, not on physics ticks. SOL's Orion Spur location is about 26,000 ly from the centre; neighbouring stars are spread for readability and their plotted positions are NOT astrometric. Alpha Centauri includes Proxima. Replaced unwired fictional expansion systems and links with Alpha Centauri and Tau Ceti; no expansion planets or live wormhole travel. Existing local waypoint and SOL travel commands unchanged. Sources: NASA https://science.nasa.gov/solar-system/solar-system-facts/ ; https://www.galaxies3d.org/stars-nearest-data.htm ; https://www.physics.unlv.edu/~jeffery/astro/star/star_table_nearest.html ; https://liveearthviewer.com/stars?focus=proxima-centauri . Test coverage added; full compile, precommit and native visual verification pending. First Run end-to-end user playtest reported complete.

## 2026-11-26 — Green Starbase safe arrival

- Reused cruise-to-station maps now reset the living undocked ship to a server-owned approach 2,000 local units from the hub, aligned with the open bay. An already embedded pose is recovered without additional damage; valid swept wall impacts retain damage and stopping behavior. Reject unsafe saved station poses while retaining valid docking checkpoints. Added pure, map transition and persistence regressions. No hull repair, quest reset, docking bypass or client change. Full compilation and live verification pending.

## 2026-11-26 — First Run orphaned rescue recovery

- Reconcile stage 6 at authenticated join and verified respawn only, using a fresh server navigation snapshot and checking for pending tactical cleanup. Missing tactical and pending encounters return to stage 5, preserve earlier flags and cargo, and rearm on a new voyage. Ordinary navigation broadcasts cannot reset a fight mid-settlement. No DB reset or new client command. Added pure and channel regression coverage; compilation and live retry pending. A lost surrender with no durable story result must be replayed, not granted automatically.

## 2026-11-26 — Cockpit pointer ownership

- Unified dashboard and mouse-capture pointer routing: unlocked physical dashboard clicks (including blank instrument surface) consume the event before steering capture, target selection or weapon handling. Escape or middle-click releases captured steering; clicking outside the dashboard resumes it. Pending native fallback requests are invalidated on release to prevent delayed recapture. Saved steering preference, throttle, keyboard flight and server authority unchanged. Added source-level routing regression coverage; packaged WebKit/desktop visual acceptance and full test suite pending.

## 2026-11-26 — Interstellar catalogue foundation

- Added `Core.Universe.StarSystems` and `Core.Universe.Wormholes`: unchanged SOL catalogue, two provisional expansion systems, reciprocal system-local wormhole mouths. Added focused tests and `docs/interstellar-navigation.md`. This is an unwired foundation; existing SOL campaign, NPC balance, saved voyages and live navigation unchanged. Compilation/tests pending.

## 2026-11-26 — Cockpit computer and tactical decisions

- Removed duplicate speed from the floating hull/shield window. Physical dashboard now shows velocity, throttle, context-sensitive target/range or objective and tactical/comms/Atlas/cargo controls. Desktop pointer clicks raycast the physical panel before mouse capture; existing authenticated tactical buttons/commands remain the fallback and share the same request state. Fixed Dart surrender eligibility (formerly Scow-only). Existing headset gaze surrender and flight status remain available; new dashboard tabs are desktop-interactive only in this pass. Own surrender, combat rebalance and full VR tab interaction are separate work. Regression tests added; installed-client and full Mix verification pending.

## 2026-11-26 — Encounter continuation wording

- After a successful hail, both encounter panels show "Resume course" instead of "Ignore / Resume course". Hail status is local to the displayed encounter and resets when it changes or closes; failed hails do not mark a new encounter as hailed. No navigation commands, encounter permissions, story logic or server payloads changed. Added focused label regression coverage and updated the First Run manual checklist. Automated execution and installed-client verification pending.

## 2026-11-26 — Shared SpaceNova account theme

- Login, registration, success, verification, resend and both password recovery views now use one `Layouts.auth` component, the existing SpaceNova title artwork, wordmark and palette. Preserve existing form IDs, routes, authentication, registration gates and token handling; browser title/description now match public branding. Internal Sunracer namespaces, deployment, ship name and mail transport are unchanged. Added controller markup regression coverage; source reviewed, compilation, Mix precommit, controller tests and desktop/mobile visual checks pending.

## 2026-11-26 — Sparse deep-space debris for motion reference

- Increase only the client-side open-space field to a capped 0.22 fragments per 240-unit cell at the existing server intensity 0.025 (20% of peak Earth orbital debris density); shrink fragments to 1.5–7 scene units and reuse the orbital debris material. Keep deterministic map/cell coordinates and existing camera clearance. No speed lines, network payload changes, collision, mining, server physics, or changes to dense regions. Desktop and SBS share the existing instanced renderer; docked and cabin scenes remain separate. Eight focused Node generator tests passed in an isolated copy, including three new regression cases. Full JS suite, Mix precommit, installed-client build and manual desktop/SBS flight verification pending; density is a tuning starting point.

## 2026-11-25 — Shared Green Starbase pilot avatars

- Green Starbase remains one logical interior across private SOL flight maps. A docked authenticated world channel may query compact server-verified poses from active private-map sessions only; requests throttled to 350 ms, client poll 500 ms while docked. Reject undocked callers and ignore supplied IDs/positions. Names cached per channel while present. Render separate lightweight spacesuit avatars with nameplates, smoothed yaw/position, procedural walking, door opening for nearby remote pilots and disposal on departure. Desktop relay projection includes station pilot data for paired headset; direct helmet transport does not yet receive the shared roster. Initial implementation enumerates active sessions per docked viewer, no shared presence cache yet; no avatar collisions, customization or shared quests. Focused JS checks executed, added regression tests, full CI/precommit and manual two-pilot validation pending. No database migration.

## 2026-11-25 — Live player contacts on the SOL Atlas

- Separate authenticated `atlas_pilots` query (2-second client poll only on system Atlas; 1.5-second server throttle) reads existing SOL anchors for live same-party/guild pilots across sectors and neutral pilots within the current map's 5,000-unit proximity policy. No client-supplied IDs, full navigation state, or fake local-to-SOL coordinate transform. Party green, guild violet, neutral white; both flat and Orrery show named markers and sensor drawer lists pilots; coincident anchors use diagram-only separation. Private deep-space maps remain private tactical simulations; strategic positions do not imply physical co-location. Correct remote manual player exterior +X-to--Z local basis without changing authoritative physics or Orrery geometry. Added projection, policy and client tests; focused JS marker and rotation checks executed, full CI/precommit and manual multiplayer verification pending. Station avatars and cockpit labels remain future work.

## 2026-11-25 — Persistent guilds (initial milestone)

- PostgreSQL guilds, memberships, invitations; one guild per pilot, unique case-insensitive name, 50 seats including reservations, seven-day invitations, leader/officer/member ranks. Found, invite offline verified pilots, accept/decline, promote/demote, remove, transfer leadership and leave; last leader can disband, otherwise transfer first. Serialize mutations via transaction advisory lock and unique constraints. Private guild chat routes to exact current membership identities, recipient rechecks membership and ignore list. New Guild tab/roster/context invite, /guild text, private history clearing. No fees, treasuries, territory, shared rewards, or guild-owned bases. Guild leader account deletion cascades guild deletion. Live-only chat; persistent membership/invitations, not message history. New migration and tests; focused JS checks executed, full CI and precommit pending, no manual verification or deployment.

## 2026-11-25 — Communications reconnect regression and dedicated CI

- Local targeted run reported 10/11 passing; the global reconnect limiter test exited on its linked channel's intentional `{:shutdown, :left}` before reaching the fifth-message rejection. Unlink that channel before leave, monitor it, and assert its expected exit before reconnecting. Keep the rate-limit assertion intact. Add a dedicated communications workflow using the existing PostgreSQL/OTP/Elixir CI versions and targeted JS checks. No runtime behavior changed. Corrected test and CI execution pending; mix precommit not run.

## 2026-11-25 — Party channel compilation correction

- CI runs 45739169514, 45739169495 and 45739169423 all failed compilation because the local `reply/2` helper conflicted with the imported `Phoenix.Channel.reply/2`. Rename only the private helper and its call sites to `action_reply/2`, preserving response tuples and authorization. No test relaxation or deployment. Full compile and regression verification pending on the corrective commit.

## 2026-11-25 — Online pilots and temporary parties (milestone 2)

- Phoenix Presence lists authenticated communications clients; multiple connections per pilot collapse to one directory entry. Supervised single-node PartyManager serializes six-seat membership, online invitations (60-second expiry), accept/decline, leave, leader removal/transfer and private message routing to registered member processes only. Five-minute reconnect grace; leader succession on leave/expiry. Party state is ephemeral across server/manager restarts. Party chat shares validation/rate limits and server-side recipient ignore filtering. Invite and accept check mutual blocks. UI includes directory, roster, invitation, leadership, /invite and /p; tells remain independent. No guild, party navigation markers, persistence or cluster support yet. Added manager/channel/JS/native tests; focused JS invite/state checks executed successfully, full CI and mix precommit pending, no live verification or deployment.

## 2026-11-25 — Longer player laser reach (playtest)

- Double server-authoritative player beam range from 540 to 1,080 world units (64.8 scene units). Both manual twin-wing beams and locked fire already use the authoritative weapon range. Client instant-preview fallback follows the new range; actual range still comes from the snapshot. NPC range, damage, cooldown, aim geometry and detection radius remain unchanged. The standoff window intentionally widens to 660 units against Dart and 700 against Scow; this makes the prologue encounter easier and may allow fire beyond NPC detection, so live balance needs review. Update mission prompts and range, manual fire and preview regressions. Full CI, mix precommit, installed-client and EC2 acceptance pending. No deployment or version bump.

## 2026-11-25 — Orrery left-button panning

- Left drag pans along the orbital plane at the current zoom and elevation; five CSS pixels distinguish clicks from drags. Keep left-click selection, middle-button orbit, wheel cursor zoom, context menu and double-click focus. Pointer capture and cancellation prevent accidental waypoint selection; update cursor and control hint. Two new focused JS tests executed against the actual helper and binding logic (passed); full CI, mix precommit and installed-client visual acceptance pending. No server physics, network, version or deployment change.

## 2026-11-25 — Preserve VR rendering regression contract before deployment

- Move communications availability update before the existing VR-only synchronization and interpolation pair. CI run 45731346723 had three passing tests and one failed source adjacency assertion. The corrected source satisfies that assertion without changing the regression test, simulation, or renderer. Full CI and mix precommit remain pending; no deployment performed.

## 2026-11-25 — Unified communications and direct tells (milestone 1)

- Global and direct chat share one compact four-tab interface, independent unread counts, bounded per-tab histories and pilot-name actions. Direct tells route via server-owned per-pilot PubSub inboxes; identity is socket-authenticated, exact verified pilot names resolve recipients, and no private message is broadcast to the shared channel topic. Global and direct actions share the existing per-pilot rate limit. Ignore preferences persist in account data; direct delivery checks both sides and global display filters ignored pilot IDs. Commands: /g, /p, /guild, /tell (quoted names supported), /r, /ignore, /unignore. Party/guild tabs explicitly unavailable until membership implementations; no pretend group broadcasts.
- Live-only tells, no offline queue or delivery/read receipt. Global filtering is client-side; no moderation/reporting, friends, or online directory yet. Chat remains outside SBS. Added server privacy/ignore and JS command/history/native markup tests. Full compilation, mix precommit, and multi-pilot installed acceptance pending. No migration, deployment or version bump.

## 2026-11-25 — Global pilot communications v1

- Added an authenticated, region-independent Phoenix chat:global channel on the existing socket. Sender names come from verified socket assigns; only pilot credentials may join. Single-line 280-character/1120-byte cap, control-character rejection, four messages per rolling ten seconds per pilot on the server node, no DB migration. Text is rendered literally. No server history or offline delivery; each client retains at most 100 received messages in memory.
- Shared desktop/browser collapsible midnight-blue chat, unread count and connection status. Keyboard capture and release of held movement/manual weapon inputs on focus prevent chat typing from becoming flight commands; hidden during blocking interactions and SBS rendering. No phone chat, private messaging, moderation/reporting, or cluster-wide rate limit in v1. Requires updated server as well as client; no EC2 deployment or release bump.
- Added channel, JS and native markup regression tests. Full compilation, mix precommit and two-pilot installed-client acceptance pending.

## 2026-11-25 — Orrery miniature spacecraft and destination beacon

- Reused the current player exterior mesh via shared sunracer_model.mjs; Scow and Dart strategic contacts use their existing geometry selected from authoritative ship_class. Neutral ships are silver, own ship cyan, hostiles red. Free waypoint is a yellow peg with a matching ring/label. Models remain schematic; course-aligned bearings are visual only. Cached miniature groups are resized to bounded screen size and disposed on departure; ray picking traverses their child meshes. Unknown contacts retain a generic marker. No transport, server, physics, or SBS changes.
- Added marker class, bearing and sizing tests. Full build and installed visual acceptance pending.

## 2026-11-25 — Minimal cockpit ship readout

- Replaced the bulky pilot/status card with a 15rem translucent hull/shield bar and actual velocity magnitude readout. Removed redundant pilot, configuration, coordinates, equipment and per-card editing controls. Existing HUD unlock/drag, visibility menu, and minimap remain; legacy saved collapsed state is normalized for the readout. No change to physics, combat, networking or SBS.
- Added shared and native markup regression tests; static ID/reference checks passed. Full Node/ExUnit suites, mix precommit, installer and visual verification pending.

## 2026-11-25 — Fix installer regression gate after docking popup removal

- CI on 51a9b22 reported 56 passing native tests and one failure in native-overlay-visibility.test.mjs: its legacy overlay list still required the intentionally removed docking popup. Replace that expectation with an absence assertion and retain the countdown and all remaining CSP-safe overlay checks. Linux and Windows installers had been skipped after the failed test; no new package was produced by those runs. Full CI and installed visual acceptance of this correction pending.

## 2026-11-25 — Remove redundant Green Starbase docking popup

- Removed the approach instruction panel, immediate-docking button and their client-only handlers from the shared cockpit. The server's automatic five-second stationary docking hold, countdown, collision warnings, docked interior and launch controls remain intact. The existing server manual-docking endpoint is unchanged; it is no longer exposed through this popup.
- Added shared and native markup regression tests. Static ID/reference checks passed; Node suite, mix precommit, installer rebuild and manual docking verification pending. No server changes, version bump or deployment.

## 2026-11-25 — Cursor-anchored Orrery zoom

- Mouse wheel now dollies toward the cursor's scene ray: visible object surfaces, offset labels at object depth, or the orbital plane for empty space. A camera-facing plane bounds near-horizon picks. The orbit target translates with the camera to keep the anchor projected at the same screen position. Existing camera limits, keyboard zoom, reset, gameplay coordinates and server authority are unchanged.
- Added regression tests for projection invariance, distance bounds and reversible zoom. 28 isolated mathematical cases passed in the authoring runtime; repository Node suite, mix precommit and installed-client visual verification not run. No version bump or deployment.

## 2026-11-25 — Installed headset relay: no command-line configuration

- Opening the HMD panel selects the already discovered private HTTPS headset IPv4 and binds port 4455 on that exact interface. The optional developer bind override must match. No wildcard/public/loopback bind, no listener at app startup, no TLS downgrade. Existing trusted local Phoenix certificate/key are discovered in the standard app config directory or the existing ~/SunRacer checkout. A native Certificate setup button selects and validates a certificate/key pair once and saves only local file paths; retry requires no relaunch or environment variables. Existing Phoenix pairing is preserved on relay failure.
- The trusted HTTPS phone page on the same LAN IP:4443 and phone CA trust remain prerequisites for the optimized local stream. Public EC2 phone origins retain direct Phoenix connectivity; fully automatic trusted certificate provisioning and local asset serving for arbitrary installations remain separate work. No secrets bundled or transferred. Added Rust address validation and native markup/IPC checks; full builds and Galaxy acceptance pending.

## 2026-11-25 — Fix SVG layer obscuring the installed 3D Atlas

- The overhead map is an SVGElement, not an HTMLElement. Setting its `.hidden` property did not set the DOM `hidden` attribute required by the CSS, leaving the opaque overhead layer above the 3D scene. Toggle the actual attribute on mode changes and regression-test SVG attribute semantics. Preserve the previous native first-frame guard and overhead fallback. Installed-client visual verification pending.

## 2026-11-25 — Installed-client orrery visibility recovery

- Keep the functional overhead map visible until an initial 3D frame is confirmed. On native clients, retain the WebGL drawing buffer and present via a regular 2D canvas, validating the first frame's solar-center pixel; use explicit stacking and the same high-performance GPU preference as the cockpit. Guard against zero draw calls, context loss and rendering exceptions. Show the failure reason and restore the overhead chart rather than leaving an interactive blank viewport. Disable invisible picks before first frame. Added mode transition tests.
- This is a defensive fix for a reported blank installed-client viewport, not a verified diagnosis of WebKitGTK. Installed GPU verification and complete tests pending. No simulation, transport, package identity or release version changes.

## 2026-11-25 — SpaceNova 3D Solar Orrery

- Added a locally rendered Three.js orrery with a tilted camera, shaded schematic planets, Saturn rings, thin cyan-blue orbit paths, midnight/nebula backdrop, labels, player and server-positioned station/contact markers and schematic route indicators. Left click selects, right click opens existing route actions, middle drag rotates, wheel zooms and double-click focuses; reset and keyboard camera controls are available. The overhead chart remains available and is the fallback if WebGL initialization fails.
- Reuses the existing reversible SOL chart projection and authenticated navigation callbacks. No protocol, physics, ephemeris, or SBS changes. Sensor contacts without a supplied position remain in the existing contacts panel; no invented locations. Routes are diagram indicators, not predicted obstacle-avoidance trajectories. Planet markings and distances remain schematic.
- Added shared landing-page color tokens, actual SVG icons for the native toolbar, context-sensitive flight actions and suppressed the redundant closed NET tab in Atlas. Preserved existing flight handlers and settings.
- Added projection/camera and native markup regression tests. Source integration checks passed; automated suite, asset build and GPU/browser/manual verification pending. No version bump, deployment or Mix formatting.

## 2026-11-25 — SpaceNova Atlas command layout

- Organized the shared Atlas into a compact SpaceNova header, live connection state, left pilot command toolbar and top-left settings disclosure. Existing inventory, loadout, sensor contacts, mouse preferences, headset, HUD reset, diagnostics and logout controls retain their original handlers. Pilot and mission readouts use existing authoritative player/story data.
- Restyled the right instrument stack with translucent midnight-blue surfaces; existing target selection, transit and draggable instruments remain intact. Native markup conversion recognizes the new icons. No changes to simulation, gameplay transport, SBS overlays or cockpit flight controls.
- This is the Atlas organization milestone, not a full cockpit redesign. Native equipment editing remains at its existing limitation; mission toolbar is read-only while existing story decisions remain in the cockpit. Graphics/audio settings and expanded context panels are not yet implemented.
- Added shared markup and native packaging regression checks; static control-ID checks passed. Node/ExUnit suites and visual verification pending. No release or deployment.

## 2026-11-25 — SpaceNova native pilot authentication

- Native Play/sign-in now uses the same staged artwork, logo, title stylesheet and angular action button as the launcher, with a translucent right-side login card and responsive sizing.
- Preserved the native auth form IDs, password handling, server selection, recovery, launcher return, token lifecycle and initial gameplay visibility. Changed only the visible native window title to SpaceNova; package/update identity remains SunRacer.
- Added native markup and styling regression checks. Static source/ID checks passed; Node suite, Tauri rebuild and manual login verification pending. No new release version or deployment.

## 2026-11-25 — Unify the installed SpaceNova launcher with the web title screen

- Replaced the bundled desktop launcher's old two-column console with the approved SpaceNova artwork, wordmark and Play/Create account controls. Both launch surfaces use the same title CSS and static artwork. Native staging now explicitly bundles the shared CSS and background, including the SVG fallback, without runtime downloads.
- Moved server selection, diagnostics, update and preview tools into the top-left settings menu. Existing native proxy form, Rust commands, local IPC boundary, package identity and standalone game launch are preserved.
- Updated launcher markup, branding and offline staging regression tests. Static control-ID checks passed; Node suite, Tauri build and manual desktop verification pending. No new release version or EC2 deployment.

## 2026-11-25 — Restore native proxy settings in title menu

- Moved the installed client's existing system/SOCKS5 proxy selector, host, port, tunnel override notice and save/restart flow into a top-left translucent, intrinsic-width hamburger menu. Existing Rust validation, persisted settings and local-only IPC capability are unchanged.
- Browser title screen explains where native proxy configuration lives; no remote IPC or browser proxy bypass introduced.
- Added markup and capability regression coverage; local Node suite, Tauri build and real proxy/restart verification pending. No Mix formatting or deployment performed.

## 2026-11-25 — SpaceNova title settings menu

- Removed duplicate Pilot Sign In; Play still routes guests to login and authenticated pilots to the cockpit.
- Added a reusable top-left settings popover, intrinsic-width translucent midnight-blue panel, and a browser network section with current origin and on-demand same-origin HTTP connection check. Native proxy controls remain in the Tauri launcher; browsers manage their own proxy settings.
- Added homepage DOM and Node network-check regression coverage. Full local test/build and visual verification pending; no Mix formatting or deployment performed.

## 2026-11-25 — SpaceNova public title screen

- Replaced the public homepage with a responsive cinematic title screen and styled SpaceNova wordmark. Guest actions use existing login, registration and recovery routes; authenticated actions use play, equipment and logout.
- Install the approved `spacenova-space.webp` at `apps/sunracer_web/priv/static/images/landing/` before deploying. The original `sol-approach.svg` remains a CSS fallback while the binary artwork is pending. No runtime names, native clients or game protocol changed.
- Updated guest homepage DOM regression test. ExUnit, asset build and live visual verification are pending; no Mix formatting performed.

## SBS headset bandwidth overlay removal (2026-11-24)

The per-eye RX/TX cards have been removed. The headset regression check now covers their absence. All 25 focused headset and bandwidth tests passed. Galaxy S21 visual verification is pending.

## Trade Exchange (2026-11-23)

- [x] Sell looted cargo and buy common goods at Tarek Sol's Trade Exchange,
      fixed tight prices, buy above sell (no same-desk arbitrage).
- [ ] Run `mix test` on a machine with Hex access (not run in the session
      that built it).
- [ ] Manual verification in game: dock, walk to Tarek, sell seized cargo,
      buy goods, hold/credit limits. Not yet performed.
- [ ] A second market (another station or a hauling mission) with its own
      prices, so bought cargo can be traded for profit.

## Mouse steering and SBS headset (2026-11-22)

- [x] Full-screen virtual-joystick mouse steering with a faint steering line
      on the laptop, replacing idle-timer rate steering.
- [x] Steering line relayed to the SBS headset through the LAN visual pose
      and the Rust allowlist; drawn ship-fixed with a tip dot.
- [x] Headset own-ship view predicted from relayed body rates between LAN
      poses, removing scenery judder while turning (simulation-tested).
- [x] One-Euro filter on handset head tracking (constant shimmer when still).
- [ ] Manual verification on the S21: headset line visible, view steady when
      still and smooth while turning. Not yet performed; read the FPS / SLOW /
      HEAD HZ diagnostic line. If FPS is low or SLOW high, lower the headset
      pixel ratio before considering a native Android viewer.
- [ ] Remove the temporary `STICK LINE` headset diagnostic once verified.
- [ ] Optional: drift-back-to-centre setting for the virtual joystick.

## Headset usability (2026-11-21)

- [x] Gaze-reachable death recovery. The headset had no death handling at all;
      a pilot who died in an HMD was stranded, because the respawn panel and
      button existed only in the laptop client.
- [x] Gaze-reachable surrender choice: release, seize the hold, or keep
      firing. Without it an HMD pilot could not complete prologue step 6, which
      instructs them to accept the surrender and seize the hold.
- [ ] Throttle is mouse-wheel only (`FlightControls.wheel/1` is the sole writer
      of `this.throttle`), so a headset pilot cannot move without finding the
      scroll wheel blind. This is the real headset blocker, not Ctrl+E. Options
      weighed: keyboard throttle keys plus a single-key mode toggle (cheap,
      everything touch-findable), or gamepad support through the existing
      `flight_controls` payload (best ergonomics, new input path, no channel
      change). Decide before more headset content lands.
- [x] Reachable flight-mode switching in the headset: a gaze icon relaying a
      named intent to the laptop, which applies it through the same
      FlightControls the keyboard drives. Resolves the contradiction introduced
      by prologue step 6, which tells HMD pilots to press Ctrl+E.
- [ ] Audit the rest of the prologue for keyboard-only instructions.

## Flight model and combat balance (2026-11-21)

Design settled and recorded in `docs/flight-combat-balance.md` with the
derivations. Balance is a hard requirement for this game; the figures there
were measured against the code, not estimated. No code has changed yet.

- [x] Measure the combat baseline and establish where the current numbers break
      (shield gains cap at 4.8x, the LF laser line runs to 20x, reverse equals
      forward in both flight modes, Newtonian is dominant on every axis).
- [x] Envelope parity: Newtonian ceiling dropped from `speed * 1.5` to
      `speed * 1.0`, and acceleration now comes from the hull's `acceleration_g`
      scaled by one constant, giving 64 u/s^2 for the Sunracer instead of 480.
      The velocity vector swings at 11.4 deg/s against a 44 deg/s nose, so
      momentum lags behind pointing and the two modes finally differ.
- [x] Fixed the mode-switch handbrake: entering cruise kept the along-nose
      component and deleted the rest instantly and for free. The lateral part
      is now carried as `Entity.drift_velocity` and bled off at the drive's
      thrust — 320 units/s now takes 5.1 seconds to shed instead of one tick.
- [x] Added `reverse_factor` to `Core.Ships.Ship` as per-hull game data, 0.33
      on the Sunracer, applied in cruise only. Full reverse is now -105.6
      rather than -320. Newtonian is deliberately untouched: velocity and
      facing are independent there, so reverse is not a quantity to cap.
- [ ] Raise the Dart above the Sunracer's 320 movement speed, per the project's
      own Space Rogue source data (Dart 0.30 g against the Sunracer's 0.20 g),
      then re-tune prologue step 6 around a firing pass rather than a static
      band hold.
- [ ] Add a CI balance band property test: every purchasable fit on a hull must
      need 5 to 20 s to kill its tier-appropriate opposition, and must still be
      killable within 60 s. Hang it on `mix precommit`.
- [ ] Gate the legacy LF and SG equipment lines on hull class rather than
      rescaling or retiring them.
- [ ] Wire up `cargo_pods`, which is currently display-only: the equipment page
      promises a hold expanding from 4 to 8 and nothing can act on it.
- [ ] Decide the braking rate. The implementation slows down at the same thrust
      it accelerates with, so a full stop from top speed went from 0.83 s to
      5.0 s. Braking at the retro rate would be three times slower again.
      Affects station approaches most; needs a cockpit to judge.
- [ ] Equipment unlocks (two gates: a story-granted authorization token, then a
      credit purchase) and the Ilya Quill outfitter transaction.
- [ ] Open numbers before building: time to top speed, the Dart's speed, and the
      long-run credits per delivery run that the price curve scales from.

## SunRacer rename validation (2026-11-21)

- [x] Remove remaining Space Nova references from docs, CI workflow files,
      scripts, Tauri client and config; rename workflow/doc/script filenames.
- [x] Run existing JavaScript and Tauri tests (401 and 42 passing), plus the
      Python release/deploy script tests (7 passing).
- [ ] Run mix compile --warnings-as-errors, mix test, and mix assets.deploy
      (not run: no Elixir toolchain in the rename environment).
- [ ] Back up/migrate development databases; verify production DATABASE_URL.
- [ ] Point `sunracer.ddns.net` DNS at the EC2 host and issue its TLS
      certificate before the next production cutover; `spacenova.ddns.net`
      is no longer referenced anywhere in the tree.
- [ ] Rename `SPACE_NOVA_*` to `SUNRACER_*` in the EC2 systemd environment and
      in the local deploy shell environment; there is no fallback to the old
      names, so deploys and TLS startup fail until this is done.

## Green Starbase modular graphics pass (2026-11-08)

- [x] Retain existing server-authoritative station rooms, doorways, NPC kiosks and SBS pairing.
- [x] Introduce a shared local Three.js modular-art layer with tiled PBR metal floors,
      segmented wall skins, vents, conduits, recessed light strips, equipment racks,
      kiosks and Green Starbase signage.
- [x] Keep this visual layer separate from the walkable bounds, avoiding simulated
      client-side collision authority or adding asset-stream traffic to Phoenix.
- [ ] Validate rendering/frame pacing on Pop!_OS Tauri and Galaxy S21 SBS.
- [ ] Import and curate actual Quaternius CC0 modular meshes after asset selection,
      respecting the runtime size/draw-call budget and current collision topology.

# 🚀 Sunracer Umbrella – Roadmap

## 🎯 Vision
Reference implementation (someone else's project, not ours; archived June 2021):
https://github.com/yusufsahinhamza/darkorbit-cms
Rebuild a modern, scalable SunRacer server ecosystem using Elixir/OTP, replacing legacy PHP CMS-style architectures with:

- Strong domain modeling
- Real-time systems (Phoenix / Channels)
- Deterministic gameplay state
- Atomic economy + equipment systems
- Clean separation of concerns (umbrella apps)

Inspired by:
- Legacy CMS implementations (PHP-based control panels, game logic coupling)
- Private server ecosystems (equipment, PvP, progression loops)
- Goal: production-grade MMO backend

---

## 🧠 Current Architecture (What We Have)

### Core Domains Implemented

#### ✅ Accounts
- Registration
- Session generation
- Player metadata (credits, uridium, level, etc.)

#### ✅ Inventory System
- Persistent player_equipment
- Structured equipment bag:
  - lasers
  - generators
  - drones (future-ready)
- Helpers:
  - laser_count/2
  - add_lasers/3
  - remove_laser/3

#### ✅ Fleet (Ships)
- player_ships per user
- Ownership validation
- Active ship switching
- Starter ship provisioning

#### ✅ Loadouts (Critical System)
- 2 configs per ship
- Slot-based system:
  - ship slots
  - drone slots
- Fixed slot arrays (deterministic layout)

#### ✅ Equipment Engine (Major Milestone)
- Equip / unequip
- Slot validation:
  - bounds
  - capacity (ship-specific)
- Inventory integration:
  - consume on equip
  - return on overwrite
- Atomic transactions via Ecto.Multi

#### ✅ Preferences / Titles
- Player settings
- Titles ownership + selection

---

## ✅ Completed Milestones

### Repository-generated artifact hygiene

- [x] Remove the five accidental empty Phoenix asset-root files and the empty
  root npm lockfile without changing either real npm package lockfile.
- [x] Reproduce and checksum all 31 tracked Phoenix digest/compression outputs
  with `mix assets.deploy`, then remove only those generated copies while
  preserving every undigested original artwork/static input.
- [x] Ignore compiled Phoenix bundles, the digest manifest, gzip copies,
  32-hex fingerprint copies, and the identified command-token files.
- [x] Preserve `mix.lock`, both package-scoped npm lockfiles, the Tauri
  `Cargo.lock`, source assets, configuration, and user data.
- [x] Pass strict compilation, all 358 ExUnit tests, all 253 browser JavaScript
  tests, all 12 Tauri JavaScript tests, the Phoenix asset build, and a local
  unsigned Tauri Linux release build.
- [ ] Resolve pre-existing repository-wide Elixir 1.20 RC formatter drift so
  the complete `mix precommit` alias can pass without an unrelated bulk-format
  change.
- [ ] Decide separately whether Tauri release workflows should enforce
  lockfile-only installs with `npm ci` instead of `npm install`.

### Milestone A — Persistent player domains

- Account registration and authentication
- Inventory, fleet, two ship configurations, preferences, and titles
- Slot-based equipment mutations and starter-ship provisioning

### Milestone B — Persistent-state hardening

- Atomic account provisioning and equipment replacement
- Ownership-scoped mutations, row locks, uniqueness constraints, and database checks
- Concurrent inventory and loadout regression coverage

### Milestone C — Derived stats and authoritative world

- Configurable ship and equipment catalogs
- Pure configuration-aware ship-stat calculation
- Supervised sector `1-1`, sessions, bounded server-owned movement, deterministic ticks, and PubSub events

### Milestone D — Authenticated browser flight

- Credential login, signed game socket tokens, and an authenticated Phoenix world channel
- Canvas 2D sector renderer, original placeholder graphics, interpolated authoritative snapshots, and multiplayer movement events
- Playable development pilots seeded for browser testing

### Milestone D.1 — Continuous mouse navigation

- Single-click destination setting remains available
- Click-and-hold continuously steers toward the pointer at approximately 10 commands per second
- Pointer destinations are recalculated as the camera follows the ship
- Pointer capture, cancellation, focus loss, and hidden-tab cleanup are handled safely
- Near-ship and redundant retargets are suppressed to avoid jitter and unnecessary traffic
- The client still sends destination intent only; boundary validation, position, and speed remain server-owned

### Milestone E — Server-authoritative NPC combat

- Configurable NPC catalog with **one Dart pirate fighter** in the Sector `1-1` demo (replacing the initial three Rift Skirmishers); deterministic respawn keeps one live enemy at a time
- Map-owned NPC movement, hull, shields, targeting, bounded AI, destruction, and tick-based respawning
- Pure range, cooldown, shield-absorption, hull-damage, and destruction rules
- Authenticated target/select/fire channel intentions with authoritative multiplayer combat events
- Right-click and accessible nearest-target selection, target HUD, authoritative toggle firing, laser and hit effects, and explosions
- Catalog-defined Phoenix pulse emitter so existing development pilots can fight without inventory grants or duplication

### Milestone E.1 — Classic combat controls and action hotbar

- Left-click NPC selection uses rendered entity dimensions and consumes the pointer gesture before navigation; empty-space click-and-hold flight is preserved
- Selected and engaged targets are separate authoritative states, with explicit engage/disengage commands and idempotent repeated activation
- The map tick automatically fires the server-defined pulse emitter when range and cooldown rules permit, pauses while out of range, and clears combat across destruction, removal, disconnect, and respawn lifecycles
- Engaged player ships visually face their replicated target independently of movement, then smoothly return to navigation facing when combat ends
- Responsive bottom-center slots `1` through `0` use server-defined action data, with X1 ammunition in slot 1 backed by the ship's server-defined pulse emitter and safe empty placeholders in slots 2 through 0
- Ctrl, number-row keys, click activation, Esc cancellation, active/selected/empty/cooldown states, reserved Space behavior, and input-control/key-repeat guards are implemented

Manual browser verification confirmed navigation, NPC targeting, persistent laser engagement, combat facing, and circular combat maneuvering for Milestone E.1. Broader multiplayer browser validation remains deferred.

### Milestone E.2.1 — Modular cockpit HUD and persistent layouts

- Ship status, target information, and the minimap now use one reusable cockpit-window system with unique identifiers, dedicated drag handles, focus ordering, collapse controls, and a window visibility menu
- Unlock/lock editing, Pointer Events with capture cleanup, keyboard positioning, viewport clamping, reset-to-default behavior, and versioned per-player browser persistence are implemented without changing authoritative simulation behavior
- The previous main-canvas minimap was replaced by one dedicated, resize-aware minimap canvas driven by the existing interpolated world entities and authoritative map boundaries
- The ten-slot action hotbar remains anchored at bottom center, outside the movable window layer, with click, number-row, Ctrl, Esc, reserved Space, and cooldown behavior preserved
- Narrow viewports use a horizontally scrollable cockpit dock instead of free-floating windows, keeping panels recoverable after resize
- Automated coverage exercises drag lock state, collapse, visibility, reset, persistence, malformed storage, clamping, resize mode, pointer cleanup/input isolation, keyboard behavior, reduced motion, and minimap projection/lifecycle

The E.2.1 code and automated verification are complete. Manual browser verification of the new cockpit at the target viewport sizes has not yet been performed.

### Milestone E.2.2 — Interactive and scalable minimap

- Locked-HUD minimap clicks and click-and-hold gestures now submit projected destination intentions through the existing pointer-navigation lifecycle while movement positions, speed, validation, and combat remain server-owned
- Visible minus and plus header controls resize the floating minimap in 40-pixel steps from 192 through 520 pixels, with an additional available-viewport clamp
- Minimap width uses the existing version-1 per-player cockpit storage; older payloads retain their complete layout and receive the 272-pixel default, while reset restores and persists that default
- Narrow viewports keep the horizontally scrollable dock sizing, and the selected floating width is retained for the return to floating mode
- JavaScript regressions cover sizing, automatic persistence/reload, legacy layouts, reset, configured and viewport bounds, responsive docking, continuous minimap steering, combat isolation, and cancellation cleanup
- `mix precommit` passes 84 Elixir tests, `npm test` passes 46 JavaScript tests across 37 top-level cases, the 3-test authenticated page file passes, and `mix assets.build` passes

The E.2.2 implementation and automated verification are complete. Manual browser verification was not performed; the full sizing, reload, responsive-dock, minimap-steering, and combat-preservation flow remains required at the supported viewport sizes.

### Milestone E.2.3 — Server-authoritative laser toggle controls

- `Core.Combat.ActionCatalog` now exposes action ID, type, and activation mode; slot 1 is the toggle-mode X1 ammunition action while the Phoenix pulse emitter remains the separate server-owned weapon and cooldown source
- One serialized world toggle powers both Ctrl and slot-1 activation. Toggle-off preserves `target_id`, clears only `engaged_target_id`, and leaves `next_attack_tick` unchanged; Escape still clears selection and engagement
- `ControlLeft` and `ControlRight` are accepted once per physical key press, held repeats and Ctrl chords are ignored, and Space now reports the reserved rocket action as unavailable without firing
- NPC selection remains independent from firing, destroyed targets clear both states, and a newly selected live NPC can start a fresh engagement
- Hotbar active state and `AUTOFIRE`/`STANDBY` presentation consume authoritative engagement state and action metadata, while canvas pointer-down restores gameplay focus without taking keyboard behavior from cockpit controls or editable fields
- Automated regressions cover direct/slot/alternating toggles, stop/resume, clear and destruction lifecycles, sequential NPCs, cooldown preservation, invalid/empty/unauthorized/destroyed/missing-target safety, both Ctrl keys, held-key suppression, Space reservation, action metadata, and all existing cockpit/minimap/navigation behavior
- `mix precommit` passes 87 Elixir tests, `npm test` passes 48 JavaScript tests across 39 top-level cases, `mix assets.build` passes, and `git diff --check` passes

The E.2.3 implementation and automated verification are complete. Manual browser verification was not performed; Ctrl/X1 alternation, stop/resume with the retained target, Space messaging, focus restoration, and two-browser observation remain required.

---

## 🚧 Next Major Milestones

### 1. Inventory Expansion
- Drone equipment slots
- Ammo system
- Stackable vs unique items

### 2. Ship Stats Engine ✅
- Configurable ship and equipment catalogs
- Two configuration-aware loadouts
- Pure derived stats from equipped inventory

### 3. Combat System (initial PvE slice complete)
- Server-authoritative NPC targeting, damage, cooldowns, destruction, and respawning ✅
- Server-authoritative NPC attacks and player damage ✅
- PvP, ammunition, rewards, and player respawning remain future work

### 4. Map / World Layer (initial player-flight slice complete)
- Supervised starting map (1-1)
- Server-owned player positioning and bounded movement
- Configurable deterministic simulation ticks
- Continuous click-and-hold client navigation ✅
- NPC spawning, AI, combat, destruction, and respawning ✅
- Persistent tick-owned player combat engagement and independent combat facing ✅
- Modular local cockpit layout and standalone minimap rendering ✅
- Server-authoritative minimap steering and persistent bounded minimap sizing ✅
- Atomic server-authoritative Ctrl/X1 laser toggling with retained selection ✅

### 5. Real-Time Layer (movement and PvE slices complete)
- Authenticated Channels and sockets ✅
- Connected-player presence and disconnect cleanup ✅
- Movement synchronization ✅
- Targeting, laser, damage, destruction, and respawn events ✅
- Engagement, disengagement, atomic laser toggling, hotbar activation, and replicated combat-facing state ✅

### 6. Economy System
- Shop / purchases
- Credits vs Uridium balancing
- Loot drops
- Auction system

### 7. Progression Systems
- Experience → leveling
- Rank system
- Skill tree
- Drone leveling

### 8. CMS Replacement Layer
- Phoenix LiveView dashboard
- API-first backend
- Real-time updates

---

## 🧱 Architectural Direction

Principles:
- Persistent account state is authoritative in the database
- Live movement and combat state is authoritative in map processes
- Derived values are computed, never stored
- All mutations are transactional
- Systems are composable

---

## ⚠️ Known Gaps

- The E.2.1/E.2.2 cockpit and minimap still require manual browser verification at 1366×768, 1920×1080, 2560×1440, and mobile-sized viewports
- The E.2.3 Ctrl/X1 toggle, retained-target resume, Space messaging, and canvas-focus flow require manual browser verification
- Two-player synchronization and broader multiplayer browser validation remain deferred
- Destroyed player recovery, configurable or consumable ammunition beyond the X1 action identity, rockets, loot, rewards, and PvP are not implemented
- Live map state is ephemeral, single-node, and has no crash recovery or spatial partitioning
- Initial map, NPC, and combat balance values remain provisional
- No anti-cheat layer

---

## ✅ Immediate Next Task

Manually verify the complete E.2.1/E.2.2 cockpit acceptance flow and the E.2.3
combat-control contract at the supported viewport sizes, including minimap
sizing and reload persistence, responsive docking, click-and-hold steering,
Ctrl/X1 alternating toggles, retained-target resume, Space messaging, and
canvas focus restoration. Multiplayer expansion and broader two-browser
validation remain deferred.


## Experimental SBS / 3D presentation (branch `sbs`)
- [x] Introduce optional Three.js 3D cockpit and binocular side-by-side rendering.
- [x] Preserve the existing 2D game and authoritative movement/combat protocol.
- [x] Implement eye-aware pointer projection and a small unit test suite.
- [ ] Run complete build, precommit, and manual stereo browser verification.
- [ ] Introduce server-authoritative 3D motion and 6DOF flight as a separate milestone.
- [ ] Add optional WebXR and true headset-tracked cockpit controls.

- [x] Revise SBS viewport fit after first Firefox screenshot (instrument sizing
  and peripheral framing, plus pure per-eye fit regression tests).
- [ ] Visually recheck the revised cockpit layout in Firefox and headset.


## Navigation Computer V1 — experimental `sbs` branch

- [x] Full-screen SVG map independent of Classic 2D / 3D / SBS view selection.
- [x] Pointer and coordinate waypoint selection (up to eight legs), undo and clear.
- [x] Authenticated `plot_course` and `stop_navigation` commands.
- [x] Server-side atomic route validation, ordered waypoint progression and manual override.
- [x] Screen accessibility and keyboard controls (M, Escape, focus cycle).
- [x] Regression tests for validation, movement, spoofing and map projection.
- [ ] Run `npm test`, `mix assets.build` and `mix precommit` locally.
- [ ] Manually verify course interaction, browser layout, headsets and two-player sync.
- [ ] Introduce genuine 3D sectors, 6DOF flight and Newtonian/cruise modes.
- [ ] Add real hazard-aware navigation, station docking and a stereo in-world chart.


### Genuine space volume — XYZ first, flight dynamics second

- [x] Server-owned XYZ coordinates with bounded positive/negative altitude.
- [x] Deterministic 3D waypoint movement, proximity and NPC chase range.
- [x] Preserve legacy XY snapshot fields while adding explicit XYZ fields.
- [x] Switch the playable modes to single-view 3D and stereo SBS only.
- [x] Move point-and-click course planning exclusively to the SVG sector atlas.
- [x] Add altitude input, spatial route distance and 3D client interpolation.
- [ ] Run local Elixir, Node and browser regression suites for this migration.
- [ ] Next milestone: manual 6DOF yaw/pitch/roll and world-frame translation.
- [ ] After that: assisted Cruise Flight and Newtonian inertia modes.
- [ ] Later: 3D collision, docking, hazards and server-owned static objects.

- [x] Remove Classic 2D flight renderer and retain overhead mapping only in the atlas.
- [x] Regression-test the two allowed cockpit display modes.
- [ ] Verify refreshed compiled assets and live 3D/SBS switching in Firefox.


### Manual pilot controls slice — SBS branch
- [x] Server-owned signed throttle with forward, neutral, reverse.
- [x] Server-integrated 3-axis attitude and pitch/yaw/roll keyboard commands.
- [x] Assisted Cruise Flight and momentum-preserving Newtonian Flight toggle.
- [x] Bounds-safe tick motion; authenticated Channel controls and telemetry.
- [x] Cabin and SBS flight indicators; keyboard and server tests added.
- [ ] Run `mix precommit` and `npm test` on the laptop and test the flight feel.
- [ ] Improve to quaternion-based attitude and body-frame 6DOF handling.
- [ ] Add throttle controls on screen, smoothing, remapping, docking and inertia tuning.

### Solar System Atlas foundation (2026-11-02)

- [x] SOL system overview is the default main Atlas view; the Sun,
  Mercury through Neptune, and Pluto are all visible/selectable.
- [x] One astronomical catalog with mean AU distances and orbital
  periods; compressed visual orbits and optional inner-system detail.
- [x] Preserve Sector 1-1 as a distinct functional XYZ waypoint chart.
  Clicking an AU marker cannot submit an invalid tactical waypoint.
- [x] No change to currently working flight, weapon, Dart NPC or
  authoritative combat simulation.
- [ ] Server-authoritative star-system and celestial body catalog,
  faction ownership and planetary orbital/region models.
- [ ] Define coordinate transformations and ship's astronomical
  position separately from local per-sector XYZ coordinates.
- [ ] Introduce star-system travel, orbital approach and true
  navigable destinations after the above state model is established.
- [ ] Build EncounterDirector using system region, ship contacts,
  navigation progress and factions; do not tie encounters to a
  fixed NPC respawn coordinate.

### Peaceful login and SOL journey V1 (2026-11-02)

- [x] Remove default Sector 1-1 NPC materialization; no hostile Dart on login.
- [x] Retain Dart NPC definition and its authoritative 3D combat behavior
  behind explicit server-only `start_encounter/1`.
- [x] Production encounters do not automatically respawn after destruction.
- [x] Introduce independent, supervised SOL navigation state per pilot.
- [x] Authenticated planet destination selection, system travel progress,
  arrival, abort and server-owned transit broadcasts.
- [x] Atlas display of SOL region, voyage plan and schematic progress marker.
- [ ] Persist current SOL region across full game server restarts (database).
- [ ] Associate the player's physical ship with orbital region/planet sectors.
- [ ] Implement proper navigation transitions into and out of local flight.
- [ ] Dynamic encounters with NPC-v-NPC skirmishes, contact discovery,
  faction relationships, piracy and neutral traffic.
- [ ] Ephemeris/orbital positions, credible transfer paths, game-time scaling.

### Living universe / first neutral contact (2026-11-03)

- [x] Add an independent Earth–Mars commercial freighter with stable runtime
  identity, scheduled route, reason for travel, manifest and return cargo.
- [x] Advance civilian traffic on the system clock without requiring players.
- [x] Detect nearby vessels using server-side compressed-SOL distance and
  expose contacts to the correct authenticated pilot only.
- [x] Display sensor contacts in the Atlas and allow server-validated
  non-hostile hailing without changing cargo or itinerary.
- [x] Keep pilot navigation, sector combat and tactical NPC spawning separate.
- [ ] Make traffic, missions, cargo and voyage position survive server restarts.
- [ ] Instantiate contacts as shared local tactical encounters with relative
  entry positions, extraction boundaries and reconciliation on exit.
- [ ] Add physical outcomes: trade, rescue, piracy, faction response and
  persistent cargo-delivery consequences.

### Planetary cockpit visualization V1 (2026-11-03)

- [x] Server-authored planetary visual metadata, including true mean
  radii and an explicit visual-only approach/orbit preview stage.
- [x] Three.js camera-relative planet rendering with physically correct
  apparent angular diameter, cloud textures, lighting and atmosphere,
  without widening tactical camera clipping or sector bounds.
- [x] In both standard 3D and SBS, show the actual SOL destination
  growing through cruise and large on arrival (Venus 65° of 70° FOV).
- [x] Keep the planet at a stable world bearing when the ship turns;
  provide a visible cockpit label explaining the preview.
- [x] Add server geometry/navigation and client projection/render tests.
- [ ] Replace visual staging with server-owned, physically meaningful
  planet-centered orbital frames and safe 3D approach spawn positions.
- [ ] Make local ship thrust change its true planet-relative position
  and visible altitude; implement planetary collision/atmosphere rules.
- [ ] Preserve simultaneous multiplayer observers, tactical traffic,
  and clean entry/exit between SOL cruise and local orbital flight.

### Sub-light interplanetary cruise V2 (2026-11-02)

- [x] Explicit `:conventional` vs `:interplanetary_cruise` propulsion states.
- [x] Independent server-owned, compressed system-level ship position
  computed from drive speed and the same one-second multiplayer clock.
- [x] Travel budgets approximately 3–5 minutes inner system, 10 minutes
  Jupiter, 15–22 minutes outer system, without FTL or time compression.
- [x] Disable conventional flight/combat commands during interplanetary cruise.
- [x] Atlas shows current drive, system cruise speed, distance and ETA.
- [x] Cover concurrent players, ticks, position, duration, and command
  isolation in regression tests.
- [ ] Integrate local cockpit movement/velocities into an authoritative
  system-level ship position at sector boundaries.
- [ ] Generate safe semi-random planetary approach positions and real
  celestial bodies in their local sector centers.
- [ ] Preserve the actual midcourse position when abandoning cruise instead
  of restoring the departure region.
- [ ] Implement drive acceleration/deceleration and possible interception.


### Planetary orbital regions V2 (2026-11-03)

- [x] Nine independently supervised SOL planetary tactical regions,
  including Earth, plus an isolated legacy `1-1` combat test fixture;
  server-owned map identities and join validation.
- [x] Arrival side derived from the incoming SOL voyage, with deterministic
  pilot staggering and heading toward the actual planet centre.
- [x] Separate local provisional-kilometre coordinates from compressed
  system-wide cruise coordinates, preserving one shared map per planet.
- [x] Automatically transfer the pilot's Phoenix channel on arrival,
  update the local Atlas bounds and keep SOL navigation broadcasts global.
- [x] Real planetary mean radii, camera-relative planet rendering and
  a server-controlled exclusion sphere, now lethal when crossed.
- [x] Remove the four original procedural test asteroid spheres and
  relocate the starfield around the camera in large maps.
- [x] Add directional arrival, region routing, collision and view tests.
- [x] Send live Earth pilots to `sol:earth` with a real-radius map,
  retaining the old `1-1` first-login spawn only under test configuration.
- [ ] Preserve active hull/shields/loadout and physical orbital coordinates
  across region transitions, disconnects and full server restarts.
- [ ] Implement trajectory-preserving interplanetary handoff, orbital
  velocity/gravity, planet rotation, real docking and atmospheric entry.
- [ ] Add permanent stations, asteroid fields and contextual traffic
  in the respective planetary regions.


### Fatal planetary impact V1 (2026-11-03)

- [x] Replace the old harmless orbital-volume clamp with a server-owned
  lethal impact boundary at 1.08× the planet's actual mean radius.
- [x] Use swept 3D segment-sphere intersection to prevent high-speed
  tunnelling during manual flight or local plotted autopilot.
- [x] Zero hull, shields and momentum; mark destroyed and clear targets,
  waypoints and NPC pursuit; broadcast a single planetary-death event.
- [x] Show a planet-named crash message and release pointer lock on death.
- [x] Add pure and live map integration tests for normal approach,
  first impact, fast through-crossing and safety of other flight modes.
- [ ] Add escalating proximity/collision alerts and gravitational effects.
- [ ] Implement controlled respawn or rescue/recovery workflow for pilots.
- [x] Enable identical lethal collision and proximity warning behavior
  for Earth and every other SOL planetary region.


### Planetary proximity warning V1 (2026-11-03)

- [x] Server-owned CAUTION (1.55× lethal radius) and CRITICAL
  (1.20× lethal radius) proximity bands for all nine orbital maps.
- [x] Publish one event per zone change, including retreat to safety,
  without emitting a warning every 100ms simulation tick.
- [x] Include current per-pilot 3D collision clearance and warning level
  in world snapshots for late join/reconnect recovery.
- [x] Add amber/red cockpit alerts and corresponding stereoscopic in-world
  HUD warnings; hide the flat warning in SBS.
- [x] Test thresholds, 3D altitude, transition suppression,
  in-range join snapshots and complete caution→critical→clear flight.
- [ ] Add optional configurable warning audio.
- [ ] Add recovery/respawn mechanics, planetary approach autopilot
  protections and realistic atmospheric/orbital physics.

### Planet hazard parity across SOL and future catalogue extension (2026-11-03)

- [x] One physical radius source in the authoritative SOL catalogue.
- [x] All nine navigable worlds, **including Earth**, receive the same
  region-local kilometres, approach-direction arrival, caution/critical
  alerts, lethal swept collision and destroyed-ship protocol.
- [x] First Earth gameplay session enters `sol:earth`; the original
  `1-1` sector is retained only as an explicit test-only fixture.
- [x] Planetary region sizing can expand automatically for very large
  future planets; no special collision handler per body.
- [x] Generic future planet-ID syntax and procedural texture fallback.
- [x] Add full nine-planet map-server integration crash parity test plus
  fresh-Earth safe-arrival and catalogue radius regression tests.
- [ ] Build multi-system celestial catalogue and separate cross-system
  travel/wormhole transitions (future phase, not part of this release).
- [ ] Add destruction recovery and persistent ship state between sessions.


### Living SOL close-pass encounter V1 (2026-11-03)

- [x] Six independent, scheduled traffic vessels with distinct routes,
  purposes, manifests and return journeys, simulated without players.
- [x] Encounter opportunities derive from **real** intersecting SOL routes,
  relative velocity, departure time and fixed close-approach radius.
- [x] Announce a close pass once per pilot per vessel voyage, isolate pilot
  events over Phoenix and include current flyby in reconnection snapshots.
- [x] Show a 3D traffic ship in normal/SBS cockpits using real SOL relative
  bearing and distance-dependent visual magnification.
- [x] Provide Hail and Dismiss; private manifest requires server-checked
  authenticated hailing. Do not spawn NPCs or expose cargo on passive scans.
- [x] Extend traffic, navigation, event privacy, and cockpit geometry tests.
- [ ] Design a persistent **shared tactical encounter instance** at true
  relative vessel coordinates, with voluntary intercept/approach and rejoin
  to original sublight trajectory.
- [ ] Add lawful/hostile dispositions, distress requests, NPC-v-NPC
  conflicts, escorts, weapons and consequence/reputation systems.
- [ ] Persist traffic schedules and pilot encounter state across restarts.
 
### EncounterDirector V1 — server-owned classification (2026-11-03)

- [x] Classify already-observed strategic contacts as neutral flyby,
  patrol attention or hostile contact, with no NPC spawning.
- [x] Bind faction-owned Venus patrol to ZOC and provisional server-only
  standing threshold; leave missing standing neutral.
- [x] Emit pilot-specific classified encounter snapshots/events without
  stopping cruise; label classifications in the normal cockpit panel.
- [x] Add unit and navigation event regressions for classification.
- [ ] Integrate durable player-faction reputation and lawful NPC disposition
  changes; default traffic remains non-hostile.
- [ ] Add shared tactical encounter instances, voluntary/forced interception
  and route-safe resumption; policy labels do not start combat.
- [ ] Run Mix/JS suites and manually verify 3D + SBS UI in a live browser.


### Encounter decision hold V1 (2026-11-03)

- [x] Freeze only the involved pilot's strategic cruise progression upon
  a real server-owned close pass; all other ships and traffic keep moving.
- [x] Retain a pilot-scoped pending decision across channel reconnects.
- [x] Reject spoofed encounter identities, unsupported choices, premature
  course aborts and repeated resolutions.
- [x] Show a modal with Hail and Ignore / Resume actions, including an
  SBS per-eye version, while retaining real sensor-range validation.
- [x] Add deterministic navigation and authenticated-channel regressions.
- [ ] Execute Mix/asset suites, build assets, and visually verify normal 3D
  and SBS flows in a real browser/HMD.
- [ ] Introduce physical voluntary/forced interception, shared tactical
  instancing and ship-state-safe resumption, including NPC motion policies.
- [ ] Persist paused voyages and NPC traffic across full server restarts.

### SBS development LAN listener (2026-11-03)

- [x] Bind Phoenix dev endpoint to `0.0.0.0:4000` by default to support a
  headset/phone connecting to the laptop over trusted LAN Wi-Fi.
- [x] Provide `SUNRACER_LOOPBACK_ONLY=1` opt-out for laptop-only debugging.
- [ ] Verify remote HMD pairing from another device and review production
  origin/security rules before any public hosting.


### Encounter popup reliability and paired HMD notification (2026-11-03)

- [x] Open the existing laptop encounter modal as soon as the authenticated
  first-contact event arrives, without waiting for a navigation snapshot.
- [x] Restore held decision state from navigation snapshots on reconnect;
  block underlying Atlas focus until decision is resolved.
- [x] Mirror read-only, authenticated close-pass status to the paired
  headset in both SBS eyes while the helmet is in cockpit mode.
- [x] Add unit tests for per-eye rendering and channel tests for
  privacy filtering and read-only commands.
- [ ] Run tests, build assets, and manually verify both displays.
- [ ] Add authorized VR controls for choices only if/when the helmet is
  upgraded from a read-only viewer to an authenticated input device.

### Reliable procedural SOL encounter traffic (2026-11-03)

- [x] Retain the six existing scheduled traffic ships.
- [x] Launch a real, shared, server-owned vessel along a converging lane for
  the current playtest's interplanetary voyages; randomize type and phase.
- [x] Prevent population growth beyond 32 added vessels; expire each after
  15 minutes while retaining scheduled ships.
- [x] Preserve a pending pilot's established hail connection after physical
  sensor separation, without permitting arbitrary remote hails.
- [x] Add regression tests for a fresh corridor with no existing fleet,
  bounded spawning, contact selection and travel resumption.
- [ ] Execute tests and verify Earth–Venus popup on laptop/paired headset.
- [ ] Tune actual encounter chance, route density, sector/faction hostility,
  and implement shared tactical combat interception.



### SOL tactical encounter handoff (2026-11-03)

- [x] Allow Engage for held hostile and patrol contacts only; retain Hail
  and Ignore/Resume for ordinary neutral flybys.
- [x] Validate encounter ID and session on server before entering combat;
  prevent forged entry and resuming a voyage during an active fight.
- [x] Spawn a Dart-class NPC under contact's callsign in the pilot's current
  authoritative orbital map, near the live ship and outside planetary
  exclusion geometry. Use current planet visuals for collision clarity.
- [x] Permit local cockpit movement and weapon use during tactical hold,
  while retaining SOL voyage position/progress and multiplayer isolation.
- [x] Server-check NPC destruction before victory; permit explicit retreat,
  clean up enemy and target locks, resume original travel.
- [x] Route paired read-only HMD world subscriptions to actual orbital map.
- [x] Add core and Phoenix channel regression tests including auth and
  rejected client-originated victory.
- [ ] Execute full Mix/JS suites and verify laptop plus headset gameplay.
- [ ] Build a true isolated mid-voyage tactical arena rather than temporarily
  using the pilot's current planetary combat map.
- [ ] Implement pilot defeat/respawn, battle rewards, independent ship models,
  trade scene choices, and faction-specific patrol interception.

- [x] Cancel a defeated pilot's held SOL course on authoritative destruction
  and prevent a dead pilot from invoking a fake defeat or retreat.
- [x] Render tactical Dart variants as the actual 3D Dart ship model.
- [ ] Implement final death/respawn UX and economic consequences.


### Neutral trader attack choice (2026-11-03)

- [x] Offer Attack vessel for neutral SOL close-pass contacts, in addition
  to Hail and Ignore / Resume.
- [x] Validate the exact server-owned neutral encounter and pilot session
  before entering a local 3D tactical fight.
- [x] Make neutral tactical opponents passive until a confirmed damage hit;
  retain proactive hostile raider behavior.
- [x] Add UI action-choice tests and headless tests for retaliation, close
  pass, authorization, and voyage resumption.
- [ ] Run Mix/JavaScript suites and verify laptop plus SBS headset.
- [ ] Implement actual trader ship visuals and AI/behavior beyond the
  existing Dart-class tactical placeholder.
- [ ] Add standing/reputation penalties, faction-law response, cargo/loot,
  and rewards for attacking civilian traffic.


### Scow merchant hull implementation (2026-11-03)

- [x] Register a separate Scow NPC type with reference-grounded 210 armor
  and Garnet 10-class laser and provisional balance values.
- [x] Assign server-owned Scow identity to independent traders, couriers
  and scheduled merchant traffic without changing their routes or cargo.
- [x] Spawn actual Scow combat opponents via authenticated neutral SOL
  encounter handoff, while hostile fighters retain the Dart placeholder.
- [x] Create and render an original blue low-poly cargo vessel in normal
  cockpit and SBS phone headset with existing target selection geometry.
- [x] Add model and simulation tests for class identifiers, hull, damage
  and SOL encounter mapping.
- [ ] Verify full Mix/JavaScript test suites and live laptop/HMD gameplay.
- [ ] Implement NPC captain doctrine: flight, surrender, radio threats,
  variable morale and faction standing/reputation penalties, rather
  than assuming every attacked Scow fights to destruction.
- [ ] Implement larger Tanker merchants as a separate hull with stronger
  defenses; add salvage and transferred cargo after surrender/defeat.


### Scow graphics verification and impact orientation (2026-11-03)

- [x] Replace generic gray SOL close-pass preview with actual Scow
  merchant mesh (Dart for fighter contacts) using shared model factory.
- [x] Preserve Scow preview from `pending_encounter` during pilot hold.
- [x] Publish an authoritative `ship_class` in tactical map NPC snapshots;
  render identical class in laptop and paired SBS phone.
- [x] Display selected NPC class in the cockpit target readout.
- [x] Add model-switch, pending-contact and ship-class regression tests.
- [ ] Run full JS/Elixir test suite and check actual headset graphics.
- [ ] Track authoritative NPC heading and calculate front/aft impact arc
  from server-side 3D weapon hit geometry, not browser-derived positions.
- [ ] Replace pooled shields with forward/aft shields and original
  class-based mitigation, including Scow Aft-1.
- [ ] Add component damage (engines, beam, missiles, shields, ECM),
  persistent system status, handling penalties and TAC presentation.
- [ ] Separate cosmetic model hit markers from server-owned damage outcomes.


### Merchant voyage-aligned tactical movement (2026-11-03)

- [x] Stop using the four-corner legacy NPC patrol for merchant encounters.
- [x] Carry the existing shared SOL origin/destination through the
  authenticated encounter into the tactical map.
- [x] Project a short straight merchant transit lane using its real
  strategic bearing, deflecting only to avoid planet impacts/map edges.
- [x] Keep neutral Scow flight moving while defensive turret fire uses
  server-confirmed damage; do not make it chase the attacking pilot.
- [x] Publish stable course heading to desktop and headset renderers.
- [x] End combat on Scow lane exit, remove the local NPC, clear target locks,
  and resume the owner's SOL voyage even after losing the client connection.
- [x] Add pure route geometry and AI tests plus world-level escape tests.
- [ ] Run Mix and asset tests, then verify moving Scow in laptop and headset.
- [ ] Move combat to a genuine mid-space battle bubble tied continuously
  to shared strategic ships; reconcile ship death, cargo, and encounters.
- [ ] Add merchant captains' flee, surrender, defend, and radio responses,
  informed by morale, player threat and ship damage.


### Sunracer, inventory/equipment, and Scow survival (2026-11-03)

- [x] Make default ship 1 the original Sunracer while keeping existing
  player ownership, two configurations and other purchasable hulls.
- [x] Set starter Garnet to 10 and base armor to 300; four-tonne cargo
  capacity, Forward-1 shield, missile tube, .20G, and 45°/s as metadata.
- [x] Add Beryl/Sapphire replacement laser rules for Sunracer hardpoint;
  preserve additive multi-laser loadouts for later ship classes.
- [x] Expose authenticated server-owned equipment inventory and C-1/C-2
  layout at /equipment, with atomic fitting and account-scoped activation.
- [x] Create persistent server-owned commodity stacks and enforce ship
  cargo capacity under account and inventory locks.
- [x] Make provoked Scows evade at <=80% hull and surrender at <=35%;
  owner can accept surrender with server verification and return to SOL.
- [x] Protect surrendered merchants against automatic or manual laser hits.
- [x] Add Core, Sunracer DB and Phoenix controller/channel regression tests.
- [ ] Run full test/build suites and verify browser/SBS headset gameplay.
- [ ] Replace provisional speed with original Sunracer acceleration and
  turn dynamics as appropriate to game's tactical speed scale.
- [ ] Add original forward/aft directional shield-class laser and collision
  reduction, subsystem damage, equipment status and repair.
- [ ] Add an actual merchant captain's varied morale, danger appraisal,
  surrender offers and reputation/behavior consequences.
- [ ] Build docking/shipyard purchase, commodity trading and capacity-safe
  cargo transfer from a surrendered/destroyed strategic vessel.
- [ ] Reconcile persistent strategic NPC identity with temporary tactical
  encounter actor before implementing real cargo theft/loot.

### Strategic-to-tactical vessel reconciliation (2026-11-03)

- [x] Give scheduled and procedural SOL ships canonical combat conditions,
  inherited by tactical NPC actors rather than reset at each encounter
- [x] Bind tactical encounters to contact ID and traffic voyage number
- [x] Enforce one active tactical claim per real vessel, even with two pilots
- [x] Reconcile observed hull/shields on retreat, defeat and autonomous escape
- [x] Leave surrendered merchants disabled and destroyed ships as tombstones
- [x] Preserve strategic cargo unchanged and reject duplicate/stale reports
- [x] Keep tactical-claimed procedural contacts alive until resolution
- [x] Cover claim contention, tampering, persistent damage, surrender,
  destruction, and autonomous escape with headless regression cases
- [ ] Run Mix tests and check-only precommit on the Elixir workstation
- [ ] Introduce a genuinely shared mid-space battle bubble with multiple
  pilots targeting the same physical NPC simultaneously
- [ ] Add durable DB snapshots and recovery of in-flight settlement on
  unexpected OTP restarts, plus explicit salvage/claim lifecycle
- [ ] Add authenticated market and cargo surrender transfers using locked
  inventories; do not mint rewards from local combat actors

### Lightweight NPC cognition V1 — Symbrella-derived (planned)

Source: [Symbrella `symbolic_generation`](https://github.com/bushman77/Symbrella/tree/symbolic_generation). Extract **only bounded, reusable symbolic mechanisms**; do not embed the complete Symbrella brain or companion runtime in the MMO.

- [ ] **Structured perception + bounded working memory:** feed server-authorized encounter events (contact, attack, damage, assistance) into a small per-character active context. Adapt the relevant retention/admission ideas from `Brain.WorkingMemory` / `Brain.WM`; no natural-language parsing of game events.
- [ ] **Scoped episodic memory:** adapt `Brain.Hippocampus.Recall`'s scoped, recency-weighted retrieval to structured NPC episodes. Persist only salient encounters, with the remembering **character** identified separately from the strategic ship and tactical actor.
- [ ] **Goal and decision policy:** extract small pure, testable patterns from `Brain.GoalStack` / `Brain.ActionSelector` for goals such as trade, survive, threaten, surrender, and retreat. Produce *intentions*, never direct writes to combat, inventory, navigation, or ownership state; the authoritative game server validates and executes them.
- [ ] **Prewritten dialogue:** render approved lines from the chosen intent, NPC role/personality, and encounter context. Support bounded player dialogue choices; no generative dialogue or LLM.
- [ ] **First vertical slice:** one merchant captain recalls a prior attack or rescue, chooses an appropriate goal/response, and retains memory across tactical encounters and a server restart. Add deterministic tests for identity isolation, recall, intention validation, and fallback when cognition is unavailable.

**Non-goals for V1:** dictionary/brain-cell import, LIFG language parsing or lambda sentence composition, full Thalamus/ACC/OFC/DLPFC/neuromodulator processes, image/camera input, llama.cpp, and a GenServer per NPC. Keep Symbrella's personal companion identity/memory completely separate. Run cognition outside the map tick; reuse the existing bounded `Core.NPC.AI` for movement/combat, with safe deterministic fallback. Benchmark CPU, RAM, and decision latency before scaling NPC counts.


### Voluntary SOL free-flight cockpit (2026-11-05)

- [x] Atlas cruise represents AI-assisted strategic propulsion and avoids physical debris collision simulation.
- [x] Authenticated pilot can suspend a real SOL journey at the current position for conventional cockpit flight without encountering another vessel.
- [x] Each pilot receives an isolated, empty deep-space region under a supervised DynamicSupervisor; local coordinates never substitute for shared SOL position.
- [x] Returning to Atlas resumes exactly the stored journey and requires a surviving, server-authorized ship.
- [ ] Implement debris entities, swept collisions, physical hull damage and cockpit-only hazards; no random Atlas damage.
- [ ] Upgrade private local maps to shared, location-grounded tactical instances when co-located pilots interact.
- [x] Add channel and headless tests for authenticated entry/exit, remote map authorization, flight controls and ship condition gating.
- [x] Targeted Core, Phoenix Channel, and JavaScript tests passed in [SOL free-flight CI](https://github.com/bushman77/SunRacer/actions/runs/42067967403) on 2026-11-05.
- [ ] Manually verify browser transition, reconnect, server restart, and SBS headset; full repository suites remain a separate verification.


### SOL merchant cargo seizure and faction consequences V1 (2026-11-05)

- [x] Offer two distinct outcomes after map-verified merchant surrender:
  **release captain** without taking cargo or **seize cargo** and resume cruise.
- [x] Map a real SOL traffic manifest into capacity-limited physical cargo
  crates at a provisional rate of ten strategic units per one-tonne crate;
  retain the source's remaining manifest units.
- [x] Lock the account/inventory, enforce active ship cargo capacity, and
  issue a database-unique claim receipt per vessel and voyage. All item
  identities are restricted to the authoritative cargo catalog.
- [x] Apply the receipt's exact debit to the canonical strategic vessel on
  tactical settlement; reuse the original receipt on interrupted cleanup.
- [x] Add durable, deduplicated SOL faction events and account standings:
  first confirmed neutral merchant hit -12, civilian cargo seizure -18,
  with standing bounded to [-100, 100]. Raider encounters do not incur
  neutral-merchant penalties.
- [x] Refresh SOL encounter policy standing from PostgreSQL upon login, and
  update the in-memory navigation cache after a faction event.
- [x] Show the two choices in the cockpit and add cargo receipts/standing to
  the authenticated Equipment Locker.
- [x] Add isolated tests for catalog conversions, cargo capacity, idempotent
  replay, unrelated-account rejection, out-of-stock claims, faction penalties,
  canonical vessel debit and rejection of forged channel requests.
- [ ] Run database migration, full Elixir/JavaScript suites, build and live
  phone SBS verification on the developer workstation; these changes are
  committed but not locally executed in this authoring environment.
- [ ] Persist/recover the complete SOL navigation and in-flight settlement
  state across a full OTP/host restart. The SQL receipt prevents repeat cargo
  minting, but SOL traffic recovery is a separate consistency milestone.
- [ ] Make faction infractions a first-class map-level event so non-owner
  attackers and disconnect-mid-hit cases are captured without relying on
  the owner's Phoenix channel observing the shot.
- [ ] Add player-selected individual cargo lots, voluntary buy/sell orders,
  planetary dock warehouses, prices, taxes, smuggling inspections and
  law-specific reputation penalties.


### SOL orbital bases and forward refineries V1 (2026-11-05)

- [x] Derive one stable planetary **orbital base**, **forward refinery** and
  **three named docking bays** from each registered SOL destination
  (Mercury–Pluto, Earth included). The Sun is not a port.
- [x] Create a shared strategic stock ledger with distinct provisional
  industrial profiles and minute-based bounded refinery production.
- [x] Advance merchant traffic and refinery inventories in the same
  Solar Navigation GenServer clock, independent of active pilots.
- [x] Queue traders at full bays, unload their real arriving manifests,
  load outbound requested cargo only from available refinery stock and
  free berths on departure. Trade ships retain vessel/voyage identities,
  damage state and faction; disabled/destroyed vessels do not deliver.
- [x] Debit the origin refinery whenever the global shipping timetable
  or procedural neutral traffic launches a new trader. Previously
  underway seed ships count as starting-world assets.
- [x] Report local orbital-base occupancy only in authorized navigation
  snapshots and on berth changes; avoid remote inventories and full
  station broadcasts on every world tick.
- [x] Publish a fixed, safe orbital site in every planetary tactical map
  and render an original lightweight 3D base in desktop and paired SBS
  cockpit views. No new asset bundle or external download is required.
- [x] Add isolated tests for stock transfers, production, arrival/departure,
  bay queues, future-body station fallback, fixed orbital geometry and
  live Navigation-backed inventory consumption; Node tests cover the
  station pose and camera-relative stereo placement.
- [ ] Run the new ExUnit/Node tests and visually verify the orbital base
  in the real laptop and paired Galaxy SBS cockpit.
- [ ] Render *individual physically docked Scows* at their occupied bay
  coordinates and implement actual ship-to-station approach/docking
  trajectories. Current bay movements are strategic, not tactical
  physics or player-interactive docking.
- [ ] Add ship docking permissions, collision-safe approach corridors,
  port fees, faction-based access, purchase/sale pricing and warehouse
  transaction APIs.
- [ ] Persist refinery reserves, berth leases, production clocks and
  shared merchant state across OTP/server restarts. V1 station state is
  supervised RAM state; account cargo/standing already has its own
  PostgreSQL persistence boundary.


### Green Starbase — independent Earth–Mars landmark (2026-11-08)

- [x] The first independent interplanetary starbase now has a stable,
  server-owned SOL position midway between Earth and Mars. This is NOT
  the nine planetary forward refineries and creates no stock or NPC state.
- [x] Add a distinct green twin-pyramid Atlas icon and selectable, validated
  navigation destination. Pilots travel to its precise position through the
  existing SOL cruise/waypoint system; the server remains authoritative.
- [x] Render a low-poly, 1989-inspired green starbase in the ordinary and SBS
  3D cockpit after arrival. The design has opposing pyramids, an industrial
  central block and a *real open* front-facing docking aperture.
  Geometry lives in the installed desktop bundle, never Phoenix socket
  payloads. It is not a targetable/combat NPC.
- [x] Gate local rendering to a server-validated nearby idle SOL waypoint
  in the correct deep-space flight region.
- [ ] V1.1: station safety collision hull, special open docking corridor,
  proximity warning and speed/orientation approach guidance.
- [ ] V1.2: server-authorized bay entry, docking state and automatic removal
  of the player ship from active tactical space while docked.
- [ ] V1.3: persistent docked status and basic docked-services panel.
- [ ] V1.4: authenticated undocking/launch pose and temporary protection
  against immediate re-contact; server validates ship and bay occupancy.
- [ ] V1.5: actual credit-backed repair, shields, ammunition and trading
  through existing Ecto inventory/ship-condition transaction boundaries.
- [ ] Visually verify the real desktop client and paired-phone SBS graphics,
  alignment and scale at the docking mouth before activating docking.

### Pilot location continuity (2026-11-08)

- [x] Add PostgreSQL pilot checkpoints for SOL planet, voyage number,
  destination, mid-flight position, and interplanetary progress.
- [x] Persist the ship's authoritative local XYZ position and orientation on
  disconnect and every ten seconds while the game channel is connected.
- [x] Only restore an orbital pose when map ID, ship ID, voyage number and
  physical geometry all match. Ignore stale poses from earlier planetary visits;
  a new pilot still starts at Earth.
- [x] Rebuild SOL Navigation from the last versioned, validated checkpoint
  after OTP/server restart. Do not recreate stale NPC encounter leases.
- [ ] Run database migration and verify Venus reconnect, longer voyages,
  forced client termination and full Phoenix restart.
- [x] Extend checkpointing to manual deep-space regions and genuine empty-
  space waypoints, with the same map/ship/voyage checks and map bounds.
- [x] On logout, freeze the pilot's strategic cruise at the precise saved
  point; continue shared merchant traffic, then resume the player's voyage
  only after the next authenticated world join.
- [x] Invalidate old free-flight cockpit coordinates when automated cruise
  resumes so subsequent manual entries in the same voyage use fresh poses.
- [ ] Verify desktop manual free-flight logout/relogin and forced server
  restart in addition to the existing Venus reconnect regression.
- [ ] Persist shared merchant routes and base inventory separately.

### Green Starbase visual parity on paired SBS phone (2026-11-08)

- [x] Send only the canonical Green Starbase position/model and proximity
  flag to the read-only helmet navigation feed while at its SOL waypoint.
- [x] Track authenticated sector map ID from the headset's world snapshot so
  the existing stereo renderer can correctly show/hide deep-space objects.
- [x] Clear the station when departing; keep private contacts, cargo,
  pilot instructions and reputation out of the HMD rendering payload.
- [x] Add navigation-gating, payload and native stereo integration regressions.
- [ ] Live-test the Green Starbase from its exact Earth–Mars chart waypoint
  in both SBS eyes, including head tracking, approach and docking mouth.

### Phone SBS VR head-gaze prototype (2026-11-08)

- [x] Separate cockpit mesh/instruments from the camera. Ship orientation
  remains authoritative while device-orientation head rotation changes ONLY
  the Galaxy headset's local Three.js view.
- [x] Opt-in permission step and user recenter; gracefully retain normal SBS
  when motion sensors are absent, denied or unavailable over insecure HTTP.
  Camera sensor data never leaves the phone or issues flight input.
- [x] Add a physically ship-fixed NAV switch and read-only in-headset
  navigation display. Head gaze arms for 1.0 s, then fills a 0.8 s circular
  confirmation ring; looking away cancels, and holding never re-activates.
- [x] NAV, CLOSE and RECENTER are local headset controls only. Mouse steering,
  lasers, SOL course authority, docking and Phoenix channel contracts remain
  unchanged. No new assets, packages or database schema required.
- [x] Add optional trusted LAN HTTPS on port 4443 alongside the desktop
  loopback HTTP :4000, with strict exact-origin socket allowance. The HMD
  sensor requires a certificate valid for the laptop's LAN IP and trusted
  by the phone; no CA private keys or certificates are committed.
- [ ] Verify trusted HTTPS from Galaxy S21 on the local network, head sensor
  yaw/pitch/roll sign and neutral calibration. Untrusted HTTP origin typically
  blocks device-orientation permission in modern browsers.
- [ ] Verify both SBS eyes comfortably show reticle, NAV switch, countdown,
  and navigation panel without optical drift or cockpit/world camera clipping.
- [ ] Extend the same independent VR camera and gaze framework into ship and
  Green Starbase interiors after this prototype is validated.

### Earth respawn recovery: native verification (2026-11-08)

- [x] Authenticate respawn against a map-owned destroyed ship and restore its
  durable hull/shields, voyage and Earth position; reject client teleport requests.
- [x] Keep the death overlay included in installed Tauri markup and ensure it
  cannot be revealed during normal flight by Tailwind display precedence.
- [x] Add a whole-channel Venus-planet collision -> destroyed -> Earth reset ->
  fresh authenticated cockpit join -> flight-command acceptance regression.
- [ ] Run full ExUnit and JS/native test suites and manually playtest desktop
  destruction, respawn, Earth return and paired SBS viewer continuity.
- [ ] After live confirmation, proceed to Green Starbase Stage 6 services,
  beginning with repair pricing and credit-backed settlement.

### Green Starbase station attendants and dialogue V1 (2026-11-08)

- [x] Publish a server-owned fixed roster of six named kiosk contacts with
  room ID, job title and coordinates as compact world snapshot metadata.
- [x] Render low-poly attendant figures and in-world name/job labels in the
  shared desktop / paired SBS scene, without extra asset downloads.
- [x] Add a desktop-only E-to-talk prompt and keyboard-accessible response
  panel with distinct scripted topics for each role.
- [x] Validate docked session, matching room, physical range and permitted
  dialogue topic in MapServer on every dialogue request.
- [x] Repair contact reports live map-owned hull/shield values. No dialogue
  directly mutates money, cargo, equipment, missions or ship condition.
- [ ] Run Elixir, Phoenix and Node tests on the laptop and playtest all six
  kiosks, range/collision limits and HMD rendering.
- [ ] Wire real kiosk transactions, NPC schedules and larger dialogue trees
  in separate server-authorized milestones.

### Green Starbase rear airlock and station directory (2026-11-08)

- [x] Replace the formerly solid decorative hangar back wall with a real
  locally animated sliding door that opens as the pilot approaches.
- [x] Extend the MapServer-owned walking topology through a narrow airlock
  into a central concourse and six distinct walkable service rooms.
- [x] Build matching geometric walls, door apertures, raised signage, lit
  floors and counters for repair, trading, outfitting, resupply, missions
  and communications without downloading new assets.
- [x] Validate physically connected room transitions with bounded sweep
  collision, and persist room ID, walking position and heading using the
  existing authenticated location checkpoint and read-only SBS replication.
- [x] Show a compact station directory and live current-room label on the
  desktop; no fake purchase/repair/mission actions are enabled.
- [ ] On Pop!_OS: run tests, check passage through the small door, all six
  rooms, logout/reconnect from a service room, and verify phone SBS visuals.
- [ ] Add real NPC conversations and service transactions later, each with
  server-side permission and PostgreSQL consistency.

### Green Starbase authoritative station walking V1 (2026-11-08)

- [x] Add per-pilot server-owned station walking pose and bounded WASD,
  strafe/turn and mouse-look intents independent of the parked spacecraft.
- [x] Replicate the station avatar pose through existing world snapshots to
  desktop and read-only SBS; phone's local head tracking remains independent.
- [x] Restrict initial walking to the main hangar corridor with server bounds
  and a closed rear airlock. No client-driven teleport or alternate rooms.
- [x] Store the validated station-room position/facing in the existing
  PostgreSQL docked-ship checkpoint, tied to ship/map/voyage, without migration.
- [x] Restore the docked ship and avatar location after reconnect; checkpoint
  immediately on auto-dock, periodically and on clean logout.
- [ ] Run Elixir, Phoenix, JS/Tauri tests and perform real headset walking,
  reconnection, collision and launch checks.
- [ ] Add physical room transitions, detailed collision and real interactive
  services in separate milestones.

### Green Starbase automatic five-second docking (2026-11-08)

- [x] MapServer starts a server-owned five-second docking hold when the ship
  remains stopped inside the actual, collision-safe Green Starbase bay.
- [x] Cancel the hold if the ship moves, leaves the bay or loses its verified
  station eligibility; recheck SOL navigation authority before parking.
- [x] Automatically dock the existing player ship using the already-tested
  secured docking lifecycle, without any phone-originated controls.
- [x] Display the five-second countdown as a stereoscopic 3D HUD panel in
  both SBS eyes, plus a desktop countdown; no per-second socket spam.
- [x] Late-joining viewers resume the hold's remaining duration from the
  server's world snapshot; rejoining does not reset the hold on the server.
- [ ] Run core, channel and Node tests, then live-check stop, countdown,
  throttle-cancellation, automatic hangar transition and launch.

### Green Starbase immersive docked hangar V1 (2026-11-08)

- [x] The desktop 3D cockpit and paired read-only SBS headset now use a
  separate locally rendered industrial hangar interior while the existing
  MapServer world snapshot marks the authenticated pilot as docked.
- [x] Keep phone head tracking active through the same stereo camera while
  disabling invisible cockpit targeting and NAV gaze interactions in-station.
- [x] Restore the actual ship/cockpit scene on server-authorized launch,
  without copying the ship or changing flight, cargo, or persistent condition.
- [x] Replace the desktop's opaque fullscreen station panel with a compact
  corner services console so the new 3D space remains visible.
- [x] Preserve a docked pilot on reconnect from existing durable MapServer
  docking and world snapshots; keep the phone in its existing paired session.
- [ ] Live test approach / stop / dock / SBS view / reconnect / launch on Tauri
  and Galaxy S21 before adding repair charges and station commerce.
- [ ] Later: navigate through an interactive station interior, character
  movement, ship model at berth, signed economic transactions.

### Green Starbase Stage 4–7 — physical entry and launch (2026-11-08)

- [x] Allow docking only for a live authenticated pilot at the SOL Green
  Starbase waypoint, physically inside the central bay, stationary,
  with no active autopilot, throttle or laser engagement.
- [x] Park the exact existing ship inside MapServer's protected docked set,
  outside flight physics, targeting, collision and NPC combat. No ship cloning
  or combat repair occurs as a result of docking.
- [x] Preserve verified docked status in the pilot's existing PostgreSQL
  ship-pose checkpoint; a clean reconnect restores the parked state.
- [x] Simple docked interior panel and explicit server-issued launch command.
  Spawn the same ship outside the front entrance at a safe heading.
- [x] Reject forged or distant docking requests; no client-supplied position
  or station identity is used. No additional SQL migration is required.
- [ ] Stage 6 services: real repair prices, resupply, equipment, market, jobs.
  Current interior labels are disabled placeholders, not working services.
- [ ] Flight-test with the Tauri desktop client and paired SBS viewer.
  Verify approach, stop, dock, close client, reconnect, launch and inspect hull.

### Green Starbase Stage 3 — authoritative collision and proximity (2026-11-08)

- [x] Define the twin green pyramids, industrial struts, hangar frame, floor,
  and rear wall as swept collision solids in the server's physics coordinates.
  The central docking aperture remains OPEN: not a false solid sphere.
- [x] MapServer collision resolves both autopilot and manual thrust, stops
  unauthorized impacts outside the hull, and applies bounded impact damage
  without changing planetary refineries or planetary fatal impacts.
- [x] Activate the independent starbase's hull only when the authenticated
  pilot is stopped at the real SOL waypoint. Cache Navigation presence at
  one-second intervals rather than calling another GenServer every tick.
- [x] Distinct Green Starbase cautions, critical warnings, and the illuminated
  approach-lane label appear in the cockpit; docking is NOT yet authorized.
- [ ] Flight-test with 3D desktop and paired SBS: clear center approach,
  solid sidewalls, solid rear bulkhead, and remote deep-space inertness.
  Stage 4 adds docking clearance and a safe docked-state transition.

### SOL forward refinery collision safety V1.1 (2026-11-07)

- [x] Keep planetary fatal proximity independent from station approach telemetry;
  the Earth impact warning must never be mistaken for a refinery warning.
- [x] Derive an immutable 600-km station safety hull from each registered
  planet's server-owned orbital site. Sweep each player movement segment in
  true orbital XYZ coordinates, never against a projected Three.js mesh.
- [x] Resolve manual and autopilot station contact by stopping flight just
  outside the hull and applying bounded speed-dependent impact damage through
  the existing shield/hull combat rules. Destruction, if it happens, is a
  separate `:station_collision` cause rather than `:planetary_collision`.
- [x] Include independent caution/critical refinery warnings in authoritative
  snapshots and level-change events. Show a clearly labeled refinery warning
  in desktop/SBS cockpit and preserve world-state resynchronization behavior.
- [x] Add swept-contact, altitude-clearance, idle-tick, shield/hull,
  warning-transition, and map-server integration regression tests.
- [ ] Verify real laptop/SBS maneuvering against the **physical** station
  boundary. The long-range visual proxy may visually overlap the cockpit
  while the real station is still many kilometers away.
- [ ] Add explicit authenticated docking clearance, physical approach
  corridors, bay occupancy and speed gates before pilots can cross the
  protected hull boundary. The current sphere is a V1 safety approximation
  and does not authorize player docking.
- [ ] Spawn visible docked Scows at each numbered berth; reconcile their
  strategic cargo/occupancy with the same tactical physical identities.
- [ ] Later: tune collision volumes to the final mesh and hull scale, add
  repair/insurance/port fees, docking UI and proximity autopilot guidance.

### V1 ambient refinery drone logistics (2026-11-07)

- [x] Add **20 purely visual, non-targetable cargo drones** moving in four
  curved lanes between the planet-facing atmosphere and forward refinery.
  Two traffic lanes carry local resources inward and two carry processed
  supplies outward; phased repetition, subtle speeds and endpoint scale fades
  keep the streams continuous without creating world entities.
- [x] Draw using two reusable instanced low-poly meshes (cyan inbound and
  amber outbound). Reuse the camera-relative planet/refinery visual proxies
  so the streams appear connected in regular cockpit and SBS, without ever
  reinterpreting projected positions as physics or collision coordinates.
- [x] Render only while the current orbital planet and base match; hide
  automatically during SOL cruise, deep-space encounters and region changes.
  No Phoenix Channels, database records, cargo settlement, target selection,
  missile/laser hits, collision volumes, minimap objects or new assets.
- [x] Add deterministic path/phase, lifecycle, mismatch and visibility
  regression tests. Full in-game desktop and paired-phone SBS visual
  verification remains pending.
- [x] Validate the same four-lane stream geometry at 12 arrival bearings
  for each of Mercury–Pluto (including the dwarf planet). Add an atmosphere-
  tangent fallback for near-coincident display endpoints so a whole world's
  drone stream doesn't vanish at one approach angle.
- [x] Ensure every orbital refinery stays physically clear of its planet's
  fatal exclusion sphere; small planets such as Pluto use a minimum orbital
  spacing while retaining the same 600-km provisional station collision hull.
- [ ] Later: anchor streams to individually modeled berth pads and vary
  visual density from a single low-rate refinery activity indicator.

### SOL encounter overlap / mixed-faction guard (2026-11-05)

- [x] Keep one authentic pending/tactical encounter identity in every
  navigation snapshot while that pilot is fighting. Changing nearby traffic
  cannot replace the displayed combat vessel or faction mid-encounter.
- [x] Add a 15-second post-resolution clearance period to distinguish a new
  nearby ship's encounter from the just-finished fight. SOL traffic still moves
  and refineries still produce during this period.
- [x] Isolate tactical target locks and two-wing laser traces to the pilot's
  exclusively leased NPC. Another player's Scow or unrelated map NPC can no
  longer be struck by the same private encounter's weapon burst.
- [x] Reconcile faction offenses against both the SOL claim and the map's
  exact strategic contact/voyage identity. Seizure requires the verified
  tactical report's identity to match before any ledger credit.
- [x] Display the call sign and faction with each penalty and clear stale
  faction-hit banners when the tactical encounter changes.
- [x] Add regression tests for two overlapping Scows in one map and two
  distinct-faction merchants approaching the same pilot during one voyage.
- [ ] Run ExUnit/Node suites and live exercise on the developer workstation;
  code review is not a substitute for a passing test run.
- [ ] Longer term: separate physically shared multiplayer combat arenas from
  the current exclusive private tactical lease model, with explicit lawful
  collateral damage and faction-incident attribution.


### Scow defensive combat reliability (2026-11-06)

- [x] Reproduce the movement/range ordering defect through the complete
  MapServer combat path before changing production logic.
- [x] Preserve the AI decision-time firing origin through authoritative
  resolution so same-tick cruise/evasion cannot cancel a legitimate shot.
- [x] Keep neutral Scows passive until a confirmed hit and target only the
  pilot who owns the provoked tactical encounter.
- [x] Preserve the Scow's strategic identity, cargo settlement, faction,
  route heading and destination while it defends, evades or surrenders.
- [x] Prefer a collision-checked 340-unit Scow encounter separation and keep
  520-unit directional candidates as safe planetary/map fallbacks.
- [x] Cover defensive events/damage, cooldown, range rejection, movement,
  surrender/destruction and concurrent pilot isolation with deterministic
  full-MapServer tests.
- [x] Pass the focused NPC AI (4 tests), focused world/MapServer (45 tests),
  full umbrella (358 tests), and warnings-as-errors compilation checks.
- [ ] Resolve repository-wide Elixir 1.20 RC formatter drift before
  `mix precommit` can pass without unrelated formatting changes.
- [ ] Perform manual browser/SBS verification of neutral approach, defensive
  fire, evasion and surrender presentation.
- [ ] Replace private per-pilot tactical leases with a genuinely shared combat
  arena before introducing lawful collateral damage or cooperative defense.

## Unified GitHub Release Distribution — 2026-11-06

- [x] Release-manager source and workflows assembled on `sbs`; canonical version in root `mix.exs` (0.3.1), derived desktop build metadata and stable public filenames.
- [x] Ubuntu x86_64 OTP release build definition, migration entry point and CI startup smoke-test instructions.
- [x] Windows NSIS and Linux AppImage/`.deb` release staging, Tauri updater signatures, checksums and gated draft-first publication.
- [x] Release-specific offline version tests and push-time validation workflow.
- [ ] Inspect GitHub Actions validation results following merge/commit; resolve any CI build failures.
- [ ] Perform first signed end-to-end release test; GitHub Releases currently has no published package.
- [ ] Verify installer upgrades on real Windows/Linux systems and Android SBS phone pairing.
- [ ] Add separate EC2 deployment automation with backups, migrations and rollback controls.

See `docs/sunracer-release.md` for the distribution procedure.

### Release diagnostic packaging safeguard (2026-11-06)

- [x] Build local server diagnostics from temporary committed source rather than accidentally bundling workstation TLS keys.
- [ ] Run `./scripts/sunracer server` on Pop!_OS and verify a complete archive; isolated build may require additional disk space.

### Production Caddy compatibility (2026-11-06)

- [x] Align production runtime with observed working EC2 Caddy TLS on 443 and loopback-only Phoenix HTTP on 4000; preserve optional direct TLS.
- [x] Align Tauri default launcher URL with public HTTPS 443, migrate saved old production origin and revise tests/docs.
- [ ] Rebuild and stage server release from updated source; configure `SUNRACER_PROXY_MODE=true` only in private EC2 systemd environment.
- [ ] Run production migration and controlled cutover after verifying database backup, then confirm public HTTPS and websocket operation.
- [ ] Publish/install new signed client version so existing Tauri installations adopt port 443 by default.

### Installed production client on HTTPS-inspected networks (2026-11-06)

- [x] Add opt-in native Tauri/WebKitGTK SOCKS5 handling for installed clients;
  public HTTPS certificate validation remains enforced.
- [x] Add one-command SSH tunnel + installed client runner and regression tests.
- [ ] Rebuild, reinstall and smoke-test the installed Linux production client
  through SSH with the current Fortinet-filtered network.

### Pilot registration verification recovery (2026-11-06)

- [x] 24-hour, SHA-256-digested, single-use email verification tokens.
- [x] CSRF-protected activation confirmation POST (safe GET for link scanners).
- [x] Non-enumerating resend form and per-account resend throttling.
- [x] Recovery path for failed initial email delivery without duplicating starter assets.
- [x] Domain/controller tests and separate registration CI workflow.
- [ ] Verify a production sending identity, configure Resend privately on EC2, and test real signup.
- [ ] Add durable mail outbox/automatic retries, per-IP abuse controls and password reset before public launch.

### Production email sending platform — 2026-11-06

- [x] Retain Swoosh as the mail API and add optional SMTP transport via gen_smtp.
- [x] Select Swoosh SMTP / Resend through a private environment setting, requiring TLS and provider credentials.
- [x] Separate working outbound transport from an explicit production registration open switch.
- [x] Add an operator-only probe to send a single test email without creating an account.
- [x] Document installation, private SMTP configuration, provider verification and a safe production test.
- [x] Resolve and commit gen_smtp / ranch Mix dependency lock entries.
- [ ] Validate production OTP release packaging and an actual SMTP delivery test.
- [ ] Verify SMTP sending identity, install private credentials, deliver an email to a real inbox.
- [ ] Open public registration only after real delivery succeeds and abuse controls are reviewed.


### SOL location-dependent space environments — Stage 1 (2026-11-20)

- [x] Define a single, server-owned visual-region catalog in compressed SOL game km:
  a broad asteroid belt (3D annular band), one fictional ion storm and
  a small Earth orbital-debris region. Deep space remains sparse.
- [x] Select the current environmental profile from the authoritative SOL
  ship position; belt intensity ramps in from its boundaries.
- [x] Replicate read-only region geometry and the selected profile through
  existing authenticated Navigation snapshots; the Atlas renders overlays
  without inventing destinations or changing navigation geometry.
- [x] Add pure classification boundary tests and Atlas rendering regressions.
- [ ] Run ExUnit and Node suites on the developer workstation (not run in
  this GitHub-only edit environment); manually inspect chart zoom and labels.
- [x] Stage 2: stable, deterministic nearby procedural scenery for ordinary
  and paired-phone 3D cockpit. Instanced meshes are visual-only, have no hitboxes,
  and use local-map/region-seeded cells so Atlas toggles cannot reshuffle them.
- [ ] Run the new Node field tests and visually verify desktop and SBS asteroid
  density, scale, sparse space and plasma colors on real devices.
- [ ] Stage 3: server-owned persistent physical hazards, legitimate collision
  geometry, salvage and damage; only after separate safety and persistence
  contracts have been tested.

- [x] Deliver the sanitized visual profile to the read-only paired helmet feed
  so both SBS eyes can render the same local environmental scenery.
- [x] Add regression tests for paired-device privacy and scene metadata; include
  environmental Core/Node tests and JS syntax checking in SOL free-flight CI.

### Pilot HMD smoothing/comfort fixes and predicted mouse look (2026-11-20)

- [x] Smooth headset entities between Phoenix/relay updates.
- [x] Single animation-frame request on the headset across sleep/wake.
- [x] `viewport-fit=cover` on `/helmet`.
- [x] Proximity warnings, encounter hold and surrender in the stereo HUD.
- [x] Pooled beam meshes; gap-aware SBS picking; parallel SBS eye axes;
  depth-correct sight ring; headset DPR cap 2.0; inward first-run gap.
- [x] Optional lens distortion pass (beta, off by default).
- [x] Laptop own-ship prediction between server ticks (mouse and keyboard).
- [ ] Run `mix test` / `mix precommit` (new controller test added).
- [ ] Manually verify on the S21 headset: full-width eye viewports, smooth
  motion on Phoenix and LAN relay, no frame-rate drop after sleep/wake,
  gaze cursor depth on NAV/HUD controls, HUD readability at DPR 2.0,
  distortion on/off.
- [ ] Browser-verify mouse-look feel on LAN and EC2.
- [ ] Calibrate lens distortion coefficients and per-headset FOV; consider
  storing them with the gap/IPD calibration.

### HMD head-tracking warning flash (2026-11-21)

- [x] Hold the last head pose while the sensor is quiet; neutral (not "lost")
  while a recenter waits for a fresh sample.
- [x] Show the cockpit warning only for denied / unsupported / HTTPS-required.
- [ ] Verify on the S21: hold still >2 s, tap-recenter, gaze RECENTER — no
  panel and no view snap.

### Green Starbase launch direction (2026-11-21)

- [x] Launch faces out of the bay; regression test flies 10 s at full
  throttle from launch without hull contact.
- [ ] `mix test` and an in-game launch check (laptop and headset).

### Manual laser aim (2026-11-21)

- [x] Wing lasers converge on the central sight (server-owned eye line).
- [ ] `mix test`; in-game check that a target in the sight ring is hit.
- [ ] Consider per-ship-class hit radii (Scow and freighters are larger
  than the 40-unit sphere).

### Story prologue: "First Run" (story-driven tutorial) — prologue playable server-side, not manually play-tested (2026-11-21)

Design: `docs/story-first-run.md`. An original SOL story whose prologue (a
first Helios courier run, Earth to Mars, interrupted by a raider attack on
Vesper-02) teaches flight, cargo, navigation, encounters, combat, surrender,
docking, station walking and mission completion. Branch `story_line`.

- [x] Story premise, cast, nine-step prologue with server triggers, failure
  rules and the Chapter 1 hook written down; Brad's decisions recorded.
- [x] Story progress store: `story_progress` (per pilot and chapter: step,
  flags, skipped, step timestamps) advanced only by server-confirmed events
  under a row lock; pure step engine `Sunracer.Story.Prologue`.
- [x] Tutorial prompts and in-character comms lines: laptop cockpit card
  (`#story-comms`), one-line objective in the stereo HUD (laptop SBS and the
  paired phone headset via `helmet_story`), skip and resume.
- [x] Credits payout with a once-only receipt (`story_rewards`, unique per
  pilot and reward): 500 credits, Helios courier license flag, +5 Helios
  Courier Cooperative standing through the keyed faction-event ledger.
- [x] Staged encounters for one pilot: private Vesper-02 close pass (step 4)
  and a private, beatable Corsair-17 that surrenders at half hull (step 5).
  Neither enters shared traffic; live raider settings untouched.
- [x] Mara Venn, Juno Rook and Eno Kade story topics driven by story state;
  Mara's topic applies the scripted hull patch.
- [x] Mara's ai3d-generated 3D model plays its looping idle in the repair bay
  (client code and tests, 2026-11-23). The GLB file still has to be copied
  into `priv/static/images/game/station/`; not yet viewed in the cockpit or
  headset.
- [x] Combat balance for the first fight: player beam range 540 against
  NPC 420/380, so Corsair-17 is beaten by holding the range band
  (simulated; not flown).
- [ ] Manual play-through of all nine steps in the laptop cockpit and headset
  (not yet performed).
- [ ] Next milestone: Ilya Quill (Ship Outfitter) sells a small story-gated
  gear selection; first item still to choose.
- [ ] Open design questions: the leaker; confirm the one-time crate reissue
  at Earth (implemented provisionally to prevent a soft lock).



### Desktop HUD window customization

- Shared move, resize and reset controls for station, communications, inventory, story, network, tactical and Atlas panels; positions and sizes are stored locally per pilot. Existing cockpit lock and minimap controls remain unchanged; the unlocked ship status also gains width resizing. Station/dialogue delegated input remains intact.
- Added viewport clamping and preference validation tests. CI and manual desktop/Windows/SBS verification pending; no live deployment performed.


### Native gameplay browser guard

- Suppress WebView browser context menus and F5 / Ctrl+R / Cmd+R reload shortcuts during authenticated gameplay. Preserve custom Atlas menus, RMB firing, normal keyboard shortcuts, explicit logout and in-memory bearer credentials. Added native event regression tests; installed Linux and Windows WebView verification pending.


### Walkable ship interior during SOL cruise (desktop MVP)

- Optional first-person Sunracer cabin with bridge, crew quarters and engineering during active uninterrupted autopilot transit. Local bounded walking pose; existing server cruise and station movement authority remain unchanged. Return to cockpit automatically on arrival, encounter, Atlas, loss of session or SBS/headset activation. RMB cannot interrupt cruise while walking. Procedural interior is provisional, not a ship-specific GLB or shared multiplayer interior; SBS walk presentation remains future work.
- Added movement/eligibility tests. CI and live transit verification pending; no release deployment performed.


### Native station GLB texture decoding

- Permit local blob URLs in native WebView image and fetch CSP directives for Three.js embedded GLB texture decoding. Script and object restrictions unchanged. Added CSP regression test and GLB metadata audit command (`node clients/tauri/scripts/audit-station-textures.mjs`). Actual installed model appearance and binary asset metadata still need verification; no model files changed.


### Juno Rook station character model

- `missions` now resolves to `juno_rook.glb` on the existing station character loader, with the ai3d source prompt committed as `examples/juno/prompt.txt` in the ai3d repository. Deliberately a text prompt, since no approved reference image exists for Juno; her slate-blue liaison uniform follows the attendant colour `0x8ca8dd` she replaces.
- [x] Client mapping, documentation and tests (`node --test js/game/*_test.mjs`, 595 pass).
- [x] GLB generated on the RTX 3060 rig and committed (1.90 MB, 15,460 triangles, `idle` clip, no compression; texture audit passes).
- [x] Reviewed in the native cockpit: correct model, facing visitors, server-owned interaction prompt intact.
- [ ] Confirm the idle loop advances and the feet meet the floor plane; neither was in the observed frame.
- [ ] SBS headset review (not yet performed).
- [ ] Optional reroll with a wider A-pose if automatic weights prove to bleed between arm and torso (X extent 0.90 against Mara's 1.94).


### Station attendant idle variation

- Per-attendant idle phase and playback rate, plus a shallow procedural arm swing over ai3d's generated idle, which animates only the spine and head. Runtime only: no asset, rig or network change.
- [x] Implementation and tests (`node --test js/game/*_test.mjs`, 604 pass).
- [ ] Observe in the native cockpit and judge the amplitude; 0.045 rad is a conservative first guess, not a reviewed value.
- [ ] Watch for forearm clipping on characters whose arms sit close to the torso (Juno's X extent is 0.90 against Mara's 1.94), which is where ai3d's automatic weights are most likely to bleed.
- [ ] Richer motion still needs real clips: the rig is Mixamo-named, so Mixamo actions retarget onto it without manual rigging.


### Station attendant gestures

- Gesture clips play as one-shots over the idle, scheduled per attendant. The runtime half is done and inert; the clips come from ai3d merging Mixamo animations onto the rig.
- [x] Runtime scheduler, crossfading and tests (`node --test js/game/*_test.mjs`, 611 pass).
- [x] ai3d merge stage, tested in real Blender (`bushman77/ai3d@72f81b3`).
- [ ] Download Mixamo clips into `~/ai3d/gestures/` and re-run the characters; nothing is visible until then.
- [ ] Review gesture frequency (currently every 14-30 s) and whether the ease duration of 0.45 s reads well against ai3d's idle.
- [ ] Hand-detail gestures are unavailable: the rig ends at the hand with no finger bones, and the generated hands are fused. Whole-body gestures only.
