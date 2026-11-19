local _, ns = ...

------------------------------------------------------------------------
-- RareScanner integration
--
-- Static data (which teachers are rares, where they spawn/patrol) is baked
-- into RareData.lua, so it works even if RareScanner changes or is off.
-- Live data (last seen, kills, respawn timing) is read from RareScanner's
-- saved variables. RareScanner has no public API, so every read is
-- defensive: if its format changes, we simply show nothing.
------------------------------------------------------------------------
local RS = {}
ns.RS = RS

local function DB()
  local d = _G.RareScannerDB
  return type(d) == "table" and d or nil
end

function RS.Loaded()
  local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  return isLoaded and isLoaded("RareScanner") and DB() ~= nil or false
end

-- RareData.lua (local-only copy of RareScanner's table) adds coordinates;
-- the published addon only ships RareIds.lua (NPC ids for the live timers).
function RS.Get(name)
  local r = ns.rsRares and ns.rsRares[name]
  if r then return r end
  local id = ns.rareIds and ns.rareIds[name]
  return id and { id = id } or nil
end

local function Now() return (GetServerTime and GetServerTime()) or time() end

local function Num(v)
  v = tonumber(v)
  if v and v == v and v ~= math.huge and v ~= -math.huge then return v end
end

local function Coord(v)
  v = Num(v)
  if not v then return end
  if v > 1 then v = v / 10000 end
  return v
end

function RS.Ago(sec)
  sec = math.max(0, math.floor(sec))
  if sec < 60 then return sec .. "s" end
  if sec < 3600 then return math.floor(sec / 60) .. "m" end
  if sec < 86400 then
    local h, m = math.floor(sec / 3600), math.floor((sec % 3600) / 60)
    return m > 0 and h < 10 and (h .. "h " .. m .. "m") or (h .. "h")
  end
  return math.floor(sec / 86400) .. "d"
end

-- { time=, map=, x=, y= } from RareScanner's "rares_found"
function RS.LastSeen(id)
  local ok, res = pcall(function()
    local f = DB().global.rares_found[id]
    if type(f) ~= "table" or not Num(f.foundTime) then return end
    return { time = Num(f.foundTime), map = Num(f.mapID), x = Coord(f.coordX), y = Coord(f.coordY) }
  end)
  return ok and res or nil
end

-- Median respawn in seconds from RareScanner's (guild-synced) telemetry
function RS.RespawnEstimate(id)
  local ok, est, n = pcall(function()
    local samples = DB().global.telemetry.npcs[id].samples
    local list = {}
    for _, s in ipairs(samples) do
      local sp, de = Num(s.spawnTime), Num(s.deathTime)
      if sp and de and not s.gap then
        local d = sp - de
        if d > 30 and d < 6 * 3600 then list[#list + 1] = d end
      end
    end
    if #list == 0 then return end
    table.sort(list)
    return list[math.floor((#list + 1) / 2)], #list
  end)
  if ok then return est, n end
end

-- Most recent death RareScanner knows about (any layer)
function RS.LastDeath(id)
  local ok, res = pcall(function()
    local best
    for _, kills in pairs(DB().global.telemetry.recentKills) do
      local k = type(kills) == "table" and kills[id]
      local ts = type(k) == "table" and Num(k.timestamp)
      if ts and (not best or ts > best) then best = ts end
    end
    return best
  end)
  return ok and res or nil
end

-- Your own kill: RareScanner stores the respawn timestamp, or -1 for "never"
-- RareScanner's db.char is AceDB-keyed by name; the key shape differs per
-- flavour (Forever: "First Surname" / "First - Realm"), so the candidate list
-- comes from the client layer and nothing here touches UnitName/GetRealmName.
function RS.MyKill(id)
  local ok, res = pcall(function()
    local chars = DB().char
    for _, key in ipairs(ns.Client.ThirdPartyCharKeyCandidates()) do
      local c = chars[key]
      if type(c) == "table" and type(c.rares_killed) == "table" then
        return Num(c.rares_killed[id])
      end
    end
  end)
  return ok and res or nil
end

-- Status for a rare teacher. Returns { text=, short=, up=bool|nil, seen=table|nil }
function RS.Status(name)
  local r = RS.Get(name)
  if not r or not RS.Loaded() then return nil end
  local now = Now()
  local st = { seen = RS.LastSeen(r.id) }
  local parts = {}

  local mine = RS.MyKill(r.id)
  local death = RS.LastDeath(r.id)
  local est = RS.RespawnEstimate(r.id)

  if mine and mine > now then
    st.up = false
    st.short = "|cffff6060back in " .. RS.Ago(mine - now) .. "|r"
    parts[#parts + 1] = "you killed it - respawns in " .. RS.Ago(mine - now)
  elseif death and now - death < 6 * 3600 then
    if est and now < death + est then
      st.up = false
      st.short = "|cffff9040back in ~" .. RS.Ago(death + est - now) .. "|r"
      parts[#parts + 1] = ("died %s ago - back in ~%s"):format(RS.Ago(now - death), RS.Ago(death + est - now))
    elseif est then
      st.up = true
      st.short = "|cff40ff40should be up|r"
      parts[#parts + 1] = ("died %s ago - should be up (respawn ~%s)"):format(RS.Ago(now - death), RS.Ago(est))
    else
      st.short = "|cffff9040died " .. RS.Ago(now - death) .. " ago|r"
      parts[#parts + 1] = ("died %s ago"):format(RS.Ago(now - death))
    end
  end
  if st.seen and st.seen.time then
    local ago = now - st.seen.time
    parts[#parts + 1] = ("last seen %s ago"):format(RS.Ago(ago)) ..
      ((st.seen.x and st.seen.y) and (" at %.0f, %.0f"):format(st.seen.x * 100, st.seen.y * 100) or "")
    if not st.short then st.short = "|cff9d9d9dseen " .. RS.Ago(ago) .. " ago|r" end
  end
  if est then parts[#parts + 1] = ("usual respawn ~%s"):format(RS.Ago(est)) end
  if #parts == 0 then return nil end
  st.text = table.concat(parts, "  ·  ")
  return st
end

-- RareScanner already pops an alert for rares on its list
function RS.HandlesAlert(name)
  return ns.db and ns.db.opts.rsHandlesRares and RS.Get(name) ~= nil and RS.Loaded()
end

------------------------------------------------------------------------
-- Rare Pets collection
------------------------------------------------------------------------
-- Petopia's rare list (RarePets.lua) is the source; RareScanner adds timers.
-- Innate traits come with that exact pet and can't be taught.
local CLASSIC_NOTES = {
  ["Lupos"] = { short = "Shadow dmg?", long = "In Classic, Lupos' melee deals shadow damage (innate - unverified on Forever)." },
}

local FAMILY_ICON = {
  ["Bird of Prey"] = "Ability_Hunter_Pet_Owl", ["Carrion Bird"] = "Ability_Hunter_Pet_Vulture",
  ["Wind Serpent"] = "Ability_Hunter_Pet_WindSerpent", ["Tallstrider"] = "Ability_Hunter_Pet_TallStrider",
}
local function FamilyIcon(fam)
  if fam == "Fox" or fam == "Core Hound" or not fam then return "Interface\\Icons\\Ability_Hunter_BeastTaming" end
  local n = FAMILY_ICON[fam] or ("Ability_Hunter_Pet_" .. fam:gsub("%s", ""))
  return "Interface\\Icons\\" .. n
end
RS.FamilyIcon = FamilyIcon

-- "1.2" green (faster than normal), "2.0" grey (normal), "2.5" orange (slower)
function RS.SpeedText(speed)
  if not speed then return "|cff808080?|r" end
  local s = ("%.1f"):format(speed)
  if speed <= 1.3 then return "|cff40ff40" .. s .. "|r" end
  if speed < 2.0 then return "|cff9be37a" .. s .. "|r" end
  if speed > 2.0 then return "|cffff9040" .. s .. "|r" end
  return "|cff9d9d9d" .. s .. "|r"
end

-- list of { short=, long= } for the table / tooltip (type + speed have their own columns)
local function Traits(p)
  local out = {}
  if p.unique then
    out[#out + 1] = { short = "|cffffd100Unique look|r", long = "Unique look - Petopia lists this skin on only one tameable beast." }
  end
  local note = CLASSIC_NOTES[p.name]
  if note then out[#out + 1] = { short = "|cffb080ff" .. note.short .. "|r", long = note.long } end
  if p.spawned then
    out[#out + 1] = { short = "|cff69ccf0Quest spawn|r", long = "Spawned by a quest or trigger - usually a one-time chance, sometimes faction-only." }
  end
  local rs = RS.Get(p.name)
  if (rs and rs.id >= 200000) or p.zone:find("Zephras", 1, true) then
    out[#out + 1] = { short = "|cff69ccf0Forever-only|r", long = "Custom beast added by WoW Forever - not in original Classic." }
  end
  if p.speed and p.speed < 2.0 then
    out[#out + 1] = { short = "", long = ("Attack speed %.1f (normal is 2.0) - it stays with this pet."):format(p.speed) }
  elseif p.speed and p.speed > 2.0 then
    out[#out + 1] = { short = "", long = ("Attack speed %.1f (normal is 2.0) - slower than most pets."):format(p.speed) }
  end
  if p.elite then
    out[#out + 1] = { short = "", long = "Elite in the wild (tougher to tame) - no stronger than a normal pet once tamed." }
  end
  return out
end

function RS.TypeText(p)
  local parts = {}
  if p.rare then parts[#parts + 1] = "|cffff8000Rare|r" end
  if p.elite then parts[#parts + 1] = "|cffffd100Elite|r" end
  if p.spawned then parts[#parts + 1] = "|cff69ccf0Spawned|r" end
  return table.concat(parts, " ")
end

-- One special pet: { name, t (family/level/zone), speed, traits, teaches, status, tamed, icon }
function RS.Info(name)
  local p = ns.rarePetByName and ns.rarePetByName[name]
  if not p then return nil end
  local seen, teaches = {}, {}
  for _, e in ipairs(ns.teacherIndex[name] or {}) do
    local k = ns.Key(e.ab.name, e.rank.rank)
    if not seen[k] then
      seen[k] = true
      teaches[#teaches + 1] = e
    end
  end
  table.sort(teaches, function(a, b)
    if a.ab.name ~= b.ab.name then return a.ab.name < b.ab.name end
    return a.rank.rank < b.rank.rank
  end)
  return {
    name = name, t = p, speed = p.speed, traits = Traits(p), teaches = teaches,
    status = RS.Status(name),
    tamed = ns.db and ns.db.tamedRares[name] or nil,
    icon = FamilyIcon(p.family),
  }
end

-- Untamed first, then (fastest first | "should be up"), then by level
function RS.AllRares(bySpeed)
  local out = {}
  for _, p in ipairs(ns.rarePets or {}) do
    out[#out + 1] = RS.Info(p.name)
  end
  table.sort(out, function(a, b)
    if (a.tamed and 1 or 0) ~= (b.tamed and 1 or 0) then return not a.tamed end
    if bySpeed then
      local as, bs = a.speed or 9, b.speed or 9
      if as ~= bs then return as < bs end
    end
    local au = a.status and a.status.up and 0 or 1
    local bu = b.status and b.status.up and 0 or 1
    if au ~= bu then return au < bu end
    if a.t.minLevel ~= b.t.minLevel then return a.t.minLevel < b.t.minLevel end
    return a.name < b.name
  end)
  return out
end

------------------------------------------------------------------------
-- Knowing which special pet the current pet is.
-- Forever gives every hunter pet the same generic NPC id in its GUID, so we
-- can't read the original beast from the pet. Instead we:
--   1. watch Tame Beast: target name -> the pet that appears right after
--   2. remember links by pet GUID and by pet name+family (survives renames)
--   3. right-clicking a row while that pet is out links it by hand
------------------------------------------------------------------------
local function Links()
  ns.db.petLinks = ns.db.petLinks or {}       -- "Kittery|Cat" -> "The Rake"
  ns.db.petGuidLinks = ns.db.petGuidLinks or {} -- pet GUID -> "The Rake"
  ns.db.tamedNicks = ns.db.tamedNicks or {}   -- "The Rake" -> "Kittery"
end

local function PetKey()
  if not UnitExists("pet") then return end
  return (UnitName("pet") or "?") .. "|" .. (UnitCreatureFamily("pet") or "?")
end

local function RareFromPet()
  if not ns.db or not UnitExists("pet") then return end
  Links()
  local guid = UnitGUID("pet")
  if guid and ns.db.petGuidLinks[guid] then return ns.db.petGuidLinks[guid] end
  local key = PetKey()
  if key and ns.db.petLinks[key] then return ns.db.petLinks[key] end
  local name = UnitName("pet")
  local sp = name and ns.rarePetByName[name]
  if sp and sp.family == UnitCreatureFamily("pet") then return name end
end
RS.RareFromPet = RareFromPet

-- Tie the pet that's out right now to a special pet
local function LinkPet(rare)
  if not UnitExists("pet") then return end
  Links()
  local guid, key, nick = UnitGUID("pet"), PetKey(), UnitName("pet")
  if guid then ns.db.petGuidLinks[guid] = rare end
  if key then ns.db.petLinks[key] = rare end
  if nick and nick ~= rare then ns.db.tamedNicks[rare] = nick end
end

local function MarkTamed(rare, how)
  if ns.db.tamedRares[rare] then return end
  ns.db.tamedRares[rare] = time()
  ns.tamedSerial = (ns.tamedSerial or 0) + 1
  local nick = ns.db.tamedNicks and ns.db.tamedNicks[rare]
  local who = nick and (rare .. " (" .. nick .. ")") or rare
  if how ~= "manual" then
    if ns.Toast then ns.Toast("Special pet tamed!", { who .. " joined your collection" }, FamilyIcon(ns.rarePetByName[rare].family)) end
    ns.Say(("|cffff8000Tamed %s!|r Added to your Special Pets collection."):format(who))
  end
end

function RS.SetTamed(name, on)
  local sp = ns.db and ns.rarePetByName[name]
  if not sp then return end
  if on then
    -- right-click with that pet out (same family): link it so renames are tracked
    if UnitExists("pet") and UnitCreatureFamily("pet") == sp.family then
      LinkPet(name)
      ns.Say(("linked your pet |cffffffff%s|r to %s."):format(UnitName("pet") or "?", name))
    end
    MarkTamed(name, "manual")
  else
    ns.db.tamedRares[name] = nil
    if ns.db.tamedNicks then ns.db.tamedNicks[name] = nil end
    for k, v in pairs(ns.db.petLinks or {}) do if v == name then ns.db.petLinks[k] = nil end end
    for k, v in pairs(ns.db.petGuidLinks or {}) do if v == name then ns.db.petGuidLinks[k] = nil end end
    ns.tamedSerial = (ns.tamedSerial or 0) + 1
  end
  ns.Refresh()
end

ns.OnInit(function(db) db.tamedRares = db.tamedRares or {} end)

-- /bttk petinfo: what the game reports about the current pet
function RS.PetInfo()
  if not UnitExists("pet") then ns.Say("no pet out.") return end
  ns.Say(("pet: %s  |  family: %s  |  level: %s"):format(UnitName("pet") or "?", UnitCreatureFamily("pet") or "?", UnitLevel("pet") or "?"))
  ns.Say("GUID: " .. (UnitGUID("pet") or "nil"))
  ns.Say("linked to: " .. tostring(RareFromPet() or "nothing - right-click its row in Special Pets to link it"))
end

local pendingTame   -- { name=, t= } from the last Tame Beast cast
local lastGuid, lastName

local function CheckPet()
  if not ns.db or not UnitExists("pet") then return end
  local guid, name = UnitGUID("pet"), UnitName("pet")

  -- just tamed a special pet?
  if pendingTame and GetTime() - pendingTame.t < 90 and guid ~= lastGuid then
    local sp = ns.rarePetByName[pendingTame.name]
    if sp and sp.family == UnitCreatureFamily("pet") then
      LinkPet(pendingTame.name)
      MarkTamed(pendingTame.name)
      pendingTame = nil
    end
  end

  -- same pet, new name (renamed): carry the link over
  if guid and guid == lastGuid and name ~= lastName and ns.db.petGuidLinks and ns.db.petGuidLinks[guid] then
    LinkPet(ns.db.petGuidLinks[guid])
  end

  local rare = RareFromPet()
  if rare then
    LinkPet(rare)
    MarkTamed(rare)
  end
  lastGuid, lastName = guid, name
  ns.Refresh()
end

local TAME_BEAST = 1515
local tev = CreateFrame("Frame")
for _, e in ipairs({ "UNIT_PET", "PLAYER_ENTERING_WORLD", "UNIT_NAME_UPDATE", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_CHANNEL_START" }) do
  pcall(tev.RegisterEvent, tev, e)
end
tev:SetScript("OnEvent", function(_, e, unit, a2, a3, a4)
  if not ns.Active() then return end -- hunter-only mode on another class
  if e == "UNIT_SPELLCAST_SENT" then
    -- unit, target name, castGUID, spellID
    if unit == "player" and a4 == TAME_BEAST and a2 and a2 ~= "" then pendingTame = { name = a2, t = GetTime() } end
  elseif e == "UNIT_SPELLCAST_CHANNEL_START" then
    -- unit, castGUID, spellID
    if unit == "player" and a3 == TAME_BEAST and UnitExists("target") then
      pendingTame = { name = UnitName("target"), t = GetTime() }
    end
  elseif e == "UNIT_NAME_UPDATE" then
    if unit == "pet" then C_Timer.After(0.5, CheckPet) end
  elseif e == "UNIT_PET" then
    if unit == "player" then C_Timer.After(1, CheckPet) end
  else
    C_Timer.After(4, CheckPet)
  end
end)

-- Rare teachers that still teach you something you can tame now
function RS.NeededRares()
  local out = {}
  local src = ns.rareIds or ns.rsRares
  if not src then return out end
  for name in pairs(src) do
    local list = ns.teacherIndex[name]
    if list then
      local best, t = {}, nil
      for _, e in ipairs(list) do
        if not ns.IsKnown(e.ab, e.rank.rank) and ns.CanTame(e.t) then
          t = e.t
          local cur = best[e.ab.name]
          if not cur or e.rank.rank > cur.rank.rank then best[e.ab.name] = e end
        end
      end
      if t then
        local teaches = {}
        for _, e in pairs(best) do teaches[#teaches + 1] = e end
        table.sort(teaches, function(a, b) return a.ab.name < b.ab.name end)
        out[#out + 1] = { name = name, t = t, teaches = teaches, status = RS.Status(name) }
      end
    end
  end
  table.sort(out, function(a, b)
    local au = a.status and a.status.up and 0 or 1
    local bu = b.status and b.status.up and 0 or 1
    if au ~= bu then return au < bu end
    if a.t.minLevel ~= b.t.minLevel then return a.t.minLevel > b.t.minLevel end
    return a.name < b.name
  end)
  return out
end
