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
}