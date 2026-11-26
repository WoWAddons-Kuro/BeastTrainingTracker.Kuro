-- Unit tests for Beast Training Tracker's logic. Run from the addon folder:
--   lua5.1 tests/run.lua
-- Not shipped to CurseForge (.pkgmeta ignores tests/).
package.path = "./tests/?.lua;" .. package.path
local H = require("harness")
local out = io.write

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function fail(msg, level) error(msg, (level or 1) + 1) end
local function ok(v, msg) if not v then fail(msg or "expected a true value", 2) end end
local function eq(actual, expected, msg)
  if actual ~= expected then
    fail(("%sexpected %s, got %s"):format(msg and (msg .. ": ") or "", tostring(expected), tostring(actual)), 2)
  end
end
local function has(s, sub, msg)
  if type(s) ~= "string" or not s:find(sub, 1, true) then
    fail(("%sexpected %q to contain %q"):format(msg and (msg .. ": ") or "", tostring(s), sub), 2)
  end
end

------------------------------------------------------------------------
-- Data integrity
------------------------------------------------------------------------
test("ability data: ranks are 1..n with non-decreasing pet levels", function()
  local ns = H.load()
  ok(#ns.abilities > 0, "no abilities loaded")
  for _, ab in ipairs(ns.abilities) do
    ok(#ab.parsed > 0, ab.name .. " has no ranks")
    for i, r in ipairs(ab.parsed) do
      eq(r.rank, i, ab.name .. " rank order")
      ok(type(r.level) == "number" and type(r.tp) == "number", ab.name .. " rank " .. i .. " numbers")
      if i > 1 then ok(r.level >= ab.parsed[i - 1].level, ab.name .. " rank " .. i .. " level goes down") end
      for _, t in ipairs(r.teachers) do
        ok(t.name ~= "" and t.family ~= "" and t.zone ~= "", ab.name .. " has a teacher with missing fields")
      end
    end
  end
end)

local FAMILIES = {}
for _, f in ipairs({ "Bat", "Bear", "Bird of Prey", "Boar", "Carrion Bird", "Cat", "Core Hound", "Crab", "Crocolisk",
  "Fox", "Gorilla", "Hyena", "Raptor", "Scorpid", "Spider", "Tallstrider", "Turtle", "Wind Serpent", "Wolf" }) do
  FAMILIES[f] = true
end

test("special pets data: unique names, known families, sane speeds and flags", function()
  local ns = H.load()
  local seen = {}
  ok(#ns.rarePets > 0, "no special pets loaded")
  for _, p in ipairs(ns.rarePets) do
    ok(not seen[p.name], "duplicate special pet " .. p.name)
    seen[p.name] = true
    ok(FAMILIES[p.family], p.name .. " has unknown family " .. tostring(p.family))
    ok(p.minLevel > 0, p.name .. " has no level")
    ok(p.speed == nil or (p.speed >= 0.5 and p.speed <= 3.0), p.name .. " has odd speed")
    ok(p.rare or p.elite or p.spawned, p.name .. " isn't rare, elite or spawned")
    eq(ns.rarePetByName[p.name], p, p.name .. " lookup")
  end
  ok(seen["The Rake"] and seen["Vulgara the Insatiable"], "expected The Rake and Vulgara in the list")
end)

test("rare ids are numbers for known beasts", function()
  local ns = H.load()
  local n = 0
  for name, id in pairs(ns.rareIds) do
    n = n + 1
    ok(type(id) == "number" and id > 0, name .. " id")
    ok(ns.rarePetByName[name] or ns.teacherIndex[name], name .. " isn't a known pet or teacher")
  end
  ok(n > 0, "no rare ids")
end)

------------------------------------------------------------------------
-- Client: pet families and diets per flavour
------------------------------------------------------------------------
test("diet: every family in the data files has a diet on Forever", function()
  local ns = H.load()
  eq(ns.Client.flavour, "forever")
  for f in pairs(FAMILIES) do
    local d = ns.Client.FamilyDiet(f)
    ok(d and #d > 0, f .. " has no diet")
    ok(ns.Client.FamilyExists(f), f .. " should exist on Forever")
  end
  for _, ab in ipairs(ns.abilities) do
    for _, r in ipairs(ab.parsed) do
      for _, t in ipairs(r.teachers) do
        ok(ns.Client.FamilyDiet(t.family), ("%s (%s) has no diet"):format(t.name, t.family))
      end
    end
  end
  for _, p in ipairs(ns.rarePets) do
    ok(ns.Client.FamilyDiet(p.family), ("%s (%s) has no diet"):format(p.name, p.family))
  end
  eq(ns.Client.FamilyDiet("Not A Family"), nil)
  eq(ns.Client.FamilyDiet(nil), nil)
end)

test("diet: known values and a fresh copy each call", function()
  local ns = H.load()
  eq(table.concat(ns.Client.FamilyDiet("Wolf"), ", "), "Meat")
  eq(table.concat(ns.Client.FamilyDiet("Cat"), ", "), "Meat, Fish")
  eq(table.concat(ns.Client.FamilyDiet("Turtle"), ", "), "Fish, Fungus, Fruit, Raw Fish")
  eq(table.concat(ns.Client.FamilyDiet("Bear"), ", "), "Meat, Fish, Cheese, Bread, Fungus, Fruit")
  local a = ns.Client.FamilyDiet("Wolf")
  a[1] = "Rocks"
  eq(ns.Client.FamilyDiet("Wolf")[1], "Meat", "caller mutated the shared table")
end)

test("diet: Forever family names are the identity", function()
  local ns = H.load()
  eq(ns.Client.CanonicalFamilyName("Bird of Prey"), "Bird of Prey")
  eq(ns.Client.DisplayFamilyName("Bird of Prey"), "Bird of Prey")
  eq(ns.Client.FamilyExists("Fox"), true)
  eq(ns.Client.FamilyExists("Core Hound"), true)
end)

test("diet: Classic Era maps Owl to Bird of Prey and has no Fox / Core Hound", function()
  local ns = H.load({ flavour = "classic_era" })
  eq(ns.Client.flavour, "classic_era")
  eq(ns.Client.CanonicalFamilyName("Owl"), "Bird of Prey")
  eq(ns.Client.CanonicalFamilyName("Wolf"), "Wolf")
  eq(ns.Client.DisplayFamilyName("Bird of Prey"), "Owl")
  eq(ns.Client.DisplayFamilyName("Wolf"), "Wolf")
  eq(ns.Client.FamilyExists("Fox"), false)
  eq(ns.Client.FamilyExists("Core Hound"), false)
  eq(ns.Client.FamilyExists("Bird of Prey"), true)
  -- diet works through either name
  eq(table.concat(ns.Client.FamilyDiet("Owl"), ", "), "Meat")
  eq(table.concat(ns.Client.FamilyDiet("Bird of Prey"), ", "), "Meat")
  -- and the pet's family is canonical so data-file comparisons work
  H.state.pet = { name = "Hoot", family = "Owl", level = 20, guid = "Pet-0-7", spells = {} }
  eq(ns.PetFamily(), "Bird of Prey")
  ok(ns.AbilityFitsPet(ns.byName.Claw, ns.PetFamily()), "Era owl should be able to use Claw")
end)

------------------------------------------------------------------------
-- Saved data
------------------------------------------------------------------------
test("fresh install creates empty saved data with defaults", function()
  local ns = H.load()
  ok(ns.db, "db missing")
  eq(next(ns.db.known), nil, "known should start empty")
  eq(ns.db.opts.hideKnown, false, "hideKnown default")
  eq(ns.db.opts.learnToast, true, "learnToast default")
  ok(type(ns.db.tamedRares) == "table", "tamedRares table")
end)

test("a higher rank implies the lower ones", function()
  local ns = H.load()
  local bite = ns.byName.Bite
  ns.db.known["Bite#3"] = true
  eq(ns.Status(bite, 3), "known")
  eq(ns.Status(bite, 1), "implied")
  eq(ns.Status(bite, 2), "implied")
  eq(ns.Status(bite, 4), nil)
  eq(ns.BestKnown(bite), 3)
end)

test("backup restores learned ranks and tamed pets if saved data is lost", function()
  local ns = H.load()
  ns.db.known["Bite#1"] = true
  ns.db.tamedRares["The Rake"] = 123
  ns.db.tamedNicks["The Rake"] = "Kittery"
  H.fire("PLAYER_LOGOUT")
  local backup = H.deepcopy(BeastTrainingTrackerKuroBackup)

  local ns2 = H.load({ backup = backup }) -- per-character data gone, backup kept
  ok(ns2.db.known["Bite#1"], "rank not restored")
  eq(ns2.db.tamedRares["The Rake"], 123, "tamed pet not restored")
  eq(ns2.db.tamedNicks["The Rake"], "Kittery", "nickname not restored")
end)

test("reset wipes learned ranks but keeps the tamed collection", function()
  local ns = H.load()
  ns.db.known["Bite#1"] = true
  ns.db.tamedRares["The Rake"] = 1
  ns.ResetData()
  eq(next(ns.db.known), nil, "known not wiped")
  eq(ns.db.tamedRares["The Rake"], 1, "tamed pets should survive a reset")
end)

------------------------------------------------------------------------
-- Detection
------------------------------------------------------------------------
test("'You have learned' chat messages record the rank", function()
  local ns = H.load()
  H.fire("CHAT_MSG_SYSTEM", "You have learned a new ability: Claw (Rank 2).")
  ok(ns.db.known["Claw#2"], "Claw 2 not recorded")
  H.fire("CHAT_MSG_SYSTEM", "You have learned a new spell: Dash (Rank 1).")
  ok(ns.db.known["Dash#1"], "Dash 1 not recorded")
  H.fire("CHAT_MSG_SYSTEM", "You have learned a new spell: Fireball (Rank 1).")
  ok(not ns.db.known["Fireball#1"], "non-pet spell recorded")
end)

test("spell-link 'You have learned' message takes the rank from the pet", function()
  local ns = H.load()
  H.state.pet = { name = "Bruin", family = "Bear", level = 30, guid = "Pet-0-2",
    spells = { { "Swipe", "Rank 3" }, { "Bite", "Rank 4" } } }
  ns.RefreshNow()
  ok(not ns.db.known["Swipe#3"], "taming alone should not count as learned")
  H.fire("CHAT_MSG_SYSTEM", "You have learned a new spell: |cff71d5ff|Hspell:16829:0|h[Swipe]|h|r.")
  ok(ns.db.known["Swipe#3"], "Swipe 3 not recorded from spell link")
end)

test("Beast Training scan reads ranks in this server's field order", function()
  local ns = H.load()
  -- name, type, icon, reqLevel, rank (as seen in game with /bttk debug)
  H.state.trainer = {
    { "Bite", "used", 132278, 8, "Rank 2" },
    { "Bite", "used", 132278, 16, "Rank 3" },
    { "Growl", "used", 132270, 10, "Rank 2" },
  }
  H.fire("TRAINER_SHOW")
  ok(ns.db.known["Bite#2"] and ns.db.known["Bite#3"], "Bite ranks not read")
  ok(ns.db.known["Growl#2"], "Growl 2 not read")
end)

test("Beast Training scan adds ranks and never removes saved ones", function()
  local ns = H.load()
  ns.db.known["Bite#1"] = true
  H.state.trainer = {
    { "Pet Abilities", "", "header" },
    { "Claw", "Rank 1", "available" },
    { "Growl", "Rank 2", "used" },
  }
  H.fire("TRAINER_SHOW")
  ok(ns.db.known["Claw#1"], "Claw 1 not saved")
  ok(ns.db.known["Growl#2"], "Growl 2 not saved")
  ok(ns.db.known["Bite#1"], "existing rank was removed")
  ok(ns.db.lastSync, "lastSync not set")

  H.state.trainer = {} -- window shows nothing (filters, etc.)
  H.fire("TRAINER_UPDATE")
  ok(ns.db.known["Claw#1"] and ns.db.known["Bite#1"], "an empty list wiped saved ranks")
end)

test("pet spellbook ranks are not learned until the pet teaches them", function()
  local ns = H.load()
  H.state.pet = { name = "Fang", family = "Wolf", level = 20, guid = "Pet-0-1",
    spells = { { "Bite", "Rank 2" }, { "Growl", "Rank 1" }, { "Attack", "" } } }
  ns.RefreshNow()
  ok(not ns.db.known["Bite#2"] and not ns.db.known["Growl#1"], "freshly tamed pet's ranks were saved as learned")
  eq(ns.petRank.Bite, 2)
  ok(ns.petHas["Bite#2"], "petHas")
end)

------------------------------------------------------------------------
-- Planning
------------------------------------------------------------------------
test("upgrades: teachable now vs pet needs a level", function()
  local ns = H.load()
  local bite = ns.byName.Bite
  ok(bite.parsed[5].level > bite.parsed[4].level, "test needs Bite 5 to need a higher level than Bite 4")
  H.state.pet = { name = "Fang", family = "Wolf", level = bite.parsed[4].level, guid = "Pet-0-1",
    spells = { { "Bite", "Rank 3" } } }

  ns.db.known["Bite#4"] = true
  ns.RefreshNow()
  local up
  for _, u in ipairs(ns.Upgrades()) do if u.ab.name == "Bite" then up = u end end
  ok(up, "no Bite upgrade")
  eq(up.from, 3) eq(up.to, 4) eq(up.needLevel, nil)

  wipe(ns.db.known)
  ns.db.known["Bite#5"] = true
  ns.RefreshNow()
  up = nil
  for _, u in ipairs(ns.Upgrades()) do if u.ab.name == "Bite" then up = u end end
  ok(up, "no Bite entry when only a too-high rank is known")
  eq(up.to, 5) eq(up.needLevel, bite.parsed[5].level)
end)

test("hunt plan: only tameable, non-dungeon, highest missing rank per ability", function()
  local ns = H.load()
  H.state.level = 12
  local plan = ns.HuntPlan(false, false, "count")
  ok(#plan > 0, "empty hunt plan at level 12")
  for i, z in ipairs(plan) do
    if i > 1 then ok(#plan[i - 1].entries >= #z.entries, "zones not sorted by count") end
    local seenAb = {}
    for _, e in ipairs(z.entries) do
      ok(not seenAb[e.ab.name], e.ab.name .. " listed twice in " .. z.zone)
      seenAb[e.ab.name] = true
      ok(not ns.IsKnown(e.ab, e.rank.rank), "known rank in plan")
      for _, t in ipairs(e.teachers) do
        ok(t.minLevel <= 12, t.name .. " is above level 12")
        ok(not t.dungeon, t.name .. " is in a dungeon")
        eq(t.zone, z.zone, "teacher zone")
      end
      -- no higher missing rank of this ability is tameable in the same zone
      for _, r in ipairs(e.ab.parsed) do
        if r.rank > e.rank.rank and not ns.IsKnown(e.ab, r.rank) then
          for _, t in ipairs(r.teachers) do
            ok(not (t.zone == z.zone and t.minLevel <= 12 and not t.dungeon),
              ("%s %d listed but %d is also tameable in %s"):format(e.ab.name, e.rank.rank, r.rank, z.zone))
          end
        end
      end
    end
  end

  for _, r in ipairs(ns.byName.Bite.parsed) do ns.db.known["Bite#" .. r.rank] = true end
  for _, z in ipairs(ns.HuntPlan(false, false)) do
    for _, e in ipairs(z.entries) do ok(e.ab.name ~= "Bite", "learned ability still in the plan") end
  end
end)

test("zone levels: known Classic ranges, subzones, and Forever zones from beast levels", function()
  local ns = H.load()
  local lo, hi = ns.ZoneLevels("Silverpine Forest")
  eq(lo, 10) eq(hi, 20)
  lo, hi = ns.ZoneLevels("The Tundrid Hills, Dun Morogh")
  eq(lo, 1) eq(hi, 10)
  lo, hi = ns.ZoneLevels("Zephras Isle")
  ok(lo > 0 and hi >= lo, "Zephras Isle range should come from its beasts")
  lo, hi = ns.ZoneLevels("Razorfen Kraul (Dungeon)")
  ok(lo > 0 and hi >= lo, "dungeon range should come from its beasts")
end)

test("hunt plan: lowest level zones first by default", function()
  local ns = H.load()
  H.state.level = 30
  local plan = ns.HuntPlan(false, false)
  ok(#plan > 1, "need at least two zones")
  for i = 2, #plan do
    ok(plan[i - 1].minLevel <= plan[i].minLevel, ("%s (%d) listed before %s (%d)"):format(
      plan[i - 1].zone, plan[i - 1].minLevel, plan[i].zone, plan[i].minLevel))
  end
end)

local function PlanHas(plan, zone)
  for _, z in ipairs(plan) do
    if z.zone:find(zone, 1, true) then return true end
  end
  return false
end

test("hunt plan: the other faction's zones are hidden unless turned on", function()
  local ns = H.load() -- Horde
  H.state.level = 12
  ok(not PlanHas(ns.HuntPlan(false, false), "Elwynn Forest"), "Horde sees Elwynn Forest")
  ok(PlanHas(ns.HuntPlan(false, false), "Durotar"), "Horde should see Durotar")
  ns.db.opts.huntBothFactions = true
  ok(PlanHas(ns.HuntPlan(false, false), "Elwynn Forest"), "option should show Alliance zones")

  local ns2 = H.load()
  H.state.faction, H.state.level = "Alliance", 12
  ok(not PlanHas(ns2.HuntPlan(false, false), "Durotar"), "Alliance sees Durotar")
  ok(PlanHas(ns2.HuntPlan(false, false), "Elwynn Forest"), "Alliance should see Elwynn Forest")
  eq(ns2.ZoneHostile("Durotar"), true)
  eq(ns2.ZoneHostile("Stranglethorn Vale"), false, "contested zones are never hostile")
end)

test("zone tracker still lists beasts in an enemy zone you're standing in", function()
  local ns = H.load() -- Horde
  H.state.level, H.state.zone = 12, "Elwynn Forest"
  local entries = ns.NeededHere()
  ok(#entries > 0, "nothing listed in Elwynn Forest for a Horde player standing there")
end)

test("needed-here only lists the current zone", function()
  local ns = H.load()
  H.state.level, H.state.zone = 12, "Mulgore"
  local entries, zone = ns.NeededHere()
  ok(zone:find("Mulgore", 1, true), "zone name")
  for _, e in ipairs(entries) do
    for _, t in ipairs(e.teachers) do has(t.zone, "Mulgore", "teacher zone") end
  end
end)

------------------------------------------------------------------------
-- Export / import
------------------------------------------------------------------------
test("export and import round trip, including tamed pets", function()
  local ns = H.load()
  ns.db.known["Bite#1"], ns.db.known["Bite#2"], ns.db.known["Claw#3"] = true, true, true
  ns.db.tamedRares["The Rake"] = 1
  ns.db.tamedNicks["The Rake"] = "Kittery"
  local s = ns.Export()
  ok(s:find("^BTT1:"), "export prefix")
  has(s, "Bite=1,2")
  has(s, "Claw=3")
  has(s, "#T:The Rake>Kittery")

  local ns2 = H.load()
  local added, skipped, tamed = ns2.Import(s)
  eq(added, 3, "ranks added") eq(skipped, 0, "skipped") eq(tamed, 1, "tamed added")
  ok(ns2.db.known["Bite#2"] and ns2.db.known["Claw#3"], "ranks imported")
  ok(ns2.db.tamedRares["The Rake"], "tamed pet imported")
  eq(ns2.db.petLinks["Kittery|Cat"], "The Rake", "nickname link imported")
end)

test("import merges, skips junk and rejects non-exports", function()
  local ns = H.load()
  ns.db.known["Dash#1"] = true
  local added = ns.Import("BTT1:Bite=1")
  eq(added, 1)
  ok(ns.db.known["Dash#1"], "import removed an existing rank")

  local a, msg = ns.Import("hello there")
  eq(a, nil, "junk accepted")
  ok(type(msg) == "string", "no error message")

  local a2, skipped = ns.Import("BTT1:Nope=1;Bite=99")
  eq(a2, 0) eq(skipped, 2)
end)

test("old exports without a tamed section still import", function()
  local ns = H.load()
  local added, skipped, tamed = ns.Import("BTT1:Bite=1,2;Claw=1")
  eq(added, 3) eq(skipped, 0) eq(tamed, 0)
end)

------------------------------------------------------------------------
-- Special pets
------------------------------------------------------------------------
test("renamed pet is recognised after right-click linking, and unlinking clears it", function()
  local ns = H.load()
  H.state.pet = { name = "Kittery", family = "Cat", level = 28, guid = "Pet-0-6821-1-40-165189-37E2154097", spells = {} }
  eq(ns.RS.RareFromPet(), nil, "unlinked pet matched")
  ns.RS.SetTamed("The Rake", true)
  ok(ns.db.tamedRares["The Rake"], "not marked tamed")
  eq(ns.db.tamedNicks["The Rake"], "Kittery")
  eq(ns.RS.RareFromPet(), "The Rake")
  ns.RS.SetTamed("The Rake", false)
  eq(ns.db.tamedRares["The Rake"], nil, "still tamed")
  eq(ns.RS.RareFromPet(), nil, "link not cleared")
end)

test("right-click doesn't link a pet of a different family", function()
  local ns = H.load()
  H.state.pet = { name = "Fang", family = "Wolf", level = 28, guid = "Pet-0-9", spells = {} }
  ns.RS.SetTamed("The Rake", true)
  ok(ns.db.tamedRares["The Rake"], "should still mark tamed")
  eq(ns.RS.RareFromPet(), nil, "wolf linked to a cat rare")
end)

test("taming a special pet marks it, and a rename keeps the link", function()
  local ns = H.load()
  H.fire("UNIT_SPELLCAST_SENT", "player", "The Rake", "cast-1", 1515)
  H.state.pet = { name = "The Rake", family = "Cat", level = 10, guid = "Pet-0-NEW", spells = {} }
  H.fire("UNIT_PET", "player")
  ok(ns.db.tamedRares["The Rake"], "tame not detected")

  H.state.pet.name = "Kittery"
  H.fire("UNIT_NAME_UPDATE", "pet")
  eq(ns.db.tamedNicks["The Rake"], "Kittery", "rename not tracked")
  eq(ns.db.petLinks["Kittery|Cat"], "The Rake", "renamed link missing")
  eq(ns.RS.RareFromPet(), "The Rake")
end)

test("special pet info: speed, type and traits", function()
  local ns = H.load()
  local rake = ns.RS.Info("The Rake")
  eq(rake.speed, 1.2) eq(rake.t.family, "Cat")
  has(ns.RS.TypeText(rake.t), "Rare")
  local v = ns.RS.Info("Vulgara the Insatiable")
  ok(v.t.elite and v.t.unique, "Vulgara should be elite with a unique look")
  has(ns.RS.TypeText(v.t), "Elite")
  eq(ns.RS.Info("Not A Pet"), nil)
end)

test("time and speed formatting", function()
  local ns = H.load()
  eq(ns.RS.Ago(30), "30s")
  eq(ns.RS.Ago(90), "1m")
  eq(ns.RS.Ago(3660), "1h 1m")
  eq(ns.RS.Ago(2 * 86400), "2d")
  has(ns.RS.SpeedText(nil), "?")
  has(ns.RS.SpeedText(1.2), "1.2")
  has(ns.RS.SpeedText(2.5), "2.5")
end)

test("RareScanner missing: no timers, no errors", function()
  local ns = H.load()
  eq(ns.RS.Loaded(), false)
  eq(ns.RS.Status("The Rake"), nil)
  ok(ns.RS.Get("The Rake") and ns.RS.Get("The Rake").id, "rare id should come from RareIds.lua")
end)

------------------------------------------------------------------------
-- Standalone: no Questie / TomTom / RareScanner
------------------------------------------------------------------------
test("standalone: optional addons all report 'not detected'", function()
  local ns = H.load()
  local st = ns.Geo.AddonStatus()
  eq(#st, 3)
  for _, a in ipairs(st) do
    eq(a.on, false, a.name .. " should be missing")
    has(a.text, "Not detected", a.name .. " text")
  end
end)

test("standalone: spotting a teacher records its location", function()
  local ns = H.load()
  H.setPosition(1412, 0.5, 0.6)
  H.state.units.target = { name = "Prairie Wolf" }
  H.fire("PLAYER_TARGET_CHANGED")
  local spots = BeastTrainingTrackerKuroSeen["Prairie Wolf"]
  ok(spots and #spots == 1, "sighting not saved")
  eq(spots[1][1], 1412) eq(spots[1][2], 0.5) eq(spots[1][3], 0.6)

  local info = ns.Geo.Lookup("Prairie Wolf")
  ok(info and #info.spawns == 1, "lookup didn't use the sighting")
  eq(info.spawns[1].src, "seen")
  eq(ns.Geo.SeenCount(), 1)
end)

test("standalone: untracked mobs and players aren't recorded", function()
  H.load()
  H.setPosition(1412, 0.5, 0.6)
  H.state.units.target = { name = "Kobold Vermin" }
  H.fire("PLAYER_TARGET_CHANGED")
  eq(BeastTrainingTrackerKuroSeen["Kobold Vermin"], nil, "random mob recorded")
end)

test("standalone: sightings are account-wide and survive a reload", function()
  local ns = H.load()
  H.setPosition(1412, 0.25, 0.75)
  H.state.units.mouseover = { name = "The Rake" }
  H.fire("UPDATE_MOUSEOVER_UNIT")
  local seen = H.deepcopy(BeastTrainingTrackerKuroSeen)
  local ns2 = H.load({ seen = seen })
  local info = ns2.Geo.Lookup("The Rake")
  ok(info and info.spawns[1] and info.spawns[1].x == 0.25, "sighting lost after reload")
end)

test("standalone: waypoint without TomTom uses the built-in marker", function()
  local ns = H.load()
  H.setPosition(1412, 0.5, 0.6)
  H.state.units.target = { name = "Prairie Wolf" }
  H.fire("PLAYER_TARGET_CHANGED")
  local res = ns.Geo.Waypoint({ name = "Prairie Wolf", zone = "Mulgore" }, "Prairie Wolf - Bite 1")
  ok(res, "no waypoint set")
  ok(H.said("waypoint set: Prairie Wolf - Bite 1"), "no confirmation message")
  ok(H.said("minimap edge"), "should point to the minimap marker")
end)

test("standalone: unknown location explains how to get one", function()
  local ns = H.load()
  local s, _, why = ns.Geo.Destination({ name = "Prairie Wolf", zone = "Mulgore" })
  eq(s, nil)
  has(why, "Mulgore")
  has(why, "Questie")
  ok(not ns.Geo.Waypoint({ name = "Prairie Wolf", zone = "Mulgore" }), "waypoint set with no location")
end)

test("with TomTom: waypoints go to TomTom", function()
  local ns = H.load()
  local added = {}
  TomTom = { AddWaypoint = function(_, m, x, y, o) added[#added + 1] = { m, x, y, o.title } return { id = #added } end,
    RemoveWaypoint = function() end }
  H.setPosition(1412, 0.5, 0.6)
  H.state.units.target = { name = "Prairie Wolf" }
  H.fire("PLAYER_TARGET_CHANGED")
  ok(ns.Geo.Waypoint({ name = "Prairie Wolf", zone = "Mulgore" }, "Wolf"), "no waypoint")
  eq(#added, 1, "TomTom not used")
  eq(added[1][1], 1412)
  local st = ns.Geo.AddonStatus()
  eq(st[2].name, "TomTom") eq(st[2].on, true)
  TomTom = nil
end)

------------------------------------------------------------------------
-- Hunt routes
------------------------------------------------------------------------
-- spot a beast at a position (records a sighting there)
local function spot(name, map, x, y)
  H.setPosition(map, x, y)
  H.state.units.target = { name = name }
  H.fire("PLAYER_TARGET_CHANGED")
end

test("route: stops are ordered nearest-first from the player", function()
  local ns = H.load()
  H.setPosition(1412, 0.1, 0.1)
  local out = ns.Geo.OrderStops({
    { map = 1412, x = 0.9, y = 0.9, label = "far" },
    { map = 1413, x = 0.1, y = 0.1, label = "other map" },
    { map = 1412, x = 0.2, y = 0.2, label = "near" },
    { map = 1412, x = 0.5, y = 0.5, label = "middle" },
  })
  eq(out[1].label, "near") eq(out[2].label, "middle") eq(out[3].label, "far") eq(out[4].label, "other map")
end)

test("route: clicking beasts adds stops, Hunt Planner starts a new route, clear empties it", function()
  local ns = H.load()
  spot("Prairie Wolf", 1412, 0.3, 0.3)
  spot("The Rake", 1412, 0.6, 0.6)
  spot("Ghostfang", 1426, 0.5, 0.5)
  H.setPosition(1412, 0.1, 0.1)

  ok(ns.Geo.Waypoint({ name = "The Rake", zone = "Mulgore" }, "Rake"), "first stop")
  ok(ns.Geo.Waypoint({ name = "Prairie Wolf", zone = "Mulgore" }, "Wolf"), "second stop")
  eq(#ns.Geo.route, 2, "clicks should add stops")
  eq(ns.Geo.route[1].label, "Wolf", "nearest stop should come first")
  eq(ns.Geo.current, 1)
  ok(H.said("route now has 2 stops"), "no route message")

  ns.Geo.Waypoint({ name = "Prairie Wolf", zone = "Mulgore" }, "Wolf again")
  eq(#ns.Geo.route, 2, "the same spot was added twice")

  local n = ns.Geo.WaypointMany({
    { t = { name = "Ghostfang", zone = "Dun Morogh" }, label = "Ghostfang" },
    { t = { name = "The Rake", zone = "Mulgore" }, label = "Rake" },
    { t = { name = "Nobody Known", zone = "Nowhere" }, label = "?" },
  })
  eq(n, 2, "new route should only have the two known beasts")
  eq(#ns.Geo.route, 2)
  eq(ns.Geo.route[1].label, "Rake", "same-map stop first")

  ns.Geo.ClearWaypoints()
  eq(#ns.Geo.route, 0) eq(ns.Geo.current, 0)
  ok(H.said("cleared 2 waypoints"), "no clear message")
end)

test("route: removing a stop keeps the rest", function()
  local ns = H.load()
  spot("Prairie Wolf", 1412, 0.3, 0.3)
  spot("The Rake", 1412, 0.6, 0.6)
  H.setPosition(1412, 0.1, 0.1)
  ns.Geo.WaypointMany({
    { t = { name = "Prairie Wolf", zone = "Mulgore" }, label = "Wolf" },
    { t = { name = "The Rake", zone = "Mulgore" }, label = "Rake" },
  })
  ns.Geo.RemoveStop(ns.Geo.route[1])
  eq(#ns.Geo.route, 1) eq(ns.Geo.route[1].label, "Rake") eq(ns.Geo.current, 1)
  ns.Geo.RemoveStop(ns.Geo.route[1])
  eq(#ns.Geo.route, 0, "removing the last stop should clear the route")
end)

test("route: dotted line color has a visible default and can be changed", function()
  local ns = H.load()
  local r, g, b, a = ns.Geo.RouteColor()
  eq(r, 0.1) eq(g, 0.85) eq(b, 1.0) eq(a, 0.9)
  ns.db.opts.routeColor = { r = 1, g = 0, b = 0 }
  ns.db.opts.routeAlpha = 0.5
  r, g, b, a = ns.Geo.RouteColor()
  eq(r, 1) eq(g, 0) eq(b, 0) eq(a, 0.5)
  ns.Geo.DrawRoute() -- no map library loaded: must not error
end)

-- two different beasts that each teach exactly one rank, the same one
local function SameRankPair(ns)
  for _, ab in ipairs(ns.abilities) do
    for _, r in ipairs(ab.parsed) do
      local solo = {}
      for _, t in ipairs(r.teachers) do
        local entries = ns.teacherIndex[t.name]
        if #entries == 1 and not ns.rarePetByName[t.name] and solo[#solo] ~= t.name then solo[#solo + 1] = t.name end
      end
      if #solo >= 2 then return ab, r, solo[1], solo[2] end
    end
  end
end

test("route: only one mob per ability, the nearest in route order", function()
  local ns = H.load()
  local ab, r, a, b = SameRankPair(ns)
  ok(a and b, "data has no two beasts teaching the same single rank")
  spot(a, 1412, 0.2, 0.2)
  spot(b, 1412, 0.8, 0.8)
  H.setPosition(1412, 0.1, 0.1)
  local n = ns.Geo.WaypointMany({
    { t = { name = b, zone = "?" }, label = b },
    { t = { name = a, zone = "?" }, label = a },
  })
  eq(n, 1, ("%s and %s both teach %s %d - only one stop expected"):format(a, b, ab.name, r.rank))
  eq(ns.Geo.route[1].label, a, "the nearer beast should be kept")

  -- clicking the other one by hand still adds it
  ns.Geo.Waypoint({ name = b, zone = "?" }, b)
  eq(#ns.Geo.route, 2, "clicked stops are always kept")
end)

test("route: learning a rank or taming a pet drops stops you no longer need", function()
  local ns = H.load()
  local ab, r, a = SameRankPair(ns)
  spot(a, 1412, 0.2, 0.2)
  spot("The Rake", 1412, 0.5, 0.5)
  H.setPosition(1412, 0.1, 0.1)
  ns.Geo.WaypointMany({
    { t = { name = a, zone = "?" }, label = a },
    { t = { name = "The Rake", zone = "Mulgore" }, label = "The Rake" },
  })
  eq(#ns.Geo.route, 2)

  H.fire("CHAT_MSG_SYSTEM", ("You have learned a new ability: %s (Rank %d)."):format(ab.name, r.rank))
  eq(#ns.Geo.route, 1, "teacher stop not removed after learning")
  eq(ns.Geo.route[1].label, "The Rake")
  ok(H.said("route updated"), "no route update message")

  ns.RS.SetTamed("The Rake", true)
  eq(#ns.Geo.route, 0, "pet stop not removed after taming")
  ok(H.said("hunt route complete"), "no completion message")
end)

test("route: plain stops are never pruned", function()
  local ns = H.load()
  local ab, r, a = SameRankPair(ns)
  ns.db.known[ns.Key(ab.name, r.rank)] = true -- already learned before clicking
  spot(a, 1412, 0.2, 0.2)
  ns.Geo.Waypoint({ name = a, zone = "?" }, a)
  H.fire("CHAT_MSG_SYSTEM", "You have learned a new ability: Dash (Rank 1).")
  eq(#ns.Geo.route, 1, "a stop with nothing left to learn was added on purpose and should stay")
end)

test("route: your own sightings never override real spawn data", function()
  local ns = H.load()
  ns.rsRares = { ["The Rake"] = { id = 5807, map = 1412, x = 0.9, y = 0.9, path = {} } }
  spot("The Rake", 1412, 0.1, 0.1) -- you saw its nameplate while standing at 0.1, 0.1
  local info = ns.Geo.Lookup("The Rake")
  eq(#info.spawns, 1, "sighting should be ignored when real data exists")
  eq(info.spawns[1].x, 0.9)
  local s = ns.Geo.Destination({ name = "The Rake", zone = "Mulgore" })
  eq(s.x, 0.9, "route went to where you were standing, not the spawn")
end)

test("route: beasts that can't be placed are named in chat", function()
  local ns = H.load()
  spot("Prairie Wolf", 1412, 0.3, 0.3)
  ns.Geo.WaypointMany({
    { t = { name = "Prairie Wolf", zone = "Mulgore" }, label = "Wolf" },
    { t = { name = "Mist Creeper", zone = "Silverpine Forest" }, label = "Mist Creeper - Web 1" },
  })
  eq(#ns.Geo.route, 1)
  ok(H.said("no location known for: Mist Creeper"), "missing beast not reported")
  ok(H.said("Questie isn't installed"), "no Questie warning on the route")
end)

test("/bttk where explains a beast's location sources, any capitalization", function()
  H.load()
  SlashCmdList.BEASTTRAININGTRACKERKURO("where prairie wolf")
  ok(H.said("locations for |cffffffffPrairie Wolf|r"), "name not matched case-insensitively")
  ok(H.said("Questie: not installed"), "Questie status missing")
  ok(H.said("used for pins/routes: nothing"), "summary missing")
end)

test("route: TomTom gets one waypoint per stop", function()
  local ns = H.load()
  local added, removed = 0, 0
  TomTom = { AddWaypoint = function() added = added + 1 return {} end, RemoveWaypoint = function() removed = removed + 1 end }
  spot("Prairie Wolf", 1412, 0.3, 0.3)
  spot("The Rake", 1412, 0.6, 0.6)
  ns.Geo.WaypointMany({
    { t = { name = "Prairie Wolf", zone = "Mulgore" }, label = "Wolf" },
    { t = { name = "The Rake", zone = "Mulgore" }, label = "Rake" },
  })
  eq(added, 2, "TomTom waypoints")
  ns.Geo.ClearWaypoints()
  eq(removed, 2, "TomTom waypoints not removed")
  TomTom = nil
end)

------------------------------------------------------------------------
-- Stable masters
------------------------------------------------------------------------
-- a fake QuestieDB: friendly to both, Horde only, a [DND] placeholder, a plain vendor, and an unmapped zone
local function StableDB()
  return H.setQuestieDB({
    [100] = { name = "Shoja'my",   flags = 8192 + 1, faction = "AH", spawns = { [1637] = { { 20, 30 } } } },
    [101] = { name = "Xon'cha",    flags = 8192,     faction = "H",  spawns = { [1637] = { { 60, 70 }, { 65, 72 } } } },
    [102] = { name = "[DND] Test", flags = 8192,     faction = "AH", spawns = { [1637] = { { 50, 50 } } } },
    [103] = { name = "Some Vendor", flags = 4,       faction = "AH", spawns = { [1637] = { { 10, 10 } } } },
    [104] = { name = "Unmapped",   flags = 8192,     faction = "AH", spawns = { [9999] = { { 10, 10 } } } },
  }, { [1637] = 1454 })
end

-- the scan runs in a coroutine driven by an OnUpdate frame: pump it
local function RunStableScan(ns)
  ns.Geo.ready = true
  ns.RefreshNow()
  for _ = 1, 50 do
    for _, f in ipairs(H.frames) do
      if f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.1) end
    end
    if ns.Stables.ready then break end
  end
end

test("client: both flavours implement the stable master methods", function()
  for _, flavour in ipairs({ "classic_era", "forever" }) do
    local ns = H.load({ flavour = flavour })
    ok(not H.said("client is missing"), flavour .. ": missing client method")
    ok(not H.said("not in Client.INTERFACE"), flavour .. ": extra client method")
    eq(ns.Client.PlayerFactionKey(), "H")
    eq(type(ns.Client.StableMasterMinimapPinsWanted()), "boolean")
  end
  local era = H.load({ flavour = "classic_era" })
  eq(era.Client.StableMasterMinimapPinsWanted(), true, "Era draws minimap pins")
  eq(era.Client.StableMasterNativeTrackingHint(), nil)
  local fv = H.load({ flavour = "forever" })
  eq(fv.Client.StableMasterMinimapPinsWanted(), false, "Forever relies on native tracking")
  has(fv.Client.StableMasterNativeTrackingHint(), "tracking")
end)

test("stables: without QuestieDB the feature reports itself absent", function()
  local ns = H.load()
  eq(ns.Stables.HasSource(), false)
  SlashCmdList.BEASTTRAININGTRACKERKURO("stable")
  ok(H.said("QuestieDB is not installed"), "no QuestieDB message")
  eq(#ns.Geo.route, 0)
end)

test("stables: scan keeps flag matches friendly to my faction, skips [DND] and unmapped zones", function()
  local ns = H.load()
  StableDB()
  RunStableScan(ns)
  ok(ns.Stables.ready, "scan did not finish: " .. tostring(ns.Stables.status))
  eq(ns.Stables.count, 2, "Horde should see Shoja'my and Xon'cha")
  eq(#ns.Stables.list, 3, "one entry per spawn point")
  for _, e in ipairs(ns.Stables.list) do
    eq(e.map, 1454)
    ok(e.name ~= "[DND] Test" and e.name ~= "Some Vendor" and e.name ~= "Unmapped", "kept " .. e.name)
  end
end)

test("stables: Alliance only sees AH stable masters", function()
  local ns = H.load()
  H.state.faction = "Alliance"
  StableDB()
  RunStableScan(ns)
  eq(ns.Stables.count, 1)
  eq(ns.Stables.list[1].name, "Shoja'my")
end)

test("stables: nearest picks the closest on my map and /bttk stable sets a manual waypoint", function()
  local ns = H.load()
  StableDB()
  RunStableScan(ns)
  H.setPosition(1454, 0.62, 0.71)
  local e = ns.Stables.Nearest()
  eq(e.name, "Xon'cha")
  eq(e.x, 0.6)
  SlashCmdList.BEASTTRAININGTRACKERKURO("stable")
  ok(H.said("nearest stable master: |cffffffffXon'cha|r"), "nearest not announced")
  eq(#ns.Geo.route, 1)
  eq(ns.Geo.route[1].label, "Xon'cha - Stable Master")
  ok(ns.Geo.route[1].manual, "stable stop must be manual so pruning keeps it")
  H.fire("CHAT_MSG_SYSTEM", "You have learned a new ability: Dash (Rank 1).")
  eq(#ns.Geo.route, 1, "stable stop was pruned")
end)

test("stables: off my map says so and lists where they are", function()
  local ns = H.load()
  StableDB()
  RunStableScan(ns)
  H.setPosition(1412, 0.5, 0.5)
  local e, _, reason = ns.Stables.Nearest()
  eq(e, nil)
  has(reason, "this map")
  SlashCmdList.BEASTTRAININGTRACKERKURO("stable")
  ok(H.said("stable masters are in:"), "map list missing")
end)

test("stables: Questie status line counts them once ready", function()
  local ns = H.load()
  StableDB()
  RunStableScan(ns)
  has(ns.Geo.AddonStatus()[1].text, "2 stable masters")
end)

------------------------------------------------------------------------
-- Version
------------------------------------------------------------------------
test("version: unpackaged copy reports a development version", function()
  local ns = H.load()
  eq(ns.Version(), "dev")
  has(ns.VersionText(), "development")
  ns = H.load({ version = "v1.5.0" })
  eq(ns.Version(), "dev", "unreplaced packager token")
end)

test("version: packaged release shows its tag and announces updates once", function()
  local ns = H.load({ version = "v1.3.0", db = { lastVersion = "v1.2.0" } })
  eq(ns.VersionText(), "v1.3.0")
  ok(H.said("updated to"), "no update message")
  eq(ns.db.lastVersion, "v1.3.0")

  H.load({ version = "v1.3.0", db = { lastVersion = "v1.3.0" } })
  ok(not H.said("updated to"), "update message on a normal login")
end)

------------------------------------------------------------------------
-- Runner
------------------------------------------------------------------------
local failed = 0
for _, t in ipairs(tests) do
  local good, err = pcall(t.fn)
  if good then
    out("  ok    ", t.name, "\n")
  else
    failed = failed + 1
    out("  FAIL  ", t.name, "\n        ", tostring(err), "\n")
    if os.getenv("GITHUB_ACTIONS") then
      -- shows up as an annotation on the Actions run page
      out("::error title=Test failed::", t.name, " - ", (tostring(err):gsub("[\r\n]", " ")), "\n")
    end
  end
end
out(("\n%d tests, %d failed\n"):format(#tests, failed))
os.exit(failed > 0 and 1 or 0)
