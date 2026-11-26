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

--------------------------------------------------------------------------------
-- Pet families. Era differs from the canonical (Forever) naming in two ways:
--   * the family Forever calls "Bird of Prey" is "Owl" here (UnitCreatureFamily
--     and Beast Lore both say Owl);
--   * Fox and Core Hound do not exist as tameable families (17 families total).
-- Diets are identical, see Client.FAMILY_DIET_BY_CANONICAL_FAMILY.
--------------------------------------------------------------------------------
local ERA_TO_CANONICAL = { ["Owl"] = "Bird of Prey" }
local CANONICAL_TO_ERA = { ["Bird of Prey"] = "Owl" }

local TAMEABLE_FAMILIES = {
  ["Bat"] = true, ["Bear"] = true, ["Bird of Prey"] = true, ["Boar"] = true, ["Carrion Bird"] = true,
  ["Cat"] = true, ["Crab"] = true, ["Crocolisk"] = true, ["Gorilla"] = true, ["Hyena"] = true,
  ["Raptor"] = true, ["Scorpid"] = true, ["Spider"] = true, ["Tallstrider"] = true, ["Turtle"] = true,
  ["Wind Serpent"] = true, ["Wolf"] = true,
}

function impl.CanonicalFamilyName(familyName)
  return ERA_TO_CANONICAL[familyName] or familyName
end

function impl.DisplayFamilyName(canonicalFamilyName)
  return CANONICAL_TO_ERA[canonicalFamilyName] or canonicalFamilyName
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
-- Stable masters. Era's minimap tracking menu (1.15) has no townsfolk entries
-- at all - those arrived with TBC - so the only way to see a stable master on
-- the minimap is for us to draw it.
--------------------------------------------------------------------------------
function impl.StableMasterMinimapPinsWanted()
  return true
end

function impl.StableMasterNativeTrackingHint()
  return nil
end

-- On Era, Beast Training is the vanilla craft window (Blizzard_CraftUI's
-- CraftFrame, with "Training Points" and a Train button), NOT
-- ClassTrainerFrame. The band between the title (y -17) and the ability list
-- (Craft1 at y -96) is empty for Beast Training (CraftRankFrame, the skill
-- bar at y -37, is hidden there); the nearest stable master line sits in it,
-- centred, just above the list.
function impl.TrainerFrameNearestAnchor()
  local f = CraftFrame
  if not f then return nil end
  return {
    parent = f,
    point = "TOP",
    relTo = f,
    relPoint = "TOP",
    x = -8,
    y = -66,
    width = 320,
    justify = "CENTER",
  }
end