local _, ns = ...

------------------------------------------------------------------------
-- Beast locations, waypoints and map pins.
--
-- Works on its own and gets better with optional addons:
--   * own sightings  - every teacher / special pet you target, mouse over or
--                      see a nameplate of is remembered (account-wide). Always on.
--   * Questie        - QuestieDB spawn points for every beast
--   * RareScanner    - where rares were last seen (yours + guild)
--   * RareData.lua   - local-only rare spawn file (not published)
-- Waypoints use TomTom when installed, otherwise a built-in map pin + a
-- minimap marker that sits on the minimap edge pointing the way.
-- Map pins use HereBeDragons, bundled in Libs.
------------------------------------------------------------------------
local Geo = { ready = false, status = "waiting for login" }
ns.Geo = Geo

local qcache = {}      -- npc name -> { spawns=, rare=, elite= } | false   (QuestieDB part only)
local areaToMap        -- Questie areaId -> uiMapID
local mapByName        -- "Duskwood" -> uiMapID

------------------------------------------------------------------------
-- Optional addons
------------------------------------------------------------------------
-- QuestieDB's NPC reader. Always LibQuestieDB.Npc, never the NpcDB global:
-- that is a generic name other addons overwrite (see
-- AddonManagement\_EXTERNAL_APIS\questiedb_contract_4.md).
local function Npc()
  local LQ = _G.LibQuestieDB
  return LQ and LQ.Npc or nil
end
Geo.Npc = Npc
function Geo.HasQuestie() local n = Npc() return n ~= nil and n.IdsByName ~= nil end
function Geo.HasTomTom() return TomTom and TomTom.AddWaypoint and true or false end
function Geo.HasRareScanner() return ns.RS and ns.RS.Loaded() or false end

------------------------------------------------------------------------
-- QuestieDB zone ids -> map ids
------------------------------------------------------------------------
local function ToTable(v)
  if type(v) == "string" then
    local fn = loadstring and loadstring(v)
    if not fn then return nil end
    local ok, t = pcall(fn)
    return ok and type(t) == "table" and t or nil
  end
  return type(v) == "table" and v or nil
end

local function LoadAreaMap()
  areaToMap = {}
  local LQ = _G.LibQuestieDB
  local zdb = LQ and LQ.Support and LQ.Support.Get and LQ.Support.Get("ZoneDB")
  local p = zdb and zdb.private
  if p then
    for _, key in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
      local t = ToTable(p[key])
      if t then
        for area, m in pairs(t) do areaToMap[area] = (m and m > 0) and m or nil end
      end
    end
  end
end

local function QuestieZoneMap(area)
  if not (QuestieLoader and QuestieLoader.ImportModule) then return end
  local ok, z = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
  if ok and z and z.GetUiMapIdByAreaId then
    local ok2, m = pcall(z.GetUiMapIdByAreaId, z, area)
    if ok2 and m and m > 0 then return m end
  end
end

local function MapFor(area)
  if not areaToMap then LoadAreaMap() end
  local m = areaToMap[area] or QuestieZoneMap(area)
  if m then areaToMap[area] = m end
  return m
end
Geo.MapForArea = MapFor -- StableMasters.lua uses the same QuestieDB area -> uiMapID tables

function Geo.MapIdByName(zone)
  if not mapByName then
    mapByName = {}
    if C_Map and C_Map.GetMapInfo then
      for id = 1, 3000 do
        local info = C_Map.GetMapInfo(id)
        if info and info.name then
          local cur = mapByName[info.name]
          -- prefer real zone maps (type 3) over dungeons/micro maps
          if not cur or (info.mapType == 3 and cur.type ~= 3) then
            mapByName[info.name] = { id = id, type = info.mapType }
          end
        end
      end
    end
  end
  local z = (zone or ""):gsub("%s*%b()", "")
  local e = mapByName[z]
  return e and e.id
end

-- QuestieDB data for one npc name (cached once QuestieDB is ready)
local function QuestieInfo(name)
  if not Geo.ready then return nil end
  local c = qcache[name]
  if c ~= nil then return c or nil end
  local res = { spawns = {} }
  for _, id in ipairs(Npc().IdsByName(name) or {}) do
    local ok, rank = pcall(Npc().Get, id, "rank")
    if ok and rank then
      if rank == 2 or rank == 4 then res.rare = true end
      if rank == 1 or rank == 2 or rank == 3 then res.elite = true end
    end
    local ok2, sp = pcall(Npc().Get, id, "spawns")
    if ok2 and type(sp) == "table" then
      for area, pts in pairs(sp) do
        local m = MapFor(area)
        if m and type(pts) == "table" then
          for _, pt in ipairs(pts) do
            local x, y = pt[1], pt[2]
            if x and y and x >= 0 and y >= 0 then
              res.spawns[#res.spawns + 1] = { map = m, x = x / 100, y = y / 100, src = "questie" }
            end
          end
        end
      end
    end
  end
  qcache[name] = (#res.spawns > 0 or res.rare or res.elite) and res or false
  return qcache[name] or nil
end

------------------------------------------------------------------------
-- Player position
------------------------------------------------------------------------
local function PlayerPos()
  if not (C_Map and C_Map.GetBestMapForUnit) then return end
  local m = C_Map.GetBestMapForUnit("player")
  if not m then return end
  local p = C_Map.GetPlayerMapPosition(m, "player")
  if p then
    local x, y = p:GetXY()
    if x and y and (x > 0 or y > 0) then return m, x, y end
  end
  return m
end
Geo.PlayerPos = PlayerPos

------------------------------------------------------------------------
-- Own sightings (account-wide, BeastTrainingTrackerKuroSeen)
--   Seen[name] = { {map, x, y, time}, ... }
-- The game doesn't give other units' positions, so a sighting is where
-- you were standing - close enough when a nameplate is in view.
------------------------------------------------------------------------
local MAX_SPOTS = 15
local lastRecord = {}

local function Tracked(name)
  return name and (ns.teacherIndex[name] or (ns.rarePetByName and ns.rarePetByName[name])) and true or false
end

function Geo.RecordSighting(unit)
  if not Geo.seen or not UnitExists(unit) or UnitIsPlayer(unit) or UnitPlayerControlled(unit) then return end
  local name = UnitName(unit)
  if not Tracked(name) then return end
  local now = time()
  if lastRecord[name] and now - lastRecord[name] < 15 then return end
  lastRecord[name] = now
  local m, x, y = PlayerPos()
  if not (m and x and y) then return end
  x, y = math.floor(x * 1000 + 0.5) / 1000, math.floor(y * 1000 + 0.5) / 1000

  local list = Geo.seen[name]
  if not list then list = {}; Geo.seen[name] = list end
  for _, p in ipairs(list) do
    if p[1] == m and (p[2] - x) ^ 2 + (p[3] - y) ^ 2 < 0.0003 then
      p[4] = now -- same spot, just refresh the time
      return
    end
  end
  list[#list + 1] = { m, x, y, now }
  if #list > MAX_SPOTS then table.remove(list, 1) end
  ns.seenSerial = (ns.seenSerial or 0) + 1
  Geo.QueuePins()
  return true
end

function Geo.SeenCount()
  local n = 0
  for _ in pairs(Geo.seen or {}) do n = n + 1 end
  return n
end

------------------------------------------------------------------------
-- All known spots for a beast, from every source.
-- Returns { spawns = {{map=, x=, y=, src=}...}, rare=, elite= } or nil
------------------------------------------------------------------------
function Geo.Lookup(name)
  local res = { spawns = {} }
  local function add(map, x, y, src)
    if map and x and y then res.spawns[#res.spawns + 1] = { map = map, x = x, y = y, src = src } end
  end

  -- local rare file (precise spawn + patrol path)
  local rs = ns.rsRares and ns.rsRares[name]
  if rs then
    res.rare = true
    add(rs.map, rs.x, rs.y, "rare")
    for _, pt in ipairs(rs.path or {}) do add(rs.map, pt[1], pt[2], "rare") end
  end

  -- QuestieDB
  local q = QuestieInfo(name)
  if q then
    res.rare, res.elite = res.rare or q.rare, q.elite
    if not rs then
      for _, s in ipairs(q.spawns) do res.spawns[#res.spawns + 1] = s end
    end
  end

  -- your own sightings: only when nothing better is known. A sighting is
  -- where *you* stood, so it would always win "nearest spawn" otherwise.
  if #res.spawns == 0 then
    for _, p in ipairs(Geo.seen and Geo.seen[name] or {}) do add(p[1], p[2], p[3], "seen") end
  end

  -- RareScanner: where it was last seen
  local r = ns.RS and ns.RS.Get(name)
  if r and Geo.HasRareScanner() then
    local ls = ns.RS.LastSeen(r.id)
    if ls then add(ls.map, ls.x, ls.y, "rarescanner") end
  end

  if #res.spawns == 0 and not res.rare and not res.elite then return nil end
  return res
end

function Geo.IsRare(name)
  if ns.db and ns.db.rares[name] then return true end
  local sp = ns.rarePetByName and ns.rarePetByName[name]
  if sp and sp.rare then return true end
  if ns.rsRares and ns.rsRares[name] then return true end
  local q = QuestieInfo(name)
  return q and q.rare or false
end

function Geo.IsElite(name)
  local sp = ns.rarePetByName and ns.rarePetByName[name]
  if sp and sp.elite then return true end
  local q = QuestieInfo(name)
  return q and q.elite or false
end

function Geo.Tag(name)
  if Geo.IsRare(name) then
    local st = ns.RS and ns.RS.Status(name)
    return " |cffff8000[Rare]|r" .. (st and st.short and (" " .. st.short) or "")
  end
  if Geo.IsElite(name) then return " |cffffd100[Elite]|r" end
  return ""
end

-- Number of beasts with known locations (for the status line)
-- /bttk where <beast>: where this beast's locations come from (for bug reports)
function Geo.Explain(name)
  local Say = ns.Say
  if not name or name == "" then Say("usage: /bttk where <beast name>") return end
  -- accept any capitalization: "moss stalker" -> "Moss Stalker"
  local want = name:lower()
  for n in pairs(ns.teacherIndex) do if n:lower() == want then name = n break end end
  for n in pairs(ns.rarePetByName or {}) do if n:lower() == want then name = n break end end
  Say(("locations for |cffffffff%s|r:"):format(name))
  local known = ns.teacherIndex[name] or (ns.rarePetByName and ns.rarePetByName[name])
  Say("  in the addon's beast data: " .. (known and "yes" or "|cffff4040no - check the spelling|r"))
  if not Geo.HasQuestie() then
    Say("  Questie: not installed")
  elseif not Geo.ready then
    Say("  Questie: still loading")
  else
    local ids = Npc().IdsByName(name) or {}
    Say(("  Questie: %d NPC id(s) %s"):format(#ids, table.concat(ids, ", ")))
    for _, id in ipairs(ids) do
      local ok, sp = pcall(Npc().Get, id, "spawns")
      if ok and type(sp) == "table" then
        for area, pts in pairs(sp) do
          local m = MapFor(area)
          Say(("    zone %s -> map %s: %d spawn point(s)%s"):format(tostring(area), tostring(m),
            type(pts) == "table" and #pts or 0, m and "" or " |cffff4040(zone not mapped - not shown)|r"))
        end
      else
        Say(("    id %s: no spawn data"):format(tostring(id)))
      end
    end
  end
  local seen = Geo.seen and Geo.seen[name]
  Say(("  your sightings: %d spot(s)"):format(seen and #seen or 0))
  Say("  local rare data: " .. ((ns.rsRares and ns.rsRares[name]) and "yes" or "no"))
  local info = Geo.Lookup(name)
  local by = {}
  for _, s in ipairs(info and info.spawns or {}) do by[s.src] = (by[s.src] or 0) + 1 end
  local parts = {}
  for src, n in pairs(by) do parts[#parts + 1] = ("%s %d"):format(src, n) end
  Say("  used for pins/routes: " .. (#parts > 0 and table.concat(parts, ", ") or "nothing"))
end

function Geo.LocatedCount()
  local n = 0
  for _, v in pairs(qcache) do if v and #v.spawns > 0 then n = n + 1 end end
  return n
end

-- Nearest spawn to you if you're on that map, else the middle of the pack
function Geo.BestSpawn(info, zoneName)
  local pm, px, py = PlayerPos()
  local best, bd
  if pm and px then
    for _, s in ipairs(info.spawns) do
      if s.map == pm then
        local d = (s.x - px) ^ 2 + (s.y - py) ^ 2
        if not bd or d < bd then best, bd = s, d end
      end
    end
    if best then return best end
  end
  local want = Geo.MapIdByName(zoneName)
  local pool = {}
  for _, s in ipairs(info.spawns) do
    if not want or s.map == want then pool[#pool + 1] = s end
  end
  if #pool == 0 then pool = info.spawns end
  local cx, cy = 0, 0
  for _, s in ipairs(pool) do cx, cy = cx + s.x, cy + s.y end
  cx, cy = cx / #pool, cy / #pool
  for _, s in ipairs(pool) do
    local d = (s.x - cx) ^ 2 + (s.y - cy) ^ 2
    if not bd or d < bd then best, bd = s, d end
  end
  return best
end

-- Where to send the player for this beast. Returns spot, label suffix | nil, reason
function Geo.Destination(t)
  -- a rare RareScanner saw in the last two days: go where it was actually seen
  local r = ns.RS and ns.RS.Get(t.name)
  if r and Geo.HasRareScanner() then
    local seen = ns.RS.LastSeen(r.id)
    local now = (GetServerTime and GetServerTime()) or time()
    if seen and seen.map and seen.x and seen.y and seen.time and now - seen.time < 2 * 86400 then
      return { map = seen.map, x = seen.x, y = seen.y }, " (last seen)"
    end
  end
  local info = Geo.Lookup(t.name)
  if info and #info.spawns > 0 then return Geo.BestSpawn(info, t.zone) end
  if Geo.HasQuestie() and not Geo.ready then
    return nil, nil, "beast locations are still loading - try again in a moment."
  end
  return nil, nil, ("no location known yet for %s - it's in %s. %s"):format(t.name, t.zone or "?",
    Geo.HasQuestie() and "" or "Spot it once (target or mouse over it) and it's remembered, or install Questie for every spawn.")
end

------------------------------------------------------------------------
-- Waypoints and hunt routes
--
-- Waypoints build a route: clicking teachers adds stops, Hunt Planner's
-- "Waypoints" starts a new route. Stops are ordered nearest-first from
-- where you stand. TomTom (if installed) gets one waypoint per stop;
-- otherwise a built-in marker (world map + minimap edge) points at the
-- current stop and moves on when you arrive. Numbered pins and lines
-- show the route on the world map, which can open on the first stop.
------------------------------------------------------------------------
Geo.uids = {}
Geo.route = {}       -- ordered stops: { map=, x=, y=, label= }
Geo.current = 0      -- index of the stop you're heading to

local HBD, HBDPins
local REF = "BeastTrainingTrackerKuro"
local REF_TARGET = "BeastTrainingTrackerKuroTarget"
local REF_ROUTE = "BeastTrainingTrackerKuroRoute"
local tWorld, tMini  -- built-in marker pins
local stopPins = {}  -- numbered route pins

local function Libs()
  HBD = HBD or (LibStub and LibStub("HereBeDragons-2.0", true))
  HBDPins = HBDPins or (LibStub and LibStub("HereBeDragons-Pins-2.0", true))
  return HBDPins
end

local function Opt(key) return ns.db and ns.db.opts[key] end

-- What a route stop is for: the ranks its beast teaches that you still need,
-- and the special pet it is (if untamed). Stops with neither are kept as-is.
function Geo.MakeStop(spot, label, beast, manual)
  local stop = { map = spot.map, x = spot.x, y = spot.y, label = label, beast = beast, manual = manual, teaches = {} }
  for _, e in ipairs(beast and ns.teacherIndex[beast] or {}) do
    if not ns.IsKnown(e.ab, e.rank.rank) then
      stop.teaches[#stop.teaches + 1] = { ab = e.ab, rank = e.rank }
    end
  end
  if beast and ns.rarePetByName and ns.rarePetByName[beast] and not (ns.db and ns.db.tamedRares[beast]) then
    stop.pet = beast
  end
  return stop
end

local function StopKeys(s)
  local keys = {}
  for _, e in ipairs(s.teaches or {}) do keys[#keys + 1] = ns.Key(e.ab.name, e.rank.rank) end
  return keys
end

-- Nearest-neighbour order, starting from the player. A stop is only added
-- if it teaches something no earlier stop covers (one mob per ability);
-- clicked stops, special pets and plain stops are always kept.
function Geo.OrderStops(stops)
  local pm, px, py = PlayerPos()
  local left, out, covered = {}, {}, {}
  for i, s in ipairs(stops) do left[i] = s end

  local function Useful(s)
    if s.manual or s.pet or not s.teaches or #s.teaches == 0 then return true end
    for _, k in ipairs(StopKeys(s)) do
      if not covered[k] then return true end
    end
    return false
  end

  local cm, cx, cy = pm, px, py
  while #left > 0 do
    -- drop stops that are already covered by the route so far
    for i = #left, 1, -1 do
      if not Useful(left[i]) then table.remove(left, i) end
    end
    if #left == 0 then break end
    local bi, bd
    for i, s in ipairs(left) do
      local d = (cm and cx and s.map == cm) and ((s.x - cx) ^ 2 + (s.y - cy) ^ 2) or (10 + i * 0.001)
      if not bd or d < bd then bi, bd = i, d end
    end
    local s = table.remove(left, bi)
    out[#out + 1] = s
    for _, k in ipairs(StopKeys(s)) do covered[k] = true end
    cm, cx, cy = s.map, s.x, s.y
  end
  return out
end

local function MarkerPin(size, onClick)
  local p = CreateFrame("Button", nil, UIParent)
  p:SetSize(size, size)
  p.border = p:CreateTexture(nil, "BACKGROUND")
  p.border:SetPoint("TOPLEFT", -2, 2)
  p.border:SetPoint("BOTTOMRIGHT", 2, -2)
  p.border:SetColorTexture(1, 0.82, 0, 1)
  p.tex = p:CreateTexture(nil, "ARTWORK")
  p.tex:SetAllPoints()
  p.tex:SetTexture("Interface\\Icons\\Ability_Hunter_BeastTaming")
  p.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  p.num = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  p.num:SetPoint("CENTER", 0, 0)
  p.num:SetTextColor(1, 1, 1)
  p.num:SetShadowOffset(1, -1)
  p:RegisterForClicks("AnyUp")
  p:SetScript("OnEnter", function(self)
    local s = self.stop
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(s and s.label or "Waypoint", 1, 0.82, 0)
    if s and s.index then
      GameTooltip:AddLine(("Stop %d of %d"):format(s.index, #Geo.route), 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine("Click to remove this stop", 0.5, 0.5, 0.5)
    GameTooltip:Show()
  end)
  p:SetScript("OnLeave", GameTooltip_Hide)
  p:SetScript("OnClick", onClick)
  return p
end

------------------------------------------------------------------------
-- Route lines on the world map
------------------------------------------------------------------------
local mapInfo  -- "Beast hunt: stop 1 of 3 [Clear]" box on the world map
local REF_DOTS = "BeastTrainingTrackerKuroRouteDots"
local dotPool, dotUsed = {}, {}

-- Route line color + opacity (Settings). Default: bright cyan, stands out on every map.
Geo.ROUTE_DEFAULT = { r = 0.1, g = 0.85, b = 1.0, a = 0.9 }
function Geo.RouteColor()
  local o = ns.db and ns.db.opts or {}
  local c = o.routeColor or Geo.ROUTE_DEFAULT
  return c.r, c.g, c.b, o.routeAlpha or Geo.ROUTE_DEFAULT.a
end

local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

-- clip a texture to a circle (falls back to a square if masks aren't supported)
local function Round(frame, tex)
  if not frame.CreateMaskTexture or not tex.AddMaskTexture then return end
  local m = frame:CreateMaskTexture()
  m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  m:SetAllPoints(tex)
  tex:AddMaskTexture(m)
end

local function Dot()
  local d = table.remove(dotPool)
  if d then return d end
  d = CreateFrame("Frame", nil, UIParent)
  d:SetSize(5, 5)
  -- dark outline so the dot stays visible on any map color
  d.edge = d:CreateTexture(nil, "BACKGROUND")
  d.edge:SetPoint("TOPLEFT", -1, 1)
  d.edge:SetPoint("BOTTOMRIGHT", 1, -1)
  d.edge:SetColorTexture(0, 0, 0, 1)
  Round(d, d.edge)
  d.tex = d:CreateTexture(nil, "ARTWORK")
  d.tex:SetAllPoints()
  Round(d, d.tex)
  return d
end
local function PlaceDot(r, g, b, a, add)
  local d = Dot()
  d.tex:SetColorTexture(r, g, b, 1)
  d.edge:SetAlpha(0.6)
  d:SetAlpha(a)
  add(d)
  dotUsed[#dotUsed + 1] = d
end

-- Dotted line between stops, drawn as small map pins placed by
-- HereBeDragons (the same way as the numbered stop pins).
-- Dotted line between stops, evenly spaced on screen like a journey plotter:
-- recalculated for the map you're looking at and its zoom, so the gaps
-- stay the same size zoomed in or out.
local DOT_GAP = 14 -- pixels between dots on screen

local function ClearDots()
  if Libs() then HBDPins:RemoveAllWorldMapIcons(REF_DOTS) end
  for _, d in ipairs(dotUsed) do d:Hide(); dotPool[#dotPool + 1] = d end
  wipe(dotUsed)
end

function Geo.DrawRoute()
  if mapInfo then
    mapInfo:SetShown(#Geo.route > 0)
    mapInfo.text:SetText(("|cffabd473Beast hunt:|r %d stop%s"):format(#Geo.route, #Geo.route == 1 and "" or "s"))
    mapInfo:SetWidth(mapInfo.text:GetStringWidth() + 90)
  end

  ClearDots()
  if not Libs() or not HBD or #Geo.route < 2 or Opt("routeLines") == false then return end
  if not (WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame.GetMapID) then return end
  local mapID = WorldMapFrame:GetMapID()
  local canvas = WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
  if not mapID or not canvas then return end
  -- screen pixels across the whole displayed map
  local w = canvas:GetWidth() * (canvas:GetScale() or 1)
  local h = canvas:GetHeight() * (canvas:GetScale() or 1)
  if not w or w <= 0 or not h or h <= 0 then return end

  -- every stop in the displayed map's coordinates
  local pts = {}
  for i, s in ipairs(Geo.route) do
    if s.map == mapID then
      pts[i] = { s.x, s.y }
    else
      local x, y = HBD:TranslateZoneCoordinates(s.x, s.y, s.map, mapID, true)
      if x and y then pts[i] = { x, y } end
    end
  end

  local r, g, b, a = Geo.RouteColor()
  for i = 2, #Geo.route do
    local p1, p2 = pts[i - 1], pts[i]
    if p1 and p2 then
      local px = math.sqrt(((p2[1] - p1[1]) * w) ^ 2 + ((p2[2] - p1[2]) * h) ^ 2)
      local n = math.floor(px / DOT_GAP)
      for k = 1, n - 1 do -- skip the ends, the numbered stops sit there
        local t = k / n
        local x, y = p1[1] + (p2[1] - p1[1]) * t, p1[2] + (p2[2] - p1[2]) * t
        if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
          PlaceDot(r, g, b, a, function(d) HBDPins:AddWorldMapIconMap(REF_DOTS, d, mapID, x, y, 0) end)
        end
      end
    end
  end
end

-- Redraw after map changes / zooming, at most a few times a second
local redrawQueued
function Geo.QueueRouteRedraw()
  if redrawQueued or #Geo.route < 2 then return end
  redrawQueued = true
  C_Timer.After(0.3, function() redrawQueued = false; Geo.DrawRoute() end)
end

local hooked
local worldUsed -- forward: the world-map pins currently placed (set up in the pin section)
local stableWorldUsed -- forward: stable-master world-map pins (stable pin section)

-- World-map pins grow with zoom: 1x fully zoomed out, opts.pinZoomGrow x
-- fully zoomed in. Our icon is a child of HereBeDragons' pin frame, so
-- SetScale here stacks on the small 1.0-1.2x Blizzard already applies.
function Geo.ApplyPinZoom()
  if not worldUsed or not WorldMapFrame or not WorldMapFrame.ScrollContainer then return end
  local sc = WorldMapFrame.ScrollContainer
  local grow = (ns.db and ns.db.opts.pinZoomGrow) or 1
  local scale = 1
  if grow ~= 1 and sc.GetCanvasScale and sc.GetScaleForMinZoom and sc.GetScaleForMaxZoom then
    -- Blizzard fills in sc.zoomLevels only once the map has been opened and
    -- laid out; before that GetScaleForMinZoom() errors out. pcall it, and
    -- leave pins at 1x if the map hasn't been shown yet.
    local okC, cur = pcall(sc.GetCanvasScale, sc)
    local okL, lo = pcall(sc.GetScaleForMinZoom, sc)
    local okH, hi = pcall(sc.GetScaleForMaxZoom, sc)
    if okC and okL and okH and type(cur) == "number" and type(lo) == "number" and type(hi) == "number" and hi > lo then
      local t = math.max(0, math.min(1, (cur - lo) / (hi - lo)))
      scale = 1 + t * (grow - 1)
    end
  end
  for _, p in ipairs(worldUsed) do p:SetScale(scale) end
  -- stable pins keep a fixed screen size: city maps (Darnassus, Ironforge)
  -- have a zoom range that made them shrink to a few pixels
  for _, p in ipairs(stableWorldUsed or {}) do p:SetScale(1) end
end

local function HookWorldMap()
  if hooked or not WorldMapFrame then return end
  hooked = true
  WorldMapFrame:HookScript("OnShow", function() Geo.DrawRoute(); Geo.ApplyPinZoom() end)
  if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() Geo.QueueRouteRedraw(); Geo.ApplyPinZoom() end) end
  if WorldMapFrame.OnCanvasScaleChanged then
    hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", function() Geo.QueueRouteRedraw(); Geo.ApplyPinZoom() end)
  end
  if WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.HookScript then
    WorldMapFrame.ScrollContainer:HookScript("OnMouseWheel", Geo.QueueRouteRedraw)
  end

  local parent = WorldMapFrame.ScrollContainer or WorldMapFrame
  mapInfo = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  mapInfo:SetSize(220, 26)
  mapInfo:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 8, 8) -- other addons crowd the top-left corner
  mapInfo:SetFrameLevel(parent:GetFrameLevel() + 50)
  if mapInfo.SetBackdrop then
    mapInfo:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    mapInfo:SetBackdropColor(0, 0, 0, 0.75)
  end
  mapInfo.text = mapInfo:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  mapInfo.text:SetPoint("LEFT", 8, 0)
  local clear = CreateFrame("Button", nil, mapInfo, "UIPanelButtonTemplate")
  clear:SetSize(70, 18)
  clear:SetPoint("RIGHT", -4, 0)
  clear:SetText("Clear")
  clear:SetScript("OnClick", function() Geo.ClearWaypoints() end)
  mapInfo:Hide()
end
Geo.HookWorldMap = HookWorldMap

-- Open the world map on a stop (skipped in combat or if turned off)
local function ShowOnMap(map)
  if not WorldMapFrame or Opt("routeOpenMap") == false then return end
  if InCombatLockdown and InCombatLockdown() then return end
  if OpenWorldMap then
    pcall(OpenWorldMap, map)
  else
    if not WorldMapFrame:IsShown() then
      if ToggleWorldMap then pcall(ToggleWorldMap) else pcall(ShowUIPanel, WorldMapFrame) end
    end
    if WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, map) end
  end
end

------------------------------------------------------------------------
-- Showing the route (TomTom waypoints or built-in marker + numbered pins)
------------------------------------------------------------------------
local function ClearShown()
  if TomTom and TomTom.RemoveWaypoint then
    for _, uid in ipairs(Geo.uids) do pcall(TomTom.RemoveWaypoint, TomTom, uid) end
  end
  wipe(Geo.uids)
  if Libs() then
    HBDPins:RemoveAllWorldMapIcons(REF_TARGET)
    HBDPins:RemoveAllMinimapIcons(REF_TARGET)
    HBDPins:RemoveAllWorldMapIcons(REF_ROUTE)
  end
  if Geo.blizzardWaypoint and C_Map and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
  Geo.blizzardWaypoint = nil
end

-- Point the built-in marker (and Blizzard's map pin) at one stop
local function PointAt(s)
  if Libs() then
    HBDPins:RemoveAllWorldMapIcons(REF_TARGET)
    HBDPins:RemoveAllMinimapIcons(REF_TARGET)
  end
  if Geo.blizzardWaypoint and C_Map and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
  Geo.blizzardWaypoint = nil
  if not s or Geo.HasTomTom() then return end
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    local can = not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(s.map)
    if can and pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(s.map, s.x, s.y)) then
      Geo.blizzardWaypoint = true
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
    end
  end
  if Libs() then
    tWorld = tWorld or MarkerPin(20, function(self) Geo.RemoveStop(self.stop) end)
    tMini = tMini or MarkerPin(16, function(self) Geo.RemoveStop(self.stop) end)
    tWorld.stop, tMini.stop = s, s
    tWorld.num:SetText(s.index or "")
    tMini.num:SetText("")
    HBDPins:AddWorldMapIconMap(REF_TARGET, tWorld, s.map, s.x, s.y, 3)
    -- floats on the minimap edge, so it points the way
    HBDPins:AddMinimapIconMap(REF_TARGET, tMini, s.map, s.x, s.y, true, true)
  end
end

local function ShowRoute()
  ClearShown()
  for i, s in ipairs(Geo.route) do s.index = i end
  if Geo.HasTomTom() then
    for _, s in ipairs(Geo.route) do
      local ok, uid = pcall(TomTom.AddWaypoint, TomTom, s.map, s.x, s.y, {
        title = s.label, persistent = false, minimap = true, world = true, from = "BeastTrainingTracker.Kuro",
      })
      if ok and uid then Geo.uids[#Geo.uids + 1] = uid end
    end
    if #Geo.uids > 1 and TomTom.SetClosestWaypoint then pcall(TomTom.SetClosestWaypoint, TomTom) end
  end
  -- numbered pins for every stop (the current one gets the gold marker)
  if Libs() and #Geo.route > 1 then
    for i, s in ipairs(Geo.route) do
      if i ~= Geo.current or Geo.HasTomTom() then
        local p = stopPins[i]
        if not p then
          p = MarkerPin(16, function(self) Geo.RemoveStop(self.stop) end)
          stopPins[i] = p
        end
        p.stop = s
        p.num:SetText(i)
        p.border:SetColorTexture(1, 0.82, 0, 1)
        HBDPins:AddWorldMapIconMap(REF_ROUTE, p, s.map, s.x, s.y, 3)
      end
    end
  end
  PointAt(Geo.route[Geo.current])
  Geo.DrawRoute()
end

-- Replace (or extend) the route. Returns the number of stops.
local function SetRoute(stops, append)
  local all = {}
  if append then
    for _, s in ipairs(Geo.route) do all[#all + 1] = s end
  end
  for _, s in ipairs(stops) do
    local dup
    for _, o in ipairs(all) do
      if o.map == s.map and (o.x - s.x) ^ 2 + (o.y - s.y) ^ 2 < 0.00005 then dup = o break end
    end
    if dup then
      -- same spot: keep one stop with both stops' reasons
      for _, e in ipairs(s.teaches or {}) do
        dup.teaches = dup.teaches or {}
        dup.teaches[#dup.teaches + 1] = e
      end
      dup.pet = dup.pet or s.pet
      dup.manual = dup.manual or s.manual
    else
      all[#all + 1] = s
    end
  end
  Geo.route = Geo.OrderStops(all)
  Geo.current = #Geo.route > 0 and 1 or 0
  ShowRoute()
  if Geo.route[1] then ShowOnMap(Geo.route[1].map) end
  if ns.Refresh then ns.Refresh() end
  return #Geo.route
end

function Geo.RemoveStop(stop)
  for i, s in ipairs(Geo.route) do
    if s == stop then
      table.remove(Geo.route, i)
      if Geo.current > i then Geo.current = Geo.current - 1 end
      if Geo.current > #Geo.route then Geo.current = #Geo.route end
      if #Geo.route == 0 then Geo.ClearWaypoints() return end
      ShowRoute()
      ns.Say(("removed %s from the route."):format(stop.label))
      return
    end
  end
end

-- Arrival: move on to the next stop
local arrive = CreateFrame("Frame")
local arriveElapsed = 0
arrive:SetScript("OnUpdate", function(_, elapsed)
  arriveElapsed = arriveElapsed + (elapsed or 0)
  if arriveElapsed < 1 or Geo.current < 1 then return end
  arriveElapsed = 0
  local s = Geo.route[Geo.current]
  if not s or not HBD then return end
  local x, y, m = HBD:GetPlayerZonePosition()
  if not (x and m) then return end
  local d = HBD:GetZoneDistance(m, x, y, s.map, s.x, s.y)
  if d and d < 25 then
    if Geo.current >= #Geo.route then
      ns.Say(("arrived at %s - hunt route complete."):format(s.label))
      Geo.ClearWaypoints(true)
    else
      Geo.current = Geo.current + 1
      local nxt = Geo.route[Geo.current]
      ns.Say(("arrived at %s. Next: %s (stop %d of %d)."):format(s.label, nxt.label, Geo.current, #Geo.route))
      ShowRoute()
    end
  end
end)

------------------------------------------------------------------------
-- Public waypoint API
------------------------------------------------------------------------
-- One beast: added to the current route
function Geo.Waypoint(t, label, quiet)
  local s, suffix, why = Geo.Destination(t)
  if not s then
    if not quiet then ns.Say(why) end
    return
  end
  label = (label or t.name) .. (suffix or "")
  local n = SetRoute({ Geo.MakeStop(s, label, t.name, true) }, true)
  if not quiet then
    ns.Say(("waypoint set: %s (%.0f, %.0f)%s%s"):format(label, s.x * 100, s.y * 100,
      n > 1 and (" - route now has %d stops"):format(n) or "",
      Geo.HasTomTom() and "" or " - follow the marker on your minimap edge"))
  end
  return true
end

-- Several beasts: a new route through all of them
function Geo.WaypointMany(list)
  local stops, noSpot, seenName = {}, {}, {}
  for _, item in ipairs(list) do
    local s, suffix = Geo.Destination(item.t)
    if s then
      stops[#stops + 1] = Geo.MakeStop(s, (item.label or item.t.name) .. (suffix or ""), item.t.name)
    elseif not seenName[item.t.name] then
      seenName[item.t.name] = true
      noSpot[#noSpot + 1] = item.t.name
    end
  end
  if #stops == 0 then
    ns.Say("no locations known yet for those beasts.")
    return 0
  end
  local n = SetRoute(stops, false)
  ns.Say(("hunt route set: %d stop%s, nearest first%s."):format(n, n == 1 and "" or "s",
    Geo.HasTomTom() and " (TomTom waypoints added)" or " - follow the marker on your minimap edge"))
  -- say what was left out, so a missing beast is never a mystery
  local covered = 0
  for _, s in ipairs(stops) do
    local kept = false
    for _, r in ipairs(Geo.route) do if r == s then kept = true break end end
    if not kept then covered = covered + 1 end
  end
  if covered > 0 then
    ns.Say(("  %d beast%s left out: another stop already teaches the same rank."):format(covered, covered == 1 and "" or "s"))
  end
  if #noSpot > 0 then
    ns.Say(("  no location known for: %s."):format(table.concat(noSpot, ", ")))
  end
  if not Geo.HasQuestie() then
    ns.Say("  |cffff9040Questie isn't installed, so this route only includes beasts you've spotted yourself - some may be missing.|r")
  end
  return n
end

-- A stable master (StableMasters.lua entry { name=, map=, x=, y= }): added to
-- the current route as a manual stop, so OrderStops / PruneRoute keep it.
function Geo.WaypointStable(e, quiet)
  if not (e and e.map and e.x and e.y) then return end
  local label = e.name .. " - Stable Master"
  local n = SetRoute({ Geo.MakeStop({ map = e.map, x = e.x, y = e.y }, label, nil, true) }, true)
  if not quiet then
    ns.Say(("waypoint set: %s (%.0f, %.0f)%s%s"):format(label, e.x * 100, e.y * 100,
      n > 1 and (" - route now has %d stops"):format(n) or "",
      Geo.HasTomTom() and "" or " - follow the marker on your minimap edge"))
  end
  return true
end

function Geo.ClearWaypoints(quiet)
  local n = #Geo.route
  ClearShown()
  wipe(Geo.route)
  Geo.current = 0
  Geo.DrawRoute()
  if ns.Refresh then ns.Refresh() end
  if not quiet then ns.Say(("cleared %d waypoint%s."):format(n, n == 1 and "" or "s")) end
end

function Geo.HasRoute() return #Geo.route > 0 end

-- Drop stops you no longer need: everything they teach is now learned
-- (or covered by a higher rank), or the special pet has been tamed.
local function StillNeeded(s)
  local hasReason = s.pet or (s.teaches and #s.teaches > 0)
  if not hasReason then return true end -- a plain stop: nothing to check, keep it
  if s.pet and not (ns.db and ns.db.tamedRares[s.pet]) then return true end
  for _, e in ipairs(s.teaches or {}) do
    if not ns.IsKnown(e.ab, e.rank.rank) then return true end
  end
  return false
end

function Geo.PruneRoute()
  if #Geo.route == 0 then return 0 end
  local removed = {}
  for i = #Geo.route, 1, -1 do
    local s = Geo.route[i]
    if not StillNeeded(s) then
      table.insert(removed, 1, s.label)
      table.remove(Geo.route, i)
      if Geo.current > i then Geo.current = Geo.current - 1 end
    end
  end
  if #removed == 0 then return 0 end
  if #Geo.route == 0 then
    Geo.ClearWaypoints(true)
    ns.Say("hunt route complete - you've got everything on it.")
    return #removed
  end
  Geo.current = math.max(1, math.min(Geo.current, #Geo.route))
  ShowRoute()
  ns.Say(("route updated: removed %s (no longer needed)."):format(table.concat(removed, ", ")))
  return #removed
end

-- Label used for waypoints and pins
function Geo.Label(ab, r, t) return ("%s - %s %d"):format(t.name, ab.name, r.rank) end

------------------------------------------------------------------------
-- Map pins (HereBeDragons, bundled)
------------------------------------------------------------------------
local worldPool, miniPool = {}, {}
worldUsed = {} -- declared above HookWorldMap so Geo.ApplyPinZoom can see it
local miniUsed = {}
local MAX_WORLD, MAX_PER_TEACHER, MAX_MINI = 900, 25, 120

local SRC_TEXT = { questie = "Questie", seen = "your sightings", rarescanner = "RareScanner", rare = "rare data" }

local function PinEnter(self)
  local tip = GameTooltip
  tip:SetOwner(self, "ANCHOR_RIGHT")
  local d = self.data
  tip:AddLine(d.t.name .. Geo.Tag(d.t.name), 1, 0.82, 0)
  tip:AddLine(("%s, level %s"):format(d.t.family or "?", d.t.level or "?"), 0.8, 0.8, 0.8)
  local st = ns.RS and ns.RS.Status(d.t.name)
  if st then tip:AddLine("RareScanner: " .. st.text, 1, 0.6, 0.25, true) end
  for _, e in ipairs(d.teaches) do
    tip:AddLine(("Teaches %s %d"):format(e.ab.name, e.rank.rank), 0.25, 1, 0.25)
  end
  if d.rareOnly then
    tip:AddLine("Untamed special pet for your collection", 1, 0.5, 0)
    local info = ns.RS and ns.RS.Info(d.t.name)
    if info then
      tip:AddLine("Attack speed " .. ns.RS.SpeedText(info.speed), 0.8, 0.8, 0.8)
      for _, tr in ipairs(info.traits) do if tr.short ~= "" then tip:AddLine(tr.short, 1, 1, 1) end end
    end
  end
  if self.src and SRC_TEXT[self.src] then tip:AddLine("Location from " .. SRC_TEXT[self.src], 0.5, 0.5, 0.5) end
  tip:AddLine(" ")
  tip:AddLine("Click: waypoint", 0.5, 0.5, 0.5)
  tip:Show()
end

local function NewPin(pool)
  local p = table.remove(pool)
  if p then return p end
  p = CreateFrame("Button", nil, UIParent)
  p.border = p:CreateTexture(nil, "BACKGROUND")
  p.border:SetPoint("TOPLEFT", -1, 1)
  p.border:SetPoint("BOTTOMRIGHT", 1, -1)
  p.tex = p:CreateTexture(nil, "ARTWORK")
  p.tex:SetAllPoints()
  p.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  p:RegisterForClicks("AnyUp")
  p:SetScript("OnEnter", PinEnter)
  p:SetScript("OnLeave", GameTooltip_Hide)
  p:SetScript("OnClick", function(self)
    local d = self.data
    local e = d.teaches[1]
    Geo.Waypoint(d.t, e and Geo.Label(e.ab, e.rank, d.t) or d.t.name)
  end)
  return p
end

local function StylePin(p, d, s, icon, rare, size)
  p:SetSize(size, size)
  -- orange border = rare, blue = a spot you saw yourself, black = normal
  if rare then
    p.border:SetColorTexture(1, 0.5, 0, 0.95)
  elseif s.src == "seen" then
    p.border:SetColorTexture(0.25, 0.6, 1, 0.95)
  else
    p.border:SetColorTexture(0, 0, 0, 0.85)
  end
  p.tex:SetTexture(icon)
  p.data, p.src = d, s.src
end

local function ClearPins()
  if not Libs() then return end
  HBDPins:RemoveAllWorldMapIcons(REF)
  HBDPins:RemoveAllMinimapIcons(REF)
  for _, p in ipairs(worldUsed) do p:Hide(); worldPool[#worldPool + 1] = p end
  for _, p in ipairs(miniUsed) do p:Hide(); miniPool[#miniPool + 1] = p end
  wipe(worldUsed); wipe(miniUsed)
end

-- teacher name -> { t=, teaches={ {ab, rank} } } for every missing rank you can tame now
local function TeachersToPin()
  local o = ns.db.opts
  local out = {}
  for _, z in ipairs(ns.HuntPlan(o.huntPetOnly, o.huntDungeons)) do
    for _, e in ipairs(z.entries) do
      for _, t in ipairs(e.teachers) do
        local d = out[t.name]
        if not d then d = { t = t, teaches = {} }; out[t.name] = d end
        d.teaches[#d.teaches + 1] = e
      end
    end
  end
  -- untamed special pets you can tame, even if they teach nothing you need
  if o.rarePins and ns.RS then
    for _, p in ipairs(ns.rarePets or {}) do
      if not out[p.name] and not ns.db.tamedRares[p.name] and ns.CanTame(p) and (p.rare or not p.dungeon) then
        out[p.name] = { t = p, teaches = {}, rareOnly = true }
      end
    end
  end
  return out
end

-- Squared distance between two points on the same map
local function Dist2(ax, ay, bx, by) return (ax - bx) ^ 2 + (ay - by) ^ 2 end

-- Per map, the one spawn to pin for a group of candidates { s=, d=, icon=, rare= }:
-- closest to you on the map you're standing on, closest to the group's
-- centre everywhere else (so "nearest" means something on other maps too).
local function OneSpawnPerMap(cands, pm, px, py)
  local byMap = {}
  for _, c in ipairs(cands) do
    local list = byMap[c.s.map]
    if not list then list = {}; byMap[c.s.map] = list end
    list[#list + 1] = c
  end
  local out = {}
  for map, list in pairs(byMap) do
    local cx, cy
    if map == pm and px then
      cx, cy = px, py
    else
      cx, cy = 0, 0
      for _, c in ipairs(list) do cx, cy = cx + c.s.x, cy + c.s.y end
      cx, cy = cx / #list, cy / #list
    end
    local best, bd
    for _, c in ipairs(list) do
      local d = Dist2(c.s.x, c.s.y, cx, cy)
      if not bd or d < bd then best, bd = c, d end
    end
    out[#out + 1] = best
  end
  return out
end

-- Every world-map pin to draw, as { s=, d=, icon=, rare= }, by mode (opts.mapPinMode / opts.minimapPinMode):
--   all      every spawn point (thinned to MAX_PER_TEACHER per beast)
--   nearest  one pin per beast per map
--   ability  one pin per ability per map (the closest beast that teaches it)
local function ChoosePins(teachers, mode, pm, px, py)
  local out = {}
  local groups = {} -- key -> { cands = {} }
  local function Group(key)
    local g = groups[key]
    if not g then g = { cands = {} }; groups[key] = g end
    return g
  end

  for name, d in pairs(teachers) do
    local info = Geo.Lookup(name)
    if info and #info.spawns > 0 then
      local rare = Geo.IsRare(name)
      local icon = d.teaches[1] and d.teaches[1].ab.icon
        or (ns.RS and ns.RS.Info(name) and ns.RS.Info(name).icon) or "Interface\\Icons\\Ability_Hunter_BeastTaming"
      if mode == "all" then
        local step = math.max(1, math.floor(#info.spawns / MAX_PER_TEACHER))
        for i = 1, #info.spawns, step do
          out[#out + 1] = { s = info.spawns[i], d = d, icon = icon, rare = rare }
        end
      elseif mode == "ability" and #d.teaches > 0 then
        -- the same beast is a candidate for every ability it teaches
        for _, e in ipairs(d.teaches) do
          local g = Group(e.ab.name)
          for _, s in ipairs(info.spawns) do g.cands[#g.cands + 1] = { s = s, d = d, icon = e.ab.icon, rare = rare } end
        end
      else
        -- "nearest", or a special pet that teaches nothing: one group per beast
        local g = Group(name)
        for _, s in ipairs(info.spawns) do g.cands[#g.cands + 1] = { s = s, d = d, icon = icon, rare = rare } end
      end
    end
  end

  if mode ~= "all" then
    local seen = {} -- same beast at the same spot picked by two abilities: pin it once
    for _, g in pairs(groups) do
      for _, c in ipairs(OneSpawnPerMap(g.cands, pm, px, py)) do
        local k = c.d.t.name .. "|" .. tostring(c.s.map) .. "|" .. c.s.x .. "|" .. c.s.y
        if not seen[k] then
          seen[k] = true
          out[#out + 1] = c
        end
      end
    end
  end
  return out
end

function Geo.UpdatePins()
  if not ns.db or not Libs() or not ns.Active() then return end
  ClearPins()
  local o = ns.db.opts
  local mapMode, miniMode = o.mapPinMode or "ability", o.minimapPinMode or "ability"
  if o.pinsOff or (mapMode == "none" and miniMode == "none") then return end

  local pm, px, py = PlayerPos()
  local size, alpha = o.pinSize or 4, o.pinAlpha or 1
  local teachers = TeachersToPin()

  if mapMode ~= "none" then
    local chosen = ChoosePins(teachers, mapMode, pm, px, py)
    for i = 1, math.min(MAX_WORLD, #chosen) do
      local c = chosen[i]
      local p = NewPin(worldPool)
      StylePin(p, c.d, c.s, c.icon, c.rare, c.rare and math.floor(size * 1.33 + 0.5) or size)
      p:SetAlpha(alpha)
      HBDPins:AddWorldMapIconMap(REF, p, c.s.map, c.s.x, c.s.y, 0)
      worldUsed[#worldUsed + 1] = p
    end
    Geo.ApplyPinZoom()
  end

  -- Minimap: its own selection, those on your map, nearest first
  if miniMode ~= "none" and pm then
    local chosen = ChoosePins(teachers, miniMode, pm, px, py)
    local nearby = {}
    for _, c in ipairs(chosen) do
      if c.s.map == pm then
        c.dist = px and Dist2(c.s.x, c.s.y, px, py) or 0
        nearby[#nearby + 1] = c
      end
    end
    table.sort(nearby, function(a, b) return a.dist < b.dist end)
    local msize = math.max(6, math.floor(size * 0.85 + 0.5))
    for i = 1, math.min(MAX_MINI, #nearby) do
      local c = nearby[i]
      local p = NewPin(miniPool)
      StylePin(p, c.d, c.s, c.icon, c.rare, c.rare and math.floor(msize * 1.33 + 0.5) or msize)
      p:SetAlpha(alpha)
      HBDPins:AddMinimapIconMap(REF, p, c.s.map, c.s.x, c.s.y, false, false)
      miniUsed[#miniUsed + 1] = p
    end
  end
  Geo.UpdateStablePins()
end

------------------------------------------------------------------------
-- Stable master pins (StableMasters.lua supplies the data)
--
-- Own HBD ref and pools so beast-pin rebuilds never churn these. World map
-- on every flavour; minimap only where the Client says so (Era has no native
-- stable-master tracking, Forever does).
------------------------------------------------------------------------
local REF_STABLE = "BeastTrainingTrackerKuroStable"
local stablePool, stableMiniUsed = {}, {}
stableWorldUsed = {} -- declared above HookWorldMap so Geo.ApplyPinZoom can see it
local STABLE_BORDER = { 0.9, 0.75, 0.45, 0.95 } -- tan: "service", not "beast"

local function StablePinEnter(self)
  local e = self.stable
  local tip = GameTooltip
  tip:SetOwner(self, "ANCHOR_RIGHT")
  tip:AddLine(e.name, 1, 0.82, 0)
  tip:AddLine("Stable Master", 0.8, 0.8, 0.8)
  local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(e.map)
  if info and info.name then tip:AddLine(("%s (%.0f, %.0f)"):format(info.name, e.x * 100, e.y * 100), 0.6, 0.6, 0.6) end
  tip:AddLine("Location from Questie", 0.5, 0.5, 0.5)
  tip:AddLine(" ")
  tip:AddLine("Click: waypoint", 0.5, 0.5, 0.5)
  tip:Show()
end

local function NewStablePin()
  local p = table.remove(stablePool)
  if p then return p end
  p = CreateFrame("Button", nil, UIParent)
  -- a thin, mostly transparent ring instead of a solid square: the stable
  -- icon has its own shape and reads better without a box around it
  p.border = p:CreateTexture(nil, "BACKGROUND")
  p.border:SetPoint("TOPLEFT", -1, 1)
  p.border:SetPoint("BOTTOMRIGHT", 1, -1)
  p.border:SetColorTexture(STABLE_BORDER[1], STABLE_BORDER[2], STABLE_BORDER[3], 0.25)
  p.tex = p:CreateTexture(nil, "ARTWORK")
  p.tex:SetAllPoints()
  p.tex:SetTexture(ns.Client.STABLE_MASTER_ICON)
  p:RegisterForClicks("AnyUp")
  p:SetScript("OnEnter", StablePinEnter)
  p:SetScript("OnLeave", GameTooltip_Hide)
  p:SetScript("OnClick", function(self) Geo.WaypointStable(self.stable) end)
  return p
end

local function ClearStablePins()
  if not Libs() then return end
  HBDPins:RemoveAllWorldMapIcons(REF_STABLE)
  HBDPins:RemoveAllMinimapIcons(REF_STABLE)
  for _, p in ipairs(stableWorldUsed) do p:Hide(); stablePool[#stablePool + 1] = p end
  for _, p in ipairs(stableMiniUsed) do p:Hide(); stablePool[#stablePool + 1] = p end
  wipe(stableWorldUsed); wipe(stableMiniUsed)
end
Geo.ClearStablePins = ClearStablePins

-- Stable icons need to stay legible: at least 10 px, and 1.33x the beast pin size like rares.
local function StablePinSize(base) return math.max(10, math.floor(base * 1.33 + 0.5)) end

function Geo.UpdateStablePins()
  ClearStablePins()
  local St = ns.Stables
  if not (ns.db and Libs() and ns.Active() and St and St.ready) then return end
  local o = ns.db.opts
  if o.pinsOff or o.stablePins == false then return end
  local size, alpha = StablePinSize(o.pinSize or 4), o.pinAlpha or 1
  local pm = PlayerPos()
  local wantMini = ns.Client.StableMasterMinimapPinsWanted() and pm ~= nil

  for _, e in ipairs(St.list) do
    local p = NewStablePin()
    p:SetSize(size, size)
    p:SetAlpha(alpha)
    p.stable = e
    -- SHOW_PARENT: a city stable master (Darnassus) also shows on the zone
    -- that contains the city (Teldrassil), the way Blizzard's own inn /
    -- mailbox POIs do. Beast pins stay on their own map only.
    HBDPins:AddWorldMapIconMap(REF_STABLE, p, e.map, e.x, e.y, HBD_PINS_WORLDMAP_SHOW_PARENT or 1)
    stableWorldUsed[#stableWorldUsed + 1] = p
    if wantMini and e.map == pm then
      local m = NewStablePin()
      m:SetSize(math.max(10, math.floor(size * 0.85 + 0.5)), math.max(10, math.floor(size * 0.85 + 0.5)))
      m:SetAlpha(alpha)
      m.stable = e
      HBDPins:AddMinimapIconMap(REF_STABLE, m, e.map, e.x, e.y, false, false)
      stableMiniUsed[#stableMiniUsed + 1] = m
    end
  end
  Geo.ApplyPinZoom()
end

-- Rebuild pins only when something that affects them changed
local lastSig
local queued
function Geo.QueuePins(force)
  if not ns.db then return end
  if not ns.Active() then
    -- hunter-only mode on another class: nothing on the map, ever
    lastSig = nil
    ClearPins()
    return
  end
  local o = ns.db.opts
  local sig = table.concat({ ns.learnedSerial or 0, ns.PlayerLevel(), ns.CurrentZone(), tostring(o.mapPinMode),
    tostring(o.minimapPinMode), tostring(o.huntPetOnly), tostring(o.huntDungeons), tostring(Geo.ready), ns.PetFamily() or "",
    tostring(o.pinsOff), tostring(o.rarePins), tostring(ns.tamedSerial or 0), tostring(ns.seenSerial or 0),
    tostring(o.pinSize), tostring(o.pinAlpha), tostring(o.pinZoomGrow),
    tostring(o.stablePins), tostring(ns.Stables and ns.Stables.ready) }, "|")
  if sig == lastSig and not force then return end
  lastSig = sig
  if queued then return end
  queued = true
  C_Timer.After(1, function() queued = false; Geo.UpdatePins() end)
end

-- after learning a rank or taming a pet, drop route stops you no longer need
local lastPruneSig

-- Hunter-only mode switched on (or login on another class): take every
-- pin, waypoint and route line off the map.
ns.OnDeactivate(function()
  lastSig = nil
  ClearPins()
  ClearStablePins()
  if #Geo.route > 0 then Geo.ClearWaypoints(true) end
  ClearDots()
end)

ns.OnRefresh(function()
  Geo.QueuePins()
  local sig = (ns.learnedSerial or 0) .. ":" .. (ns.tamedSerial or 0)
  if sig ~= lastPruneSig then
    lastPruneSig = sig
    Geo.PruneRoute()
  end
end)

-- Master on/off for every beast pin (minimap button right-click)
function Geo.TogglePins()
  local o = ns.db.opts
  o.pinsOff = not o.pinsOff
  ns.Say("beast pins on the map " .. (o.pinsOff and "|cffff4040hidden|r" or "|cff40ff40shown|r"))
  Geo.QueuePins(true)
  ns.Refresh()
end

------------------------------------------------------------------------
-- Status of optional addons (for the UI)
------------------------------------------------------------------------
-- { {name=, on=, text=}, ... }
function Geo.AddonStatus()
  local seen = Geo.SeenCount()
  local q
  if Geo.HasQuestie() then
    q = Geo.ready and ("Spawn locations for every beast (%d looked up so far)"):format(Geo.LocatedCount())
      or "Loading beast locations..."
    if ns.Stables and ns.Stables.ready then
      q = q .. (", %d stable masters"):format(ns.Stables.count or 0)
    end
  else
    q = ("Not detected - map pins use the %d beast%s you've spotted yourself. Install Questie for every spawn.")
      :format(seen, seen == 1 and "" or "s")
  end
  return {
    { name = "Questie", on = Geo.HasQuestie(), text = q },
    { name = "TomTom", on = Geo.HasTomTom(), text = Geo.HasTomTom() and "Waypoint arrows"
      or "Not detected - waypoints use a built-in map pin and minimap marker instead." },
    { name = "RareScanner", on = Geo.HasRareScanner(), text = Geo.HasRareScanner()
      and "Live rare timers and last-seen spots" or "Not detected - install it for live rare spawn timers." },
  }
end

function Geo.StatusText()
  local parts = {}
  for _, a in ipairs(Geo.AddonStatus()) do parts[#parts + 1] = a.name .. ": " .. a.text end
  return table.concat(parts, "  |  ")
end

------------------------------------------------------------------------
-- Startup
------------------------------------------------------------------------
ns.OnInit(function()
  BeastTrainingTrackerKuroSeen = BeastTrainingTrackerKuroSeen or {}
  Geo.seen = BeastTrainingTrackerKuroSeen
end)

ns.OnLogin(function()
  Libs()
  HookWorldMap()
  if not Geo.HasQuestie() then
    Geo.status = "Questie not installed"
    return
  end
  -- build QuestieDB's name index spread over several frames
  Geo.status = "loading beast locations..."
  local co = coroutine.create(function()
    if Npc().BuildNameIndexAsync then Npc().BuildNameIndexAsync(400) else Npc().BuildNameIndex() end
  end)
  local runner = CreateFrame("Frame")
  runner:SetScript("OnUpdate", function(self)
    local ok, err = coroutine.resume(co)
    if not ok then
      self:SetScript("OnUpdate", nil)
      Geo.status = "QuestieDB error: " .. tostring(err)
      return
    end
    if coroutine.status(co) == "dead" then
      self:SetScript("OnUpdate", nil)
      Geo.ready = true
      Geo.status = "ready"
      wipe(qcache)
      ns.Refresh()
    end
  end)
end)

local zev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "NAME_PLATE_UNIT_ADDED",
  "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT" }) do
  pcall(zev.RegisterEvent, zev, e)
end
zev:SetScript("OnEvent", function(_, e, unit)
  if not ns.Active() then return end -- hunter-only mode on another class
  if e == "ADDON_LOADED" then
    if unit == "Blizzard_WorldMap" then HookWorldMap() end
  elseif e == "NAME_PLATE_UNIT_ADDED" then
    if unit then Geo.RecordSighting(unit) end
  elseif e == "PLAYER_TARGET_CHANGED" then
    Geo.RecordSighting("target")
  elseif e == "UPDATE_MOUSEOVER_UNIT" then
    Geo.RecordSighting("mouseover")
  else
    Geo.QueuePins(true)
  end
end)
