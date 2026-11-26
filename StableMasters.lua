local _, ns = ...

------------------------------------------------------------------------
-- Stable masters: where to park a pet.
--
-- Source: QuestieDB only (LibQuestieDB.Npc). Every NPC whose npcFlags carry
-- the flavour's STABLEMASTER bit (LibQuestieDB.Enum.npcFlags resolves the
-- value per flavour - 8192 on Era/Forever, 4194304 on TBC+ - so it is never
-- hard-coded here), is not a "[DND]" placeholder, and is friendly to the
-- player's faction. One entry per spawn point. Session-only, no SavedVariables.
--
-- The scan runs once Geo.ready is set (QuestieDB's name index is built), in a
-- coroutine that yields every few hundred ids so login does not hitch.
-- Geo.lua draws the pins; Core.lua has the /bttk stable command; the Beast
-- Training window line lives in Trainer line section of UI.lua.
------------------------------------------------------------------------
local Stables = { ready = false, status = "waiting for login", list = {}, count = 0 }
ns.Stables = Stables

local SCAN_BATCH = 700 -- ids per frame, same pace Questie's townsfolk scan uses

-- LibQuestieDB.Npc is captured, never the NpcDB global (other addons clobber
-- it; see AddonManagement\_EXTERNAL_APIS\questiedb_contract_4.md).
local function Npc()
  local LQ = _G.LibQuestieDB
  return LQ and LQ.Npc or nil
end

local function StableMask()
  local LQ = _G.LibQuestieDB
  local flags = LQ and LQ.Enum and LQ.Enum.npcFlags
  return flags and flags.STABLEMASTER or nil
end

function Stables.HasSource()
  local npc = Npc()
  return npc ~= nil and npc.GetAllIds ~= nil and npc.npcFlags ~= nil and StableMask() ~= nil
end

-- Does this NPC serve the player's faction? QuestieDB: "A" | "H" | "AH" | nil (hostile to both).
local function FriendlyToMe(npc, id)
  local ok, f = pcall(npc.friendlyToFaction, id)
  if not ok or f == nil then return false end
  if f == "AH" then return true end
  return f == ns.Client.PlayerFactionKey()
end

-- Spawn table -> entries. Coordinates are 0..100 percent on the zone map;
-- -1,-1 is QuestieDB's "no fixed position" sentinel. Area -> uiMapID via
-- Geo's QuestieDB zone tables.
local function AddSpawns(out, id, name, faction, spawns)
  for area, pts in pairs(spawns) do
    local map = ns.Geo.MapForArea(area)
    if map and type(pts) == "table" then
      for _, pt in ipairs(pts) do
        local x, y = pt[1], pt[2]
        if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then
          out[#out + 1] = { id = id, name = name, map = map, x = x / 100, y = y / 100, faction = faction }
        end
      end
    end
  end
end

-- Full pass over every NPC id. Runs inside a coroutine; yields every SCAN_BATCH ids.
local function ScanBody()
  local npc, mask = Npc(), StableMask()
  local out, n = {}, 0
  local okIds, ids = pcall(npc.GetAllIds, true)
  if not okIds or type(ids) ~= "table" then error("NpcDB.GetAllIds failed") end
  for id in pairs(ids) do
    local okF, flags = pcall(npc.npcFlags, id)
    if okF and type(flags) == "number" and bit.band(flags, mask) == mask then
      local okN, name = pcall(npc.name, id)
      if okN and type(name) == "string" and name:sub(1, 5) ~= "[DND]" and FriendlyToMe(npc, id) then
        local okS, spawns = pcall(npc.spawns, id)
        if okS and type(spawns) == "table" then
          local _, f = pcall(npc.friendlyToFaction, id)
          AddSpawns(out, id, name, f, spawns)
        end
      end
    end
    n = n + 1
    if n % SCAN_BATCH == 0 then coroutine.yield() end
  end
  return out
end

local scanning
function Stables.Scan()
  if scanning or Stables.ready then return end
  if not Stables.HasSource() then
    Stables.status = "QuestieDB not installed"
    return
  end
  scanning = true
  Stables.status = "scanning stable masters..."
  local co = coroutine.create(ScanBody)
  local runner = CreateFrame("Frame")
  runner:SetScript("OnUpdate", function(self)
    local ok, res = coroutine.resume(co)
    if not ok then
      self:SetScript("OnUpdate", nil)
      scanning = false
      Stables.status = "QuestieDB error: " .. tostring(res)
      return
    end
    if coroutine.status(co) == "dead" then
      self:SetScript("OnUpdate", nil)
      scanning = false
      Stables.list = type(res) == "table" and res or {}
      -- how many distinct NPCs (the list is per spawn point)
      local seen, c = {}, 0
      for _, e in ipairs(Stables.list) do if not seen[e.id] then seen[e.id] = true; c = c + 1 end end
      Stables.count = c
      Stables.ready = true
      Stables.status = ("%d stable masters"):format(c)
      if ns.Refresh then ns.Refresh() end
    end
  end)
end

-- Entries on one uiMapID
function Stables.ForMap(mapID)
  local out = {}
  for _, e in ipairs(Stables.list) do
    if e.map == mapID then out[#out + 1] = e end
  end
  return out
end

-- Nearest entry on the map you are standing on -> entry, dist2 | nil, reason
function Stables.Nearest()
  if not Stables.HasSource() then return nil, nil, "QuestieDB is not installed - stable master locations need it." end
  if not Stables.ready then return nil, nil, "stable master locations are still loading - try again in a moment." end
  local pm, px, py = ns.Geo.PlayerPos()
  if not pm then return nil, nil, "can't tell where you are right now." end
  local best, bd
  for _, e in ipairs(Stables.list) do
    if e.map == pm then
      local d = px and ((e.x - px) ^ 2 + (e.y - py) ^ 2) or 0
      if not bd or d < bd then best, bd = e, d end
    end
  end
  if best then return best, bd end
  return nil, nil, "no stable master on this map."
end

-- Names of maps that have a stable master (for the "none here" message)
function Stables.MapNames(limit)
  local seen, names = {}, {}
  for _, e in ipairs(Stables.list) do
    if not seen[e.map] then
      seen[e.map] = true
      local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(e.map)
      names[#names + 1] = info and info.name or ("map " .. e.map)
    end
  end
  table.sort(names)
  if limit and #names > limit then
    local extra = #names - limit
    for i = #names, limit + 1, -1 do names[i] = nil end
    names[#names + 1] = ("and %d more"):format(extra)
  end
  return names
end

-- /bttk stable: say where the nearest one is and add it as a route stop
function Stables.Command()
  local Say = ns.Say
  local e, d2, reason = Stables.Nearest()
  if not e then
    Say("nearest stable master: " .. reason)
    if Stables.ready and reason:find("this map") then
      Say("  stable masters are in: " .. table.concat(Stables.MapNames(8), ", "))
    end
    return false
  end
  local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(e.map)
  Say(("nearest stable master: |cffffffff%s|r in %s (%.0f, %.0f)"):format(e.name, info and info.name or "?", e.x * 100, e.y * 100))
  ns.Geo.WaypointStable(e)
  local hint = ns.Client.StableMasterNativeTrackingHint()
  if hint then Say("  " .. hint) end
  return true
end

-- Kick the scan once QuestieDB's name index is built (Geo flips ready and refreshes)
ns.OnRefresh(function()
  if ns.Geo and ns.Geo.ready and not Stables.ready then Stables.Scan() end
  -- Beast Training window open while the scan finished / player moved
  if ns.UpdateTrainerStableLine and ClassTrainerFrame and ClassTrainerFrame:IsShown() then
    ns.UpdateTrainerStableLine()
  end
end)

ns.OnLogin(function()
  if not Stables.HasSource() then Stables.status = "QuestieDB not installed" end
end)