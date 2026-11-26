# Stable Master pins (Classic Era + Forever)

Status: **IMPLEMENTED - in play-test** (built 2026-11-26; Era confirmed showing pins + trainer line)

Show every stable master on the world map (and, on Classic Era only, the minimap), let the
hunter click one to add it as a route stop, and surface the nearest one via `/bttk stable` and a
line on the Beast Training window. Hunter-only, QuestieDB-sourced.

Related: `README.md` (Map pins), `Client/Client.lua`, `Geo.lua` (pin section ~L917),
`AddonManagement\_EXTERNAL_APIS\questiedb_contract_4.md`, `AddonManagement\PROJECT_STRUCTURE.md`
(file-segregated client interfaces).

## Decisions (owner, 2026-11-25)

| # | Question | Decision |
|---|---|---|
| 1 | Data source | **QuestieDB only** (`NpcDB.npcFlags & STABLEMASTER`). No static table. Without QuestieDB the feature is simply absent, with a status line saying so. |
| 2 | Where shown | World map **and** minimap - but see 5. Stable masters are in towns, so they do not clutter hunting areas. |
| 3 | Faction filter | Yes: hide NPCs whose `friendlyToFaction` excludes the player's faction. |
| 4 | Interaction | Click = add waypoint / route stop exactly like beast pins. `/bttk stable` prints and waypoints the nearest one. A **"Nearest stable master"** line is added to the Beast Training window. |
| 5 | Minimap | **Classic Era only.** Era's minimap tracking menu has no townsfolk entries (that arrived in TBC), so there is no native way to see stable masters there. Forever's Mainline UI has a native *Stable Master* tracking entry for hunters, so we draw none on the minimap there. |
| 6 | Client scope | `ns.Client` owns only what actually differs per flavour (minimap-pin policy, trainer-frame anchor). HereBeDragons / `C_Map` already behave identically on both clients and stay in `Geo.lua`. |
| 7 | Non-hunters | Hunter-only: obeys `ns.Active()` like every other pin; nothing drawn, no command output beyond the usual idle hint. |

**Assumption:** "QuestieDB listed as a dependency" = it stays in `## OptionalDeps` (already there) so the
rest of the addon keeps working without it; only this feature requires it. Say so if you want it in
`## RequiredDeps` instead - that would make the whole addon refuse to load without QuestieDB.

## Ground truth (read from the installed QuestieDB v1.1.3, contract 4, identical on Era + Forever)

```lua
LibQuestieDB.Npc                        -- == NpcDB global; capture THIS (globals get clobbered, see contract notes L94)
LibQuestieDB.Enum.npcFlags.STABLEMASTER -- already resolved for the active flavour by src/api.lua:
                                        --   Classic / Forever tables: 8192; TBC+: 4194304. We never hard-code the number.
Npc.GetAllIds(true)                     -- table<NpcId, true>, for the one-time scan
Npc.npcFlags(id)   -> number?           -- bitmask; bit.band(flags, mask) == mask
Npc.name(id)       -> string?           -- Questie skips names starting "[DND]"
Npc.friendlyToFaction(id) -> "A"|"H"|"AH"|nil   -- nil = hostile to both (skip)
Npc.spawns(id)     -> table<AreaId, {{x,y,phase?},...}>   -- percent 0..100; -1,-1 sentinel = skip
Npc.zoneID(id)     -> AreaId?
```

Questie's own townsfolk builder (`Questie\Modules\QuestieMenu\Townsfolk.lua` L55-L77, L115) does
exactly this scan and uses icon `Interface\Minimap\tracking\stablemaster`, which exists on both clients.
AreaId -> uiMapID goes through the existing `MapFor(area)` in `Geo.lua` (LibQuestieDB ZoneDB tables).

## Client interface additions

Add to `Client.INTERFACE` in `Client/Client.lua`, implemented in both flavour files (`Client_Select.lua`
already warns on any mismatch):

| Method | Era | Forever | Why it is in the Client |
|---|---|---|---|
| `StableMasterMinimapPinsWanted()` -> bool | `true` | `false` | Decision 5: Forever has native minimap tracking, Era does not. |
| `StableMasterNativeTrackingHint()` -> string\|nil | `nil` | `"Minimap: enable Stable Master in the minimap tracking menu."` | Shown in Settings / `/bttk stable` so the Forever user knows where the minimap pins went. |
| `TrainerFrameNearestAnchor()` -> `{ parent=, point=, relPoint=, x=, y=, width= }` or nil | anchors into the empty box left of **Train** (bottom-left of `ClassTrainerFrame`, see screenshot: wide empty slot at the bottom) | TBD - Mainline trainer frame layout differs; verify in game, fall back to `nil` = no trainer line | The only flavour-specific UI geometry in the feature. |
| `PlayerFactionKey()` -> `"A"` \| `"H"` \| nil | `UnitFactionGroup("player")` mapped | same | Keeps the faction API out of Geo.lua, mirrors `friendlyToFaction` shape. |

Shared constants in `Client.lua` (identical on both): `Client.STABLE_MASTER_ICON = "Interface\\Minimap\\tracking\\stablemaster"`.

## Data layer - `StableMasters.lua` (new file, loads after `Geo.lua`)

```lua
ns.Stables = {
  ready  = false,           -- scan finished
  status = "waiting",       -- for /bttk status + Settings
  list   = {},              -- { { id=, name=, map=, x=, y=, faction="A"|"H"|"AH" }, ... }  one entry per spawn point
}
function Stables.HasSource()      -- LibQuestieDB and LibQuestieDB.Npc and Enum.npcFlags.STABLEMASTER
function Stables.Scan()           -- coroutine, yields every ~700 ids like Questie; runs once after Geo.ready
function Stables.Nearest()        -- -> entry, distance2 | nil   (same map as player only; else nil + reason)
function Stables.ForMap(mapID)    -- entries on that uiMapID (faction-filtered)
```

Scan rules (mirror Questie): flag match, name not `[DND]`, `friendlyToFaction` is `AH` or equals
`Client.PlayerFactionKey()` (nil -> skip), every spawn `{x,y}` with `x >= 0` and a resolvable `MapFor(area)`.
Result is session-only (no SavedVariables). Scan is scheduled from the existing QuestieDB-ready
coroutine in `Geo.lua` (`Geo.ready = true` branch) so it never races the name-index build.

While in there: `Geo.lua` currently reads the **`NpcDB` global** (`HasQuestie`, `QuestieInfo`, `Explain`,
`OnLogin`). Capture `LibQuestieDB.Npc` into a file local once and use it everywhere (contract note L94).

## Pins - `Geo.lua`

- New HBD ref `REF_STABLE = "BeastTrainingTrackerKuroStable"` with its own `stableWorldUsed / stableMiniUsed` pools,
  so beast-pin rebuilds (`ClearPins`) do not churn stable pins and vice versa.
- `Geo.UpdateStablePins()`: skip unless `ns.Active()`, `ns.db.opts.stablePins`, `Stables.ready`, not `opts.pinsOff`.
  - World map: every entry, `AddWorldMapIconMap(REF_STABLE, pin, map, x, y, 0)`. Count is small (~60 on Era), no thinning.
  - Minimap: only if `Client.StableMasterMinimapPinsWanted()`; entries on the player's map, `AddMinimapIconMap(..., false, false)`.
  - Size = `opts.pinSize` scaled like rare pins (x1.33, min 10 px so the stable icon is legible); alpha = `opts.pinAlpha`;
    zoom growth via the existing `Geo.ApplyPinZoom()` (extend `worldUsed` iteration to include `stableWorldUsed`).
  - Border colour: new fixed colour (suggest tan `0.9, 0.75, 0.45`) so they read as "service", not "beast".
- Tooltip: `"<Name>"`, `"Stable Master"`, zone name, `"Click: waypoint"`.
- Click: `Geo.AddStop(Geo.MakeStop({map,x,y}, "<Name> - Stable Master", nil, true))` - a **manual** stop
  (`manual = true`) so `OrderStops`/`PruneRoute` keep it (they already keep manual stops). Needs a small
  `Geo.WaypointSpot(spot, label)` helper since `Geo.Waypoint(t, label)` takes a teacher record today.
- `Geo.QueuePins` signature gains `tostring(o.stablePins)` and `tostring(ns.Stables.ready)`; `UpdatePins` calls
  `UpdateStablePins` at the end. `OnDeactivate` and `TogglePins` (master switch) clear/hide them too.

## Commands and UI

- `/bttk stable` -> nearest entry on your map: `"nearest stable master: <Name> in <Zone> (xx, yy) - waypoint set"`
  and adds it as a route stop. If none on this map: list the maps that have one (nearest zone names) or the
  reason (`QuestieDB not installed` / `still loading`). Append `Client.StableMasterNativeTrackingHint()` when non-nil.
- Beast Training window: one FontString `"Nearest stable master: <Name> (xx, yy)"` placed by
  `Client.TrainerFrameNearestAnchor()`; clickable (same waypoint action); hidden when the anchor is nil, the
  frame is not Beast Training (`IsBeastTraining()` in Core.lua L300), or nothing is known. Created lazily in
  `HookTrainer()` (Core.lua L338).
- Settings -> Map pins: checkbox **"Stable master pins"** (`opts.stablePins`, default **on**) with tooltip
  explaining the Era/Forever minimap difference; greyed with the reason when `Stables.HasSource()` is false.
- `Geo.AddonStatus()` Questie line: append `", %d stable masters"` once ready.
- README: new bullet under *Map pins* and a row for `/bttk stable` in the Usage table.

## Tests (`tests/run.lua`, headless)

- Harness: stub `LibQuestieDB = { Npc = {...}, Enum = { npcFlags = { STABLEMASTER = 8192 } }, Support = ... }`
  with 3 NPCs: one friendly `AH`, one `H`-only, one `[DND]`-named; spawn on a mapped area.
- Scan keeps 1 (as Alliance) / 2 (as Horde), skips `[DND]`.
- `Stables.Nearest()` picks the closest on the player's map; nil off-map.
- `/bttk stable` says `not installed` when `LibQuestieDB` is nil.
- Client_Select still reports zero warnings with the four new methods (both flavours).

## Phases

- [x] **P1 Client surface** - add the four methods + icon constant to `Client.lua`, implement in both flavour files.
- [x] **P2 Data** - `StableMasters.lua` scan + `Nearest`/`ForMap`; TOC entry; `Geo.lua` switch from `NpcDB` global to `LibQuestieDB.Npc`; schedule scan after `Geo.ready`.
- [x] **P3 Pins** - `REF_STABLE` pools, `UpdateStablePins`, tooltip, click-to-waypoint, master-switch/deactivate handling.
- [x] **P4 Command + Settings** - `/bttk stable`, `opts.stablePins` checkbox, status lines, README.
- [x] **P5 Trainer line** - Era: shown on `CraftFrame`; Forever anchor still `nil`.
- [x] **P6 Tests** - harness stubs + 7 cases; `lua5.1 tests/run.lua` 58/59 (the 1 failure is the pre-existing `version:` case).
- [ ] Play-test on both clients, then one commit per PROJECT_STRUCTURE rules.

## Findings from play-test (deviations from the plan above)

- **Era's Beast Training window is `CraftFrame`** (Blizzard_CraftUI, "Training Points" + Train), not
  `ClassTrainerFrame`. `HookTrainer()` hooks both; the Era anchor is the empty band above the ability list
  (`TOP` of `CraftFrame`, -8/-66, centred) where the hidden skill bar would sit.
- **Stable pins are exempt from zoom growth** (`ApplyPinZoom` sets them to scale 1). City maps (Darnassus)
  have a zoom range that shrank them to a few pixels; a handful of service pins do not need to recede.
- Pin border is the tan colour at 25% alpha (an opaque square looked wrong behind the stable icon).
- TOC now declares `## Interface-Vanilla: 11509` so `publish.cmd` targets `_classic_era_` (it was Forever-only).

## Open questions / TBD

- Forever Beast Training window geometry - need an in-game look (screenshot like the Era one) to fill in
  `TrainerFrameNearestAnchor()` for Forever.
- Should `/bttk stable` **replace** the current route (like shift-click) or **append** (like click)? Spec says append.
- Stable pin border colour / size multiplier - cosmetic, adjust after first in-game look.
