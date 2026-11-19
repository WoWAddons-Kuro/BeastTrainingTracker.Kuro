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