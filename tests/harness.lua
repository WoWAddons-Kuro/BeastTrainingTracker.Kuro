-- Minimal fake WoW environment so the addon's logic files can load and run
-- under plain Lua 5.1. Only the API the logic files touch is stubbed; the UI
-- files (UI.lua, Tracker.lua, Alerts.lua) aren't loaded by the tests.
local H = {}

local LOGIC_FILES = {
  "Client/Client.lua", "Client/Client_Forever.lua", "Client/Client_ClassicEra.lua", "Client/Client_Select.lua",
  "Data.lua", "RarePets.lua", "RareIds.lua", "Core.lua", "Geo.lua", "Rares.lua",
}

------------------------------------------------------------------------
-- Fake frames: remember scripts and registered events, ignore the rest
------------------------------------------------------------------------
local frameMethods = {
  SetScript = function(self, name, fn) self.scripts[name] = fn end,
  GetScript = function(self, name) return self.scripts[name] end,
  HookScript = function(self, name, fn)
    local old = self.scripts[name]
    self.scripts[name] = function(...) if old then old(...) end fn(...) end
  end,
  RegisterEvent = function(self, e) self.events[e] = true end,
  UnregisterEvent = function(self, e) self.events[e] = nil end,
  UnregisterAllEvents = function(self) self.events = {} end,
  RegisterAllEvents = function() end, -- keep the debug frame quiet
}

local function NewFrame()
  local f = { scripts = {}, events = {} }
  return setmetatable(f, {
    __index = function(_, k) return frameMethods[k] or function() end end,
  })
end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
function H.deepcopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[H.deepcopy(k)] = H.deepcopy(x) end
  return out
end

-- WoW's strsplit(delimiter, text)
local function strsplit(delim, str)
  local out, start = {}, 1
  while true do
    local i = string.find(str, delim, start, true)
    if not i then
      out[#out + 1] = str:sub(start)
      break
    end
    out[#out + 1] = str:sub(start, i - 1)
    start = i + #delim
  end
  return unpack(out)
end

-- Fire an event at every fake frame registered for it
function H.fire(event, ...)
  for _, f in ipairs(H.frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

------------------------------------------------------------------------
-- H.load(opts): fresh globals + fresh addon. Returns the addon namespace.
--   opts.backup = BeastTrainingTrackerKuroBackup table to start with
--   opts.flavour = "classic_era" | "forever" (default) - which Client_*.lua is picked
------------------------------------------------------------------------
function H.load(opts)
  opts = opts or {}
  H.frames, H.printed = {}, {}
  H.clock = 1000
  -- game state the stubs read; tests change these
  H.state = {
    level = 10,
    zone = "Durotar",
    pet = nil,       -- { name=, family=, level=, guid=, spells = { {"Bite","Rank 2"}, ... } }
    trainer = nil,   -- { {"Bite","Rank 1","available"}, ... }
    units = {},      -- other units: units.target = { name = "Prairie Wolf" }
    faction = "Horde",
    playerGuid = "Player-1-0000ABCD",  -- the per-character SavedVariables key (BeastTrainingTrackerKuroBackup)
    playerSurname = nil,               -- set to e.g. "Oakheart" to simulate a Forever two-name character
  }
  local S = H.state

  -- saved variables
  BeastTrainingTrackerKuroDB = opts.db
  GetAddOnMetadata = opts.version and function(_, field) if field == "Version" then return opts.version end end or nil
  BeastTrainingTrackerKuroBackup = opts.backup
  BeastTrainingTrackerKuroSeen = opts.seen

  -- globals the addon touches
  SlashCmdList, StaticPopupDialogs = {}, {}
  StaticPopup_Show = function() end
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    H.printed[#H.printed + 1] = table.concat(parts, " ")
  end
  CreateFrame = function()
    local f = NewFrame()
    H.frames[#H.frames + 1] = f
    return f
  end
  _G.strsplit = strsplit
  wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
  tinsert = table.insert
  time = os.time
  date = os.date
  GetTime = function() H.clock = H.clock + 1 return H.clock end
  GetServerTime = os.time
  C_Timer = {
    After = function(_, fn) fn() end, -- run timers immediately
    NewTicker = function() return {} end,
  }

  ERR_LEARN_ABILITY_S = "You have learned a new ability: %s."
  ERR_LEARN_SPELL_S = "You have learned a new spell: %s."

  UnitClass = function(u) if u == "player" then return "Hunter", "HUNTER" end end
  UnitFactionGroup = function(u) if u == "player" then return S.faction, S.faction end end
  UnitName = function(u)
    if u == "player" then return "Tester" end
    if u == "pet" and S.pet then return S.pet.name end
    if S.units[u] then return S.units[u].name end
  end
  UnitPlayerControlled = function(u) return u == "player" or u == "pet" end
  UnitIsDead = function() return false end
  UnitLevel = function(u)
    if u == "player" then return S.level end
    if u == "pet" and S.pet then return S.pet.level end
  end
  UnitExists = function(u)
    if u == "player" then return true end
    if u == "pet" then return S.pet ~= nil end
    return S.units[u] ~= nil
  end
  UnitCreatureFamily = function(u) if u == "pet" and S.pet then return S.pet.family end end
  UnitGUID = function(u)
    if u == "player" then return S.playerGuid end
    if u == "pet" and S.pet then return S.pet.guid end
  end
  -- Forever two-name shape: tests can set S.playerSurname to exercise it
  UnitNameUnmodified = function(u) if u == "player" then return "Tester", S.playerSurname end end
  UnitIsUnit = function() return false end
  UnitIsPlayer = function(u) return u == "player" end
  GetRealmName = function() return "TestRealm" end
  GetRealZoneText = function() return S.zone end

  BOOKTYPE_PET = "pet"
  HasPetSpells = function() if S.pet then return #(S.pet.spells or {}) end end
  GetSpellBookItemName = function(i) local s = S.pet.spells[i] return s[1], s[2] end

  GetNumTrainerServices = function() return S.trainer and #S.trainer or 0 end
  GetTrainerServiceInfo = function(i) return unpack(S.trainer[i]) end

  IsAddOnLoaded = function() return false end

  -- Game flavour for Client_Select.lua: opts.flavour = "classic_era" or "forever" (default)
  WOW_PROJECT_CLASSIC, WOW_PROJECT_CAMELOT = 2, 100
  WOW_PROJECT_ID = (opts.flavour == "classic_era") and WOW_PROJECT_CLASSIC or WOW_PROJECT_CAMELOT

  -- things the logic files check for and must find missing
  C_SpellBook, Enum, C_AddOns, C_Map, LibStub, TomTom, NpcDB, LibQuestieDB = nil, nil, nil, nil, nil, nil, nil, nil
  RareScannerDB, ClassTrainerFrame, GetNumCrafts, GetCraftInfo, QuestieLoader = nil, nil, nil, nil, nil
  UiMapPoint, C_SuperTrack = nil, nil

  local ns = {}
  for _, file in ipairs(LOGIC_FILES) do
    local chunk = assert(loadfile(file))
    chunk("BeastTrainingTrackerKuro", ns)
  end
  H.ns = ns
  H.fire("ADDON_LOADED", "BeastTrainingTrackerKuro")
  return ns
end

-- Put the player somewhere on a map (enables C_Map position lookups)
function H.setPosition(map, x, y)
  C_Map = {
    GetBestMapForUnit = function() return map end,
    GetPlayerMapPosition = function() return { GetXY = function() return x, y end } end,
  }
end

-- Did any chat line contain this text?
function H.said(text)
  for _, line in ipairs(H.printed) do
    if line:find(text, 1, true) then return true end
  end
  return false
end

return H
