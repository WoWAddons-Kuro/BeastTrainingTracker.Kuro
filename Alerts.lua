local _, ns = ...

local isHunter = select(2, UnitClass("player")) == "HUNTER"

------------------------------------------------------------------------
-- What a unit teaches that you still need (highest rank per ability)
------------------------------------------------------------------------
local function NeededFromUnit(unit)
  if not ns.db or not UnitExists(unit) or UnitIsPlayer(unit) or UnitPlayerControlled(unit) or UnitIsDead(unit) then return end
  local name = UnitName(unit)
  local list = name and ns.teacherIndex[name]
  if not list then return end
  local lvl = UnitLevel(unit) or 0
  if lvl < 1 or lvl > ns.PlayerLevel() then return end
  local best = {}
  for _, e in ipairs(list) do
    if not ns.IsKnown(e.ab, e.rank.rank) then
      local cur = best[e.ab.name]
      if not cur or e.rank.rank > cur.rank.rank then best[e.ab.name] = e end
    end
  end
  local out = {}
  for _, e in pairs(best) do out[#out + 1] = e end
  if #out == 0 then return end
  table.sort(out, function(a, b) return a.ab.name < b.ab.name end)
  return out, name
end

-- "Meat, Fish" for a teacher's family, or nil when the family has no diet
-- entry on this client. Defined here (loaded after Core) but testable via ns.
function ns.FamilyDietText(familyName)
  if not familyName or not ns.Client or not ns.Client.FamilyDiet then return nil end
  local diet = ns.Client.FamilyDiet(familyName)
  if not diet or #diet == 0 then return nil end
  return table.concat(diet, ", ")
end

------------------------------------------------------------------------
-- Nearby alert (target, mouseover, nameplates)
------------------------------------------------------------------------
local lastAlert = {}
local THROTTLE = 90

-- Sounds you can pick for the alert (sound kit ids, stable since Legion)
ns.ALERT_SOUNDS = {
  { id = 8959,  name = "Raid warning" },
  { id = 8960,  name = "Ready check" },
  { id = 12889, name = "Alarm clock" },
  { id = 37666, name = "Raid boss whisper" },
  { id = 18019, name = "Battle.net toast" },
  { id = 31578, name = "Epic loot toast" },
  { id = 888,   name = "Level up" },
  { id = 878,   name = "Quest complete" },
  { id = 3175,  name = "Map ping" },
  { id = 3081,  name = "Whisper received" },
  { id = 5274,  name = "Auction house open" },
  { id = 8458,  name = "PvP queue" },
}

-- The configured alert sound: a custom file / FileDataID if set, else the sound kit
function ns.PlayAlertSound()
  local o = ns.db and ns.db.opts
  if not o then return end
  local custom = o.alertSoundCustom
  if type(custom) == "string" and custom ~= "" then
    local ok = pcall(PlaySoundFile, tonumber(custom) or custom, "Master")
    if ok then return end
  end
  pcall(PlaySound, o.alertSoundId or 31578, "Master")
end

local function Alert(unit, how)
  local o = ns.db and ns.db.opts
  if not o then return end
  -- nothing to tame with yet: no message, no sound
  if ns.HasTameBeast and not ns.HasTameBeast() then return end
  if how == "nameplate" and not o.alertNameplate then return end
  if how ~= "nameplate" and not o.alertTarget then return end
  local list, name = NeededFromUnit(unit)
  if not list then return end
  -- RareScanner already alerts for the rares on its list; don't double up
  if ns.RS and ns.RS.HandlesAlert(name) then return end
  local now = GetTime()
  if lastAlert[name] and now - lastAlert[name] < THROTTLE then return end
  lastAlert[name] = now

  local cls = UnitClassification(unit)
  local rare = cls == "rare" or cls == "rareelite"
  if rare then ns.db.rares[name] = true end

  local parts = {}
  for _, e in ipairs(list) do parts[#parts + 1] = ("%s %d"):format(e.ab.name, e.rank.rank) end
  local who = (rare and "|cffff8000" or "|cffffd100") .. name .. "|r" .. (rare and " (rare)" or "")
  local msg = ("%s teaches |cff40ff40%s|r - tame it!"):format(who, table.concat(parts, ", "))
  -- Second line: what the beast eats, so you know you can keep it fed. Every
  -- entry for one beast shares a family, so the first is enough. Left out
  -- entirely (never "Eats: ?") when the family is unknown.
  local dietText = ns.FamilyDietText(list[1].t and list[1].t.family)
  local dietLine = dietText and ("Eats: |cffffffff%s|r"):format(dietText) or nil

  if RaidNotice_AddMessage and RaidWarningFrame then
    -- RaidWarningFrame is a MessageFrame: "\n" renders as a second line
    local banner = dietLine and (msg .. "\n" .. dietLine) or msg
    pcall(RaidNotice_AddMessage, RaidWarningFrame, banner, ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or { r = 1, g = 1, b = 1 })
  end
  ns.Say(msg)
  if dietLine then ns.Say(dietLine) end
  if o.alertSound then ns.PlayAlertSound() end
end

------------------------------------------------------------------------
-- Upgrade reminder: you know a better rank than your pet has
------------------------------------------------------------------------
local reminded = {}

function ns.CheckUpgrades(force)
  if not ns.db or not ns.db.opts.upgradeAlert or not UnitExists("pet") then return end
  ns.ScanPet()
  local pet = UnitName("pet") or "your pet"
  local parts = {}
  for _, u in ipairs(ns.Upgrades()) do
    if not u.needLevel then
      local k = pet .. "|" .. u.ab.name .. "|" .. u.to
      if force or not reminded[k] then
        reminded[k] = true
        parts[#parts + 1] = ("%s %d -> %d"):format(u.ab.name, u.from, u.to)
      end
    end
  end
  if #parts > 0 then
    ns.Say(("|cffffd100Upgrade available|r for %s: %s. Open Beast Training to teach it."):format(pet, table.concat(parts, ", ")))
  end
end

------------------------------------------------------------------------
-- Level-up nudge: your pet just reached the level for a new rank
------------------------------------------------------------------------
local seenLevel = {}

local function PetLevelChanged()
  if not UnitExists("pet") then return end
  local pet = UnitName("pet") or "?"
  local new = UnitLevel("pet") or 0
  local old = seenLevel[pet]
  seenLevel[pet] = new
  if not old or new <= old or not ns.db.opts.levelNudge then return end
  ns.ScanPet()
  for _, ab in ipairs(ns.abilities) do
    if ns.petRank[ab.name] then
      for _, r in ipairs(ab.parsed) do
        if r.level > old and r.level <= new and r.rank > ns.petRank[ab.name] then
          if ns.IsKnown(ab, r.rank) then
            ns.Say(("|cff40ff40%s can now be taught %s %d|r - you already know it, open Beast Training."):format(pet, ab.name, r.rank))
          else
            ns.Say(("|cffffd100Your pet can now learn %s %d.|r Teachers in %s."):format(ab.name, r.rank, ns.TeacherZones(ab, r, 3)))
          end
        end
      end
    end
  end
end

local function RememberPetLevel()
  if UnitExists("pet") then seenLevel[UnitName("pet") or "?"] = UnitLevel("pet") end
end

------------------------------------------------------------------------
-- On-screen popup ("toast") so a new ability is hard to miss
------------------------------------------------------------------------
local toast = CreateFrame("Button", "BeastTrainingTrackerKuroToast", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
toast:SetSize(360, 64)
toast:SetPoint("TOP", UIParent, "TOP", 0, -170)
toast:SetFrameStrata("DIALOG")
toast:Hide()
if toast.SetBackdrop then
  toast:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  toast:SetBackdropColor(0.05, 0.08, 0.02, 0.92)
  toast:SetBackdropBorderColor(0.67, 0.83, 0.45, 1)
end
toast.icon = toast:CreateTexture(nil, "ARTWORK")
toast.icon:SetSize(40, 40)
toast.icon:SetPoint("TOPLEFT", 12, -12)
toast.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
toast.title = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
toast.title:SetPoint("TOPLEFT", toast.icon, "TOPRIGHT", 10, 0)
toast.title:SetPoint("RIGHT", -10, 0)
toast.title:SetJustifyH("LEFT")
toast.body = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
toast.body:SetPoint("TOPLEFT", toast.title, "BOTTOMLEFT", 0, -4)
toast.body:SetPoint("RIGHT", -10, 0)
toast.body:SetJustifyH("LEFT")
toast.body:SetSpacing(2)
toast:SetScript("OnClick", function(self) self:Hide() end)

local hideAt
toast:SetScript("OnUpdate", function(self)
  if not hideAt then return end
  local left = hideAt - GetTime()
  if left <= 0 then
    hideAt = nil
    self:Hide()
  elseif left < 1 then
    self:SetAlpha(left)
  end
end)

function ns.Toast(title, lines, icon)
  if not ns.Active() then return end
  toast.icon:SetTexture(icon or "Interface\\Icons\\Ability_Hunter_BeastTraining")
  toast.title:SetText("|cffabd473" .. title .. "|r")
  toast.body:SetText(table.concat(lines, "\n"))
  -- Size to the text as actually drawn, since long lines wrap
  local th = toast.title.GetStringHeight and toast.title:GetStringHeight() or 16
  local bh = toast.body.GetStringHeight and toast.body:GetStringHeight() or #lines * 16
  toast:SetHeight(math.max(64, 12 + th + 4 + bh + 14))
  toast:SetAlpha(1)
  toast:Show()
  hideAt = GetTime() + 8
  pcall(PlaySound, (SOUNDKIT and SOUNDKIT.LEVELUP) or 888, "Master")
end

-- Collect ranks learned in one burst, then show a single popup
local pending = {}
local loginAt = GetTime()

local function FlushLearned()
  local list = pending
  pending = {}
  if not ns.db or not ns.db.opts.learnToast or #list == 0 then return end
  if GetTime() - loginAt < 10 then return end -- login/first-sync noise
  local lines, icon = {}, nil
  for i, e in ipairs(list) do
    if i > 4 then
      lines[#lines + 1] = ("|cff9d9d9d+%d more|r"):format(#list - 4)
      break
    end
    local ab = ns.byName[e.name]
    icon = icon or (ab and ab.icon)
    local r = ab and ab.parsed[e.rank]
    local hint = ""
    if ns.petHas[ns.Key(e.name, e.rank)] then
      hint = "  |cff9d9d9d- your pet has it|r"
    elseif r and r.level <= ns.PetLevel() then
      hint = "  |cff9d9d9d- teach it at Beast Training|r"
    elseif r then
      hint = ("  |cff9d9d9d- pet needs lvl %d|r"):format(r.level)
    end
    lines[#lines + 1] = ("|cff40ff40%s %d|r%s"):format(e.name, e.rank, hint)
  end
  ns.Toast(#list == 1 and "New pet ability learned!" or ("%d new pet abilities learned!"):format(#list), lines, icon)
end

-- A new rank got recorded: popup, and maybe the pet can use it now
ns.OnLearned = function(name, rank, quiet)
  if not quiet then
    pending[#pending + 1] = { name = name, rank = rank }
    if #pending == 1 and C_Timer then C_Timer.After(0.5, FlushLearned) end
  end
  if C_Timer then C_Timer.After(1.5, function() ns.CheckUpgrades() end) end
end

ns.OnLogin(function() loginAt = GetTime() end)

------------------------------------------------------------------------
-- Unit tooltips: "Teaches Bite 6"
------------------------------------------------------------------------
local function AddTeachLines(tt)
  if not ns.db or not ns.Active() then return end
  local _, unit = tt:GetUnit()
  if not unit or UnitIsPlayer(unit) then return end
  -- Every tameable-family beast (yours, anyone's pet, or wild) gets its diet,
  -- whether or not it teaches anything. UnitCreatureFamily is the flavour's
  -- own name ("Owl" on Era); FamilyDiet accepts either spelling.
  local family = UnitCreatureFamily and UnitCreatureFamily(unit)
  local dietText = ns.FamilyDietText(family)
  local name = UnitName(unit)
  local list = name and ns.teacherIndex[name]
  if not list then
    if dietText then tt:AddLine("Eats: " .. dietText, 0.8, 0.8, 0.8); tt:Show() end
    return
  end
  -- A teacher whose family the client didn't report: fall back to our data
  dietText = dietText or ns.FamilyDietText(list[1] and list[1].t and list[1].t.family)
  local cls = UnitClassification(unit)
  if cls == "rare" or cls == "rareelite" then ns.db.rares[name] = true end
  local ulvl, plvl, petlvl = UnitLevel(unit) or 0, ns.PlayerLevel(), ns.PetLevel()
  local shown = {}
  for _, e in ipairs(list) do
    local k = ns.Key(e.ab.name, e.rank.rank)
    if not shown[k] then
      shown[k] = true
      local label = ("Teaches %s %d"):format(e.ab.name, e.rank.rank)
      if ns.IsKnown(e.ab, e.rank.rank) then
        tt:AddLine(label .. " (known)", 0.5, 0.5, 0.5)
      elseif ulvl > plvl or ulvl < 1 then
        tt:AddLine(label .. " (too high to tame)", 1, 0.5, 0.25)
      elseif e.rank.level > petlvl then
        tt:AddLine(label .. (" - tame it! (pet needs lvl %d to use)"):format(e.rank.level), 0.25, 1, 0.25)
      else
        tt:AddLine(label .. " - tame it!", 0.25, 1, 0.25)
      end
    end
  end
  if dietText then tt:AddLine("Eats: " .. dietText, 0.8, 0.8, 0.8) end
  local st = ns.RS and ns.RS.Status(name)
  if st then tt:AddLine("RareScanner: " .. st.text, 1, 0.6, 0.25, true) end
  tt:Show()
end

local function SafeTeach(tt) pcall(AddTeachLines, tt) end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
    if tt == GameTooltip then SafeTeach(tt) end
  end)
else
  GameTooltip:HookScript("OnTooltipSetUnit", SafeTeach)
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
if not isHunter then return end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
  "UNIT_PET", "UNIT_LEVEL", "PLAYER_ENTERING_WORLD" }) do
  pcall(ev.RegisterEvent, ev, e)
end

ev:SetScript("OnEvent", function(_, e, a1)
  if not ns.db then return end
  if e == "PLAYER_TARGET_CHANGED" then
    Alert("target", "target")
  elseif e == "UPDATE_MOUSEOVER_UNIT" then
    Alert("mouseover", "mouseover")
  elseif e == "NAME_PLATE_UNIT_ADDED" then
    if a1 then Alert(a1, "nameplate") end
  elseif e == "UNIT_PET" then
    if a1 == "player" then
      C_Timer.After(2, function() RememberPetLevel(); ns.CheckUpgrades() end)
    end
  elseif e == "UNIT_LEVEL" then
    if a1 == "pet" then C_Timer.After(0.5, PetLevelChanged) end
  elseif e == "PLAYER_ENTERING_WORLD" then
    C_Timer.After(5, function() RememberPetLevel(); ns.CheckUpgrades() end)
  end
end)
