-- BeastTrainingTracker.Kuro: the client interface for everything that differs
-- between game flavours. The rest of the addon only ever calls ns.Client.*;
-- it never touches UnitName / UnitNameUnmodified / UnitPVPName / GetRealmName
-- or WOW_PROJECT_* directly. One implementation file per flavour:
--
--   Client/Client_Forever.lua     WoW Forever (Mainline UI, interface 16001) - two-name characters
--   Client/Client_ClassicEra.lua  Classic Era / Anniversary / Hardcore        - one-name characters
--
-- Load order (TOC): Client.lua, Client_Forever.lua, Client_ClassicEra.lua, then
-- Client_Select.lua picks the one matching WOW_PROJECT_ID and verifies every
-- interface method exists. A missing method is a load-time warning, not a
-- silent nil halfway through InitDB.
--
-- Why this exists: on Forever a character has a first AND a last name and
-- UnitName("player") returns only the first one, so every "Kuro ..." alt
-- collapsed onto the same SavedVariables key. See PROJECT_STRUCTURE.md.
local _, ns = ...

local Client = {}
ns.Client = Client
ns.ClientFlavours = {}  -- flavour name -> implementation table, filled by the Client_*.lua files

--------------------------------------------------------------------------------
-- The interface. Every flavour file must implement each of these.
--------------------------------------------------------------------------------
Client.INTERFACE = {
  -- PlayerKey() -> UnitGUID("player"). THE key for any per-character table in
  -- account-wide SavedVariables (BeastTrainingTrackerKuroBackup). Never a name.
  "PlayerKey",

  -- PlayerDisplayName() -> what to show the user for this character.
  --   Era:     "Kuro"
  --   Forever: "Kuro Oakheart"
  "PlayerDisplayName",

  -- PlayerFirstName() -> UnitName("player"). Only correct use: comparing against
  -- chat sender names, which are first-name on Forever as well.
  "PlayerFirstName",

  -- ThirdPartyCharKeyCandidates() -> ordered list of strings another addon's
  -- AceDB-style `db.char[...]` is likely keyed by on this flavour. Used to read
  -- RareScanner's per-character kill data. Most specific shape first.
  "ThirdPartyCharKeyCandidates",

  -- CanonicalFamilyName(familyName) -> the Forever-style family name used as
  -- the key in Data.lua / RarePets.lua and FAMILY_DIET_BY_CANONICAL_FAMILY.
  --   Era:     "Owl" -> "Bird of Prey", anything else unchanged
  --   Forever: unchanged
  -- UnitCreatureFamily() returns the flavour's own name, so every comparison
  -- against data-file families goes through this first.
  "CanonicalFamilyName",

  -- DisplayFamilyName(canonicalFamilyName) -> what to show the player.
  --   Era:     "Bird of Prey" -> "Owl"
  --   Forever: unchanged
  "DisplayFamilyName",

  -- FamilyExists(canonicalFamilyName) -> true if that family is tameable on
  -- this flavour (Era has no Fox or Core Hound).
  "FamilyExists",

  -- FamilyDiet(familyName) -> ordered list of food-type names the family eats
  -- (as Beast Lore lists them), or nil when the family is unknown. Accepts
  -- either the flavour's or the canonical name.
  "FamilyDiet",
}

--------------------------------------------------------------------------------
-- Shared data: what each family eats. Identical on Era and Forever (the Forever
-- client data states its diets are unchanged from Classic); only the set of
-- families and the Owl / Bird of Prey name differ, and those live in the
-- flavour files. Keyed by canonical (Forever) family name.
--
-- Sources, cross-checked 2026-11-20 (Petopia's diet pages were down):
--   wow-forever.online/hunter-pets (Forever client build 70338)
--   wowcampfire.com/hunter-pets    (Forever client data)
--   wowhead.com/classic/hunter-pets (Era)
--   wow-petopia.com/forever/family.php?id=fox / id=corehound
--------------------------------------------------------------------------------
Client.FAMILY_DIET_BY_CANONICAL_FAMILY = {
  ["Bat"]          = { "Fungus", "Fruit" },
  ["Bear"]         = { "Meat", "Fish", "Cheese", "Bread", "Fungus", "Fruit" },
  ["Bird of Prey"] = { "Meat" },
  ["Boar"]         = { "Meat", "Fish", "Cheese", "Bread", "Fungus", "Fruit" },
  ["Carrion Bird"] = { "Meat", "Fish" },
  ["Cat"]          = { "Meat", "Fish" },
  ["Core Hound"]   = { "Meat" },
  ["Crab"]         = { "Fish", "Bread", "Fungus", "Fruit" },
  ["Crocolisk"]    = { "Meat", "Fish" },
  ["Fox"]          = { "Meat" },
  ["Gorilla"]      = { "Fungus", "Fruit" },
  ["Hyena"]        = { "Meat", "Fruit" },
  ["Raptor"]       = { "Meat" },
  ["Scorpid"]      = { "Meat" },
  ["Spider"]       = { "Meat" },
  ["Tallstrider"]  = { "Cheese", "Fungus", "Fruit" },
  ["Turtle"]       = { "Fish", "Fungus", "Fruit", "Raw Fish" },
  ["Wind Serpent"] = { "Fish", "Cheese", "Bread" },
  ["Wolf"]         = { "Meat" },
}

-- Common FamilyDiet implementation; each flavour file binds it as impl.FamilyDiet
-- after its own CanonicalFamilyName is defined. Returns a fresh copy so callers
-- can't mutate the table above.
function Client.CommonFamilyDiet(impl, familyName)
  if type(familyName) ~= "string" then return nil end
  local diet = Client.FAMILY_DIET_BY_CANONICAL_FAMILY[impl.CanonicalFamilyName(familyName)]
  if not diet then return nil end
  local out = {}
  for i, food in ipairs(diet) do out[i] = food end
  return out
end