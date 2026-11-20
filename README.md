# BeastTrainingTracker.Kuro

A fork of [Beast Training Tracker](https://www.curseforge.com/wow/addons/beast-training-tracker)
by Socks, maintained by Kuro for WoW Forever.

Tracks which pet ability ranks your hunter has learned, which beasts teach the
rest, and the rare / elite pets worth collecting. Works on its own; Questie,
TomTom and RareScanner add extras when they are installed.

This fork exists so it can be installed **next to the original** without the
two fighting over saved data, frames or slash commands. Everything global is
renamed, and one setting is added: the addon can switch itself off on
characters that are not hunters.

| | Original | This fork |
|---|---|---|
| Folder / TOC | `BeastTrainingTracker` | `BeastTrainingTracker.Kuro` |
| Slash commands | `/btt`, `/beasttraining` | `/bttk`, `/beasttrainingkuro` |
| SavedVariables | `BeastTrainingTrackerDB` / `Backup` / `Seen` | `BeastTrainingTrackerKuroDB` / `Backup` / `Seen` |
| Named frames, LibDataBroker object, HereBeDragons pin groups | `BeastTrainingTracker*` | `BeastTrainingTrackerKuro*` |
| Export format | `BTT1:` | `BTT1:` (unchanged, so exports move both ways) |

Saved data from the original is **not** picked up automatically. Use
Backup → Export in the original and Backup → Import here to carry it over.

Target client: WoW Forever (`_forever_`, interface `16001`, Mainline UI code).

## Usage

| Interaction | Result |
|---|---|
| `/bttk` (or the minimap button) | Open / close the window |
| `/bttk abilities` \| `hunt` \| `rarepets` \| `pet` \| `settings` \| `backup` | Open a tab directly |
| Open **Beast Training** in game | Every rank shown there is recorded as learned. Nothing is ever removed by a scan |
| Tame a beast that teaches something new | The new rank is recorded from the “You have learned” message, with a popup |
| Click a rank / beast / zone in any tab | Adds a waypoint stop to the hunt route (TomTom arrows if installed, a built-in map pin otherwise) |
| Shift-click | Starts a new route to every teacher of that rank |
| `/bttk pins` or right-click the minimap button | Show / hide every pin this addon draws |
| `/bttk tracker` or middle-click the minimap button | Show / hide the zone tracker panel |
| `/bttk petxp` or right-click the pet XP bar | Pet XP bar options |
| `/bttk clearwp` | Remove the waypoints this addon added |
| `/bttk where <beast>` | Where a beast’s map locations come from (for bug reports) |
| `/bttk rares` | Rare teachers you still need, with RareScanner timers |
| `/bttk status` | Saved data info, last scan, coordinate sources |
| `/bttk reset` | Wipe saved ranks for this character (asks first) |

## Only run on Hunters

On by default. The checkbox sits in the upper-right corner of the window, next
to the close button, on every character.

On a hunter it changes nothing. On any other class, while it is ticked, the
addon does nothing at all: no trainer scans, no learned-ability parsing, no
alerts, no tooltip lines, no map or minimap pins, no zone tracker, no pet XP
bar, no Questie lookups. Only two things stay:

- the main window, locked to the **Settings** tab (the other tabs are greyed
  out), so the option can be turned off again;
- the minimap button, whose left-click opens that window. Its tooltip says why
  the addon is idle; right- and middle-click do nothing.

`/bttk` with any other sub-command prints a one-line hint instead of running.
Untick the box and everything starts up on the spot; tick it again and pins,
routes, tracker and XP bar are taken down immediately.

## Map pins

Settings → Map pins controls how busy the maps get:

- **World map pins** and **Minimap pins** - each is *None*, *One per ability*
  (default: one pin per missing ability, the closest beast that teaches it),
  *Nearest spawn only* (one pin per beast, at the spawn closest to you, or the
  middle of its range on other maps), or *All spawns* (every known spawn point,
  as the original addon draws them). The minimap shows its selection nearest
  first and does not zoom-scale.
- **Pin size** (4–24 px, default 4) and **Pin opacity** (20–100 %).
- **Zoom growth** - world-map pins are drawn at *Pin size* fully zoomed out and
  grow to this multiple (up to 3x, default 2x) fully zoomed in. *Off* keeps them
  one size.

## Alerts

When a nearby beast teaches a rank you need, the "tame it!" banner and chat
line carry a second line, **Eats: Meat, Fish**, so you know you can keep it fed.
The same `Eats:` line sits under the "Teaches ..." lines in the beast's tooltip.
Diets are per family and identical on Forever and Classic Era (Era's "Owl" is
Forever's "Bird of Prey"; Era has no Fox or Core Hound).

Settings → Alerts → **Alert sound...** opens a picker: a list of game sounds,
each with *Play* and *Use*, plus a box for a custom sound - a file path such as
`Interface\AddOns\MyAddon\ding.ogg` or a FileDataID. Default is the epic loot toast.

## Tabs

| Tab | What it shows |
|---|---|
| Abilities | Every pet ability rank, learned / implied / missing, with the beasts that teach it and the zone you are in highlighted |
| Hunt Planner | Zones with ranks you can tame at your level, lowest level first or most new ranks first |
| Special Pets | Rare, elite and quest-spawned beasts from Petopia, with a drawer showing a 3D model, traits, respawn time and RareScanner timers |
| My Pet | Upgrades your current pet could be taught, what unlocks in the next six pet levels, and known abilities it does not have |
| Settings | Map pins, route line, alerts, zone tracker, pet XP bar, minimap button |
| Backup | Export / import the learned-rank list and tamed special pets as a text string; reset |

Learned ranks are stored per character and only ever **added** by scans. A
second copy is kept account-wide and restored automatically if the per-character
data goes missing.

## Optional addons

| Addon | With it | Without it |
|---|---|---|
| Questie | Spawn points for every beast | Pins and routes only include beasts you have spotted yourself (targeted, moused over or seen a nameplate) |
| TomTom | Waypoint arrows | A built-in world map pin and minimap edge marker point at the current stop |
| RareScanner | Live rare timers, last-seen spots, and it takes over alerts for rares on its list | Static rare data only |

## Installing from source

Copy this repository into
`World of Warcraft/_forever_/Interface/AddOns/` as a folder named
**BeastTrainingTracker.Kuro**. The folder name and the `.toc` filename must
match exactly or the client will not list the addon.

From the workspace this lives in, `cmd\publish.cmd` does that copy.

## Development

```sh
lua5.1 tests/run.lua    # headless logic suite (Core, Geo, Rares)
```

The harness in `tests/harness.lua` stubs the WoW API; UI modules are not
covered and need an in-game check. `CHANGELOG.md` carries the fork’s changes
on top of the upstream history.

## Credits

Beast Training Tracker is by **Socks**. This fork keeps the original author
line in the TOC and changes only what is needed for it to coexist with the
original and stay quiet on non-hunters.
