# BeastTrainingTracker.Kuro — diet line on the "tame it" alert

Status: **draft, awaiting approval** (2026-11-20)

## Goal

When the nearby alert fires (`Alerts.lua` → `Alert(unit, how)`), add a **second line** listing the
foods that beast's family eats, so the hunter knows whether they can keep it fed before taming.
Also add an `Eats: …` line to the unit tooltip (`AddTeachLines`). Both game flavours
(WoW Forever and Classic Era) are supported through the existing `Client/` layer.

## Ground truth — diets per family

Petopia (`wow-petopia.com/forever/diets.php`, `/classic/diets.php`) was 502 at the time of writing.
Cross-checked instead against three independent sources that agree on every row:

- wow-forever.online/hunter-pets (read from Forever client build 70338) — states *"Diets are the same as in Classic Era"*
- wowcampfire.com/hunter-pets (Forever client data)
- wowhead.com/classic/hunter-pets (Era)
- Petopia forever family pages for Fox / Core Hound (reachable via search cache): both **Meat**

| Family | Diet | Era | Forever |
|---|---|---|---|
| Bat | Fungus, Fruit | ✓ | ✓ |
| Bear | Meat, Fish, Cheese, Bread, Fungus, Fruit | ✓ | ✓ |
| Bird of Prey | Meat | as **Owl** | ✓ |
| Boar | Meat, Fish, Cheese, Bread, Fungus, Fruit | ✓ | ✓ |
| Carrion Bird | Meat, Fish | ✓ | ✓ |
| Cat | Meat, Fish | ✓ | ✓ |
| Core Hound | Meat | – | ✓ (no tameable found yet) |
| Crab | Fish, Bread, Fungus, Fruit | ✓ | ✓ |
| Crocolisk | Meat, Fish | ✓ | ✓ |
| Fox | Meat | – | ✓ |
| Gorilla | Fungus, Fruit | ✓ | ✓ |
| Hyena | Meat, Fruit | ✓ | ✓ |
| Raptor | Meat | ✓ | ✓ |
| Scorpid | Meat | ✓ | ✓ |
| Spider | Meat | ✓ | ✓ |
| Tallstrider | Cheese, Fungus, Fruit | ✓ | ✓ |
| Turtle | Fish, Fungus, Fruit, Raw Fish | ✓ | ✓ |
| Wind Serpent | Fish, Cheese, Bread | ✓ | ✓ |
| Wolf | Meat | ✓ | ✓ |

Conclusion: **the diet table is flavour-agnostic**; what differs per flavour is
(a) which families exist and (b) the Owl / Bird of Prey name. That is what goes into the Client files.

## Design

### 1. Shared diet table — `Client/Client.lua`

Per PROJECT_STRUCTURE *"shared logic identical across flavours belongs in Client.lua"*.

```lua
-- Canonical (Forever) family name -> ordered list of food-type names, as the game's Beast Lore lists them.
Client.FAMILY_DIET_BY_CANONICAL_FAMILY = {
  ["Bat"] = { "Fungus", "Fruit" },
  ["Bird of Prey"] = { "Meat" },
  ...
}
```

### 2. Client interface additions — `Client.INTERFACE`

| Method | Returns | Forever | Era |
|---|---|---|---|
| `CanonicalFamilyName(familyName)` | the Forever-style name used as the key in data files | identity | `"Owl"` → `"Bird of Prey"`, else identity |
| `DisplayFamilyName(canonicalFamilyName)` | what to show the player on this client | identity | `"Bird of Prey"` → `"Owl"`, else identity |
| `FamilyExists(canonicalFamilyName)` | boolean — is this family tameable on this client | all 19 | 17 (no Fox, no Core Hound) |
| `FamilyDiet(familyName)` | list of food names, or `nil` if unknown | shared table via `CanonicalFamilyName` | same |

`FamilyDiet` is implemented once in `Client.lua` as a common helper that both flavour tables reference
(`impl.FamilyDiet = Client.CommonFamilyDiet`), so the per-flavour files only hold the name maps and family sets.
`Client_Select.lua` already warns on missing / extra methods — no change needed there.

`UnitCreatureFamily("pet")` returns the *display* name on each client ("Owl" on Era), so `ns.PetFamily()`
in `Core.lua` should run through `Client.CanonicalFamilyName` so existing `fam` comparisons against
`Data.lua` ("Bird of Prey") keep working on Era. This is a latent Era bug fixed as a side effect; one line.

### 3. Alert — `Alerts.lua` `Alert()`

- Family comes from the teacher entry already in hand: `list[1].t.family` (every entry for one beast shares a family).
- Build `dietLine = ("Eats: |cffffffff%s|r"):format(table.concat(diet, ", "))` when `diet` is non-nil; omit the line when unknown (never print "Eats: ?").
- Banner: `RaidNotice_AddMessage(RaidWarningFrame, msg .. "\n" .. dietLine, …)` — `RaidWarningFrame` is a `MessageFrame`, newlines render as separate lines.
- Chat: `ns.Say(msg)` then `ns.Say(dietLine)` (two lines, per user choice).
- Both guarded by `if dietLine then`.

### 4. Tooltip — `Alerts.lua` `AddTeachLines()`

- After the `Teaches …` lines and before the RareScanner line: `tt:AddLine("Eats: " .. foods, 0.8, 0.8, 0.8)`.
- Only when at least one `tame it!` line was shown? **No** — show it whenever the beast is a known teacher; diet is useful either way. Cheap, one line.

### 5. Tests — `tests/run.lua`

- Every family in the existing `FAMILIES` list has a diet entry (`Client.FamilyDiet(f) ~= nil` and non-empty).
- Every `t.family` in `ns.abilities[*].ranks[*].teachers` and every `p.family` in `ns.rarePets` resolves to a diet.
- Era flavour: `CanonicalFamilyName("Owl") == "Bird of Prey"`, `FamilyExists("Fox") == false`.
- Forever flavour: identity maps, `FamilyExists("Fox") == true`.
- Harness (`tests/harness.lua`) must expose a way to force the flavour — check how it sets `WOW_PROJECT_ID` today.

### 6. README

- Alerts section: mention the diet line. Usage table row "Tame a beast…" unchanged.

## Files touched

| File | Change |
|---|---|
| `Client/Client.lua` | `FAMILY_DIET_BY_CANONICAL_FAMILY`, `CommonFamilyDiet`, 4 new INTERFACE names |
| `Client/Client_Forever.lua` | identity name maps, 19-family set |
| `Client/Client_ClassicEra.lua` | Owl↔Bird of Prey maps, 17-family set |
| `Core.lua` | `ns.PetFamily()` → canonical |
| `Alerts.lua` | alert second line (banner + chat), tooltip `Eats:` line |
| `tests/run.lua` (+ harness if needed) | coverage above |
| `README.md` | one sentence |

## Open questions

- [ ] Food name wording: use Beast Lore's nouns ("Meat, Fish") as above, or the plural "Fungi"? → **Beast Lore nouns** unless told otherwise.
- [ ] Turtle's "Raw Fish": keep as the client data lists it (it is a distinct food type in-game). → **keep**.
- [ ] Should `DisplayFamilyName` also be applied to the Abilities / Hunt / Special Pets tabs on Era so "Owl" shows instead of "Bird of Prey"? Out of scope here; note for a follow-up.
