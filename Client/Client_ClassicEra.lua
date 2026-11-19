-- BeastTrainingTracker.Kuro: client implementation for Classic Era /
-- Anniversary / Hardcore (WOW_PROJECT_CLASSIC, 1.15).
--
-- Era characters have ONE name. The GUID is still the only acceptable key:
-- a name-realm key would work here, but the addon must behave the same on
-- both flavours so the Forever bug cannot creep back in.
local _, ns = ...

local impl = {}
ns.ClientFlavours.classic_era = impl

function impl.PlayerKey()
  return UnitGUID("player")
end

function impl.PlayerDisplayName()
  return UnitName("player") or "?"
end

function impl.PlayerFirstName()
  return UnitName("player")
end

-- AceDB-3.0 on Era keys db.char as "Name - Realm".
function impl.ThirdPartyCharKeyCandidates()
  local name = UnitName("player")
  if not name then return {} end
  local realm = GetRealmName() or ""
  return { name .. " - " .. realm, name .. "-" .. realm, name }
end