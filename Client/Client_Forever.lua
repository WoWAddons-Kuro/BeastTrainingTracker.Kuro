-- BeastTrainingTracker.Kuro: client implementation for WoW Forever
-- (WOW_PROJECT_CAMELOT, Mainline UI, interface 16001).
--
-- Forever characters have TWO names ("Kuro Oakheart"), returned as two
-- separate values by UnitNameUnmodified("player"). UnitName("player") is only
-- the first name and must never be used as a key. This file is the only place
-- in the addon allowed to call those APIs.
local _, ns = ...

local impl = {}
ns.ClientFlavours.forever = impl

-- Two returns. Inside a concat Lua would keep only the first, so always
-- capture both explicitly as done here.
local function Names()
  local first, surname
  if UnitNameUnmodified then first, surname = UnitNameUnmodified("player") end
  if type(first) ~= "string" or first == "" then first = UnitName("player") end
  if type(surname) ~= "string" or surname == "" then surname = nil end
  return first, surname
end

function impl.PlayerKey()
  return UnitGUID("player")
end

function impl.PlayerDisplayName()
  local first, surname = Names()
  if not first then return "?" end
  return surname and (first .. " " .. surname) or first
end

function impl.PlayerFirstName()
  return UnitName("player")
end

-- AceDB-3.0 on Forever keys db.char as "First Surname" when
-- RegionalUniqueNamesEnabled() is true, otherwise "First - Realm" (its
-- UnitNameUnmodified .. " - " .. realm concat keeps only the first name).
-- Try the two-name shape first, then the legacy shapes.
function impl.ThirdPartyCharKeyCandidates()
  local first, surname = Names()
  local realm = GetRealmName() or ""
  local out = {}
  if first and surname then out[#out + 1] = first .. " " .. surname end
  if first then
    out[#out + 1] = first .. " - " .. realm
    out[#out + 1] = first .. "-" .. realm
    out[#out + 1] = first
  end
  return out
end

--------------------------------------------------------------------------------
-- Pet families. Forever is the canonical naming (the data files are transcribed
-- from Petopia's Forever pages), so the name maps are the identity. All 19
-- families exist, including the two new ones (Fox, Core Hound).
--------------------------------------------------------------------------------
local TAMEABLE_FAMILIES = {
  ["Bat"] = true, ["Bear"] = true, ["Bird of Prey"] = true, ["Boar"] = true, ["Carrion Bird"] = true,
  ["Cat"] = true, ["Core Hound"] = true, ["Crab"] = true, ["Crocolisk"] = true, ["Fox"] = true,
  ["Gorilla"] = true, ["Hyena"] = true, ["Raptor"] = true, ["Scorpid"] = true, ["Spider"] = true,
  ["Tallstrider"] = true, ["Turtle"] = true, ["Wind Serpent"] = true, ["Wolf"] = true,
}

function impl.CanonicalFamilyName(familyName)
  return familyName
end

function impl.DisplayFamilyName(canonicalFamilyName)
  return canonicalFamilyName
end

function impl.FamilyExists(canonicalFamilyName)
  return TAMEABLE_FAMILIES[canonicalFamilyName] == true
end

function impl.FamilyDiet(familyName)
  return ns.Client.CommonFamilyDiet(impl, familyName)
end

function impl.PlayerFactionKey()
  return ns.Client.CommonPlayerFactionKey()
end

--------------------------------------------------------------------------------
-- Stable masters. The Mainline minimap tracking menu already offers a
-- "Stable Master" entry to hunters, so drawing our own minimap pins would
-- only double the icons. World-map pins have no native equivalent and are
-- drawn by Geo.lua on every flavour.
--------------------------------------------------------------------------------
function impl.StableMasterMinimapPinsWanted()
  return false
end

function impl.StableMasterNativeTrackingHint()
  return "Minimap: turn on Stable Master in the minimap tracking menu to see them there."
end

-- The Mainline trainer frame has no free status box along the bottom. Until
-- a layout is verified in game the trainer line is not shown on Forever.
-- (/bttk stable and the map pins carry the feature.)
function impl.TrainerFrameNearestAnchor()
  return nil
end