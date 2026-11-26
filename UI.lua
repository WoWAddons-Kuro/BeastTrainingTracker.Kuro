local _, ns = ...

local abilities = ns.abilities
local Geo = ns.Geo
local Say = ns.Say

local WIDTH, HEIGHT = 780, 630
local LIST_W = WIDTH - 16 - 28
local HEAD_H, ROW_H = 26, 18
local GREEN, GOLD = "|cff40ff40", "|cffffd100"

local function C(r, g, b, a, tex) tex:SetColorTexture(r, g, b, a) return tex end

------------------------------------------------------------------------
-- Main frame + header
------------------------------------------------------------------------
local f = CreateFrame("Frame", "BeastTrainingTrackerKuroFrame", UIParent, "BasicFrameTemplateWithInset")
f:SetSize(WIDTH, HEIGHT)
f:SetPoint("CENTER")
f:SetFrameStrata("HIGH")
f:SetMovable(true)
f:EnableMouse(true)
f:SetClampedToScreen(true)
f:RegisterForDrag("LeftButton")
f:Hide()
tinsert(UISpecialFrames, "BeastTrainingTrackerKuroFrame")

local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
title:SetPoint("TOP", 0, -6)
title:SetText("|cffabd473BeastTrainingTracker.Kuro|r")

local bigIcon = f:CreateTexture(nil, "ARTWORK")
bigIcon:SetSize(40, 40)
bigIcon:SetPoint("TOPLEFT", 16, -32)
bigIcon:SetTexture("Interface\\Icons\\Ability_Hunter_BeastTraining")
bigIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

local petText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
petText:SetPoint("TOPLEFT", bigIcon, "TOPRIGHT", 10, -2)
petText:SetJustifyH("LEFT")

local zoneText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
zoneText:SetPoint("TOPLEFT", petText, "BOTTOMLEFT", 0, -4)
zoneText:SetJustifyH("LEFT")

local bar = CreateFrame("StatusBar", nil, f)
bar:SetSize(260, 18)
bar:SetPoint("TOPRIGHT", -150, -36)
bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
bar:SetStatusBarColor(0.67, 0.83, 0.45)
bar:SetMinMaxValues(0, 1)
C(0, 0, 0, 0.55, bar:CreateTexture(nil, "BACKGROUND")):SetAllPoints()
local barBorder = CreateFrame("Frame", nil, bar, BackdropTemplateMixin and "BackdropTemplate" or nil)
barBorder:SetPoint("TOPLEFT", -3, 3)
barBorder:SetPoint("BOTTOMRIGHT", 3, -3)
if barBorder.SetBackdrop then
  barBorder:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
  barBorder:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)
end
local barText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
barText:SetPoint("CENTER")

local syncText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
syncText:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -6)
syncText:SetJustifyH("RIGHT")

-- Optional addon indicators (green = detected). Click to open Settings.
local addonStrip = CreateFrame("Button", nil, f)
addonStrip:SetHeight(14)
addonStrip:SetPoint("TOPLEFT", zoneText, "BOTTOMLEFT", 0, -4)
addonStrip.text = addonStrip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
addonStrip.text:SetPoint("LEFT")
addonStrip:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
  GameTooltip:AddLine("Optional addons", 1, 0.82, 0)
  GameTooltip:AddLine("BeastTrainingTracker.Kuro works on its own. These add extras:", 0.8, 0.8, 0.8, true)
  GameTooltip:AddLine(" ")
  for _, a in ipairs(ns.Geo.AddonStatus()) do
    GameTooltip:AddLine((a.on and "|cff40ff40" or "|cff9d9d9d") .. a.name .. "|r", 1, 1, 1)
    GameTooltip:AddLine(a.text, 0.75, 0.75, 0.75, true)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click for Settings", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end)
addonStrip:SetScript("OnLeave", GameTooltip_Hide)
addonStrip:SetScript("OnClick", function() if ns.ShowTab then ns.ShowTab(ns.TAB.map) end end)

local function UpdateAddonStrip()
  local parts = {}
  for _, a in ipairs(ns.Geo.AddonStatus()) do
    parts[#parts + 1] = ("|TInterface\\COMMON\\Indicator-%s:12:12|t%s%s|r"):format(a.on and "Green" or "Gray",
      a.on and "|cff40ff40" or "|cff9d9d9d", a.name)
  end
  addonStrip.text:SetText(table.concat(parts, "   "))
  addonStrip:SetWidth(addonStrip.text:GetStringWidth() + 4)
end

------------------------------------------------------------------------
-- "Beast Training" button (secure: casts the spell that opens the window).
-- Lives on UIParent so the main window stays usable in combat.
------------------------------------------------------------------------
local BT_SPELL = (GetSpellInfo and GetSpellInfo(5149))
  or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(5149)) or "Beast Training"

local teach = CreateFrame("Button", "BeastTrainingTrackerKuroTeachButton", UIParent, "SecureActionButtonTemplate,UIPanelButtonTemplate")
teach:SetSize(124, 24)
teach:SetText("Beast Training")
teach:SetFrameStrata("DIALOG")
teach:SetAttribute("type", "spell")
teach:SetAttribute("spell", BT_SPELL)
teach:RegisterForClicks((GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")) and "AnyDown" or "AnyUp")
teach:Hide()
teach:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
  GameTooltip:AddLine("Open Beast Training", 1, 0.82, 0)
  GameTooltip:AddLine("Teach your pet the ranks you've learned. The tracker syncs every time it opens.", 1, 1, 1, true)
  GameTooltip:Show()
end)
teach:SetScript("OnLeave", GameTooltip_Hide)

-- Clear the hunt route / waypoints (sits under the Beast Training button)
local clearRoute = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
clearRoute:SetSize(124, 20)
clearRoute:SetPoint("TOPRIGHT", -16, -60)
clearRoute:SetText("Clear waypoints")
clearRoute:SetScript("OnClick", function() ns.Geo.ClearWaypoints() end)
clearRoute:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
  local n = #ns.Geo.route
  GameTooltip:AddLine("Clear waypoints", 1, 0.82, 0)
  GameTooltip:AddLine(n > 0 and ("Removes the %d-stop hunt route and its waypoints."):format(n)
    or "No waypoints set. Click beasts in any tab to build a hunt route.", 1, 1, 1, true)
  GameTooltip:Show()
end)
clearRoute:SetScript("OnLeave", GameTooltip_Hide)

local function PlaceTeach()
  if InCombatLockdown() then return end
  if f:IsShown() and f:GetRight() and ns.Active() then
    -- same effective scale as the window, so the window's coordinates can be used directly
    teach:SetScale(f:GetEffectiveScale() / UIParent:GetEffectiveScale())
    teach:ClearAllPoints()
    teach:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", f:GetRight() - 16, f:GetTop() - 32)
    teach:SetFrameLevel(f:GetFrameLevel() + 20)
    teach:Show()
  else
    teach:Hide()
  end
end

local tev = CreateFrame("Frame")
tev:RegisterEvent("PLAYER_REGEN_DISABLED")
tev:RegisterEvent("PLAYER_REGEN_ENABLED")
tev:SetScript("OnEvent", function(_, e)
  if e == "PLAYER_REGEN_DISABLED" then teach:Hide() else PlaceTeach() end
end)

f:SetScript("OnDragStart", function(self)
  self:StartMoving()
  self:SetScript("OnUpdate", PlaceTeach)
end)
f:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  self:SetScript("OnUpdate", nil)
  local p, _, rp, x, y = self:GetPoint()
  ns.db.pos = { p, rp, x, y }
  PlaceTeach()
end)

------------------------------------------------------------------------
-- Shared widgets
------------------------------------------------------------------------
local allChecks = {}

local function Check(parent, label, key, x, y, tip, onChange)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(22, 22)
  cb:SetPoint("TOPLEFT", x, y)
  local fs = cb.text or cb.Text
  if not fs then
    fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  end
  cb.text = fs
  fs:SetFontObject("GameFontHighlightSmall")
  fs:SetText(label)
  cb:SetScript("OnClick", function(self)
    ns.db.opts[key] = self:GetChecked() and true or false
    if onChange then onChange(ns.db.opts[key]) end
    ns.Refresh()
  end)
  if tip then
    cb:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(label, 1, 0.82, 0)
      GameTooltip:AddLine(tip, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", GameTooltip_Hide)
  end
  cb.key = key
  allChecks[#allChecks + 1] = cb
  return cb
end

local function Button(parent, text, w, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function Text(parent, font, x, y, text)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetJustifyH("LEFT")
  if text then fs:SetText(text) end
  return fs
end

local function Divider(parent, y)
  local t = C(0.67, 0.83, 0.45, 0.25, parent:CreateTexture(nil, "ARTWORK"))
  t:SetHeight(1)
  t:SetPoint("TOPLEFT", 4, y)
  t:SetPoint("TOPRIGHT", -4, y)
  return t
end

local function Scroll(parent, top, bottom)
  local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 2, top)
  scroll:SetPoint("BOTTOMRIGHT", -26, bottom)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(LIST_W, 1)
  scroll:SetScrollChild(child)
  return scroll, child
end

-- Generic list for Hunt / Pet tabs.
-- item = { kind = "head"|"row"|"note", icon=, left=, right=, onClick=, tip=fn(tt), button={text=, onClick=} }
local function MakeList(parent, top, bottom)
  local L = { rows = {} }
  L.scroll, L.child = Scroll(parent, top, bottom)
  L.empty = L.child:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  L.empty:SetPoint("TOP", 0, -40)
  return L
end

local function ListRow(L, i)
  local row = L.rows[i]
  if row then return row end
  row = CreateFrame("Button", nil, L.child)
  row.hl = row:CreateTexture(nil, "HIGHLIGHT")
  row.hl:SetAllPoints()
  row.hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  row.hl:SetBlendMode("ADD")
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.line = C(0.85, 0.65, 0.15, 0.35, row:CreateTexture(nil, "BORDER"))
  row.line:SetHeight(1)
  row.line:SetPoint("BOTTOMLEFT")
  row.line:SetPoint("BOTTOMRIGHT")
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  row.box = row:CreateTexture(nil, "ARTWORK")
  row.box:SetSize(16, 16)
  row.box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
  row.chk = row:CreateTexture(nil, "OVERLAY")
  row.chk:SetAllPoints(row.box)
  row.chk:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.left:SetJustifyH("LEFT")
  row.left:SetWordWrap(false)
  row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.right:SetJustifyH("RIGHT")
  row.right:SetWordWrap(false)
  row.btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.btn:SetSize(90, 20)
  row.btn:SetPoint("RIGHT", -6, 0)
  row:SetScript("OnEnter", function(self)
    local it = self.item
    if it and it.tip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      it.tip(GameTooltip)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", GameTooltip_Hide)
  row:SetScript("OnClick", function(self, button)
    local it = self.item
    if not it then return end
    if button == "RightButton" then
      if it.onRightClick then it.onRightClick() end
    elseif it.onClick then
      it.onClick()
    end
    if GameTooltip:GetOwner() == self and self.item and self.item.tip then
      GameTooltip:ClearLines()
      self.item.tip(GameTooltip)
      GameTooltip:Show()
    end
  end)
  row.btn:SetScript("OnClick", function(self)
    local it = self:GetParent().item
    if it and it.button then it.button.onClick() end
  end)
  L.rows[i] = row
  return row
end

local function ListSet(L, items, emptyMsg)
  local y = 0
  for i, it in ipairs(items) do
    local row = ListRow(L, i)
    row.item = it
    local head = it.kind == "head"
    local h = head and HEAD_H or 20
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", L.child, "TOPLEFT", 0, -y)
    row:SetPoint("RIGHT", L.child, "RIGHT")
    row:SetHeight(h)
    y = y + h
    if head then
      row.bg:SetColorTexture(0.45, 0.33, 0.05, 0.28)
    elseif it.kind == "note" then
      row.bg:SetColorTexture(0, 0, 0, 0)
    else
      row.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0)
    end
    row.line:SetShown(head)
    row.hl:SetShown(it.onClick ~= nil or it.onRightClick ~= nil or it.tip ~= nil)
    row.left:SetFontObject(head and "GameFontNormal" or (it.kind == "note" and "GameFontDisableSmall" or "GameFontHighlightSmall"))
    local x = it.indent or 8
    if it.check ~= nil then
      row.box:ClearAllPoints()
      row.box:SetPoint("LEFT", x, 0)
      row.box:Show()
      row.chk:SetShown(it.check and true or false)
      x = x + 22
    else
      row.box:Hide()
      row.chk:Hide()
    end
    if it.icon then
      local s = head and 20 or 16
      row.icon:SetSize(s, s)
      row.icon:ClearAllPoints()
      row.icon:SetPoint("LEFT", x, 0)
      row.icon:SetTexture(it.icon)
      row.icon:Show()
      x = x + s + 8
    else
      row.icon:Hide()
    end
    row.btn:SetShown(it.button ~= nil)
    if it.button then row.btn:SetText(it.button.text) end
    row.right:ClearAllPoints()
    if it.button then row.right:SetPoint("RIGHT", row.btn, "LEFT", -8, 0) else row.right:SetPoint("RIGHT", -8, 0) end
    row.right:SetText(it.right or "")
    row.left:ClearAllPoints()
    row.left:SetPoint("LEFT", x, 0)
    row.left:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
    row.left:SetText(it.left or "")
    -- optional fixed columns: { {x=, w=, text=}, ... }
    row.cols = row.cols or {}
    local cols = it.cols or {}
    for ci, c in ipairs(cols) do
      local fs = row.cols[ci]
      if not fs then
        fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        row.cols[ci] = fs
      end
      fs:ClearAllPoints()
      fs:SetPoint("LEFT", c.x, 0)
      fs:SetWidth(c.w)
      fs:SetText(c.text or "")
      fs:Show()
    end
    for ci = #cols + 1, #row.cols do row.cols[ci]:Hide() end
    row:Show()
  end
  for i = #items + 1, #L.rows do L.rows[i]:Hide(); L.rows[i].item = nil end
  L.empty:SetText(emptyMsg or "")
  L.empty:SetShown(#items == 0)
  L.child:SetHeight(math.max(1, y))
end

------------------------------------------------------------------------
-- Tabs
------------------------------------------------------------------------
local TAB_NAMES = { "Abilities", "Hunt Planner", "Special Pets", "My Pet", "Settings", "Backup" }
ns.TAB = { abilities = 1, hunt = 2, rares = 3, pet = 4, map = 5, backup = 6 }
local tabs, panels = {}, {}

local function StyleTab(b, sel)
  if sel then
    b.bg:SetColorTexture(0.67, 0.83, 0.45, 0.22)
    b.accent:Show()
    b.text:SetFontObject("GameFontHighlight")
  else
    b.bg:SetColorTexture(0, 0, 0, 0.35)
    b.accent:Hide()
    b.text:SetFontObject("GameFontNormal")
  end
end

for i, name in ipairs(TAB_NAMES) do
  local b = CreateFrame("Button", nil, f)
  b:SetSize(120, 24)
  b:SetPoint("TOPLEFT", 12 + (i - 1) * 124, -94)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.accent = C(0.67, 0.83, 0.45, 0.9, b:CreateTexture(nil, "ARTWORK"))
  b.accent:SetHeight(2)
  b.accent:SetPoint("BOTTOMLEFT")
  b.accent:SetPoint("BOTTOMRIGHT")
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.text:SetPoint("CENTER", 0, 1)
  b.text:SetText(name)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.06)
  b:SetScript("OnClick", function() ns.ShowTab(i) end)
  tabs[i] = b

  local p = CreateFrame("Frame", nil, f)
  p:SetPoint("TOPLEFT", 8, -124)
  p:SetPoint("BOTTOMRIGHT", -8, 8)
  p:Hide()
  panels[i] = p
end
Divider(f, -119)

-- Keep the class restriction accessible in the upper-right title bar.
-- Its visibility is independent of the addon being active or inactive.


local hunterCheck = Check(f, "Only run on Hunters", "hunterOnly", 0, 0,
  "On other classes the addon does nothing - no scans, alerts, map pins, tracker, XP bar or tooltips. Only this window and the minimap button stay.",
  function() if ns.ApplyActive then ns.ApplyActive() end end)
hunterCheck:ClearAllPoints()
hunterCheck:SetPoint("TOPRIGHT", f, "TOPRIGHT", -38, -2)
local hunterCheckLabel = hunterCheck.text or hunterCheck.Text
if hunterCheckLabel then
  hunterCheckLabel:ClearAllPoints()
  hunterCheckLabel:SetPoint("RIGHT", hunterCheck, "LEFT", -2, 0)
end
hunterCheck:Show()

local function CurrentTab() return (ns.db and ns.db.tab) or 1 end

-- Hunter-only mode on another class: only the Settings tab is usable
local function InactiveTab(i)
  return ns.Active() and i or ns.TAB.map
end

local function RefreshAll()
  if not ns.db or not f:IsShown() then return end
  for _, cb in ipairs(allChecks) do cb:SetChecked(ns.db.opts[cb.key]) end
  local active = ns.Active()
  for k, b in ipairs(tabs) do
    local usable = active or k == ns.TAB.map
    b:SetEnabled(usable)
    b.text:SetAlpha(usable and 1 or 0.35)
  end
  if not active then
    petText:SetText("|cffff6060Disabled on this character|r")
    zoneText:SetText("|cff9d9d9dNot a Hunter|r")
    bar:Hide()
    addonStrip.text:SetText("")
    clearRoute:SetEnabled(false)
    syncText:SetText("")
    local p = panels[ns.TAB.map]
    if p and p.Refresh then p.Refresh() end
    return
  end
  bar:Show()

  local fam, zone = ns.PetFamily(), ns.CurrentZone()
  if fam then
    petText:SetText(("%s  |cffffffffLevel %d|r"):format(UnitName("pet") or fam, UnitLevel("pet") or 0))
    zoneText:SetText(("|cff9d9d9d%s|r  ·  %s"):format(fam, zone ~= "" and zone or "?"))
  else
    petText:SetText("|cff9d9d9dNo pet out|r")
    zoneText:SetText(zone)
  end
  local known, total = ns.Counts()
  bar:SetValue(total > 0 and known / total or 0)
  barText:SetText(("%d / %d ranks learned  (%d%%)"):format(known, total, total > 0 and math.floor(known / total * 100 + 0.5) or 0))
  UpdateAddonStrip()
  clearRoute:SetEnabled(#ns.Geo.route > 0)
  syncText:SetText(ns.db.lastSync and ("Last Beast Training sync: " .. date("%b %d, %H:%M", ns.db.lastSync))
    or "Open Beast Training once to sync what you've learned")

  local p = panels[CurrentTab()]
  if p and p.Refresh then p.Refresh() end
end

function ns.ShowTab(i)
  if not ns.db then return end
  i = InactiveTab(i)
  ns.db.tab = i
  for k, b in ipairs(tabs) do
    StyleTab(b, k == i)
    panels[k]:SetShown(k == i)
  end
  if not f:IsShown() then f:Show() else RefreshAll() end
end

function ns.ToggleMain() f:SetShown(not f:IsShown()) end
ns.RefreshInactiveUI = RefreshAll -- Core calls this on Refresh while in hunter-only mode

f:SetScript("OnShow", function()
  ns.ShowTab(CurrentTab())
  RefreshAll()
  PlaceTeach()
end)
f:SetScript("OnHide", PlaceTeach)

ns.OnRefresh(RefreshAll)

-- keep RareScanner respawn timers ticking while the window is open
if C_Timer and C_Timer.NewTicker then
  C_Timer.NewTicker(30, function() if f:IsShown() then RefreshAll() end end)
end

------------------------------------------------------------------------
-- Tab 1: Abilities
------------------------------------------------------------------------
do
  local p = panels[1]
  local COL = { check = 26, rank = 48, lvl = 110, tp = 168, pet = 210, src = 262 }

  Check(p, "My pet's family", "petOnly", 4, -2, "Only abilities your current pet's family can use.")
  Check(p, "Hide learned", "hideKnown", 142, -2, "Hide ranks you've learned (or outgrown by learning a higher rank).")
  Check(p, "Hide trainer skills", "hideTrainer", 262, -2, "Hide abilities bought from a Pet Trainer (Growl, resistances...).")
  Check(p, "Hide above pet level", "hideHigh", 414, -2, "Hide ranks your pet isn't high enough level to use yet (orange pet lvl).")
  Check(p, "Tameable in this zone", "zoneOnly", 570, -2, "Only ranks taught by a beast in the zone you're in.")

  local searchLabel = Text(p, "GameFontNormalSmall", 10, -36, "Search")
  local search = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
  search:SetSize(200, 20)
  search:SetPoint("LEFT", searchLabel, "RIGHT", 12, 0)
  search:SetAutoFocus(false)
  search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  search:SetScript("OnTextChanged", function(self)
    ns.search = (self:GetText() or ""):lower():match("^%s*(.-)%s*$")
    p.Refresh()
  end)
  local hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("LEFT", search, "RIGHT", 10, 0)
  hint:SetText("ability, beast or zone")

  local collapseAll = Button(p, "Collapse all", 96, function()
    for _, ab in ipairs(abilities) do ns.db.collapsed[ab.name] = true end
    p.Refresh()
  end)
  collapseAll:SetPoint("TOPRIGHT", -4, -34)
  local expandAll = Button(p, "Expand all", 90, function()
    wipe(ns.db.collapsed)
    p.Refresh()
  end)
  expandAll:SetPoint("RIGHT", collapseAll, "LEFT", -4, 0)

  local colY = -64
  local function ColHead(text, x)
    local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", 2 + x, colY)
    fs:SetText(text)
  end
  ColHead("Rank", COL.rank)
  ColHead("Pet lvl", COL.lvl)
  ColHead("TP", COL.tp)
  ColHead("Where to tame it  " .. GREEN .. "(green = in your zone)|r", COL.src)
  Divider(p, colY - 14)

  local scroll, child = Scroll(p, colY - 18, 22)
  local emptyText = child:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  emptyText:SetPoint("TOP", 0, -40)
  emptyText:SetText("Nothing matches these filters.")

  local footer = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footer:SetPoint("BOTTOMLEFT", 6, 4)
  footer:SetText("Click a rank: add a teacher to your route  ·  Shift-click: new route to all its teachers  ·  Click an ability to collapse")

  local rows = {}

  local function BestTeacher(r, zone)
    local best, bs
    for _, t in ipairs(r.teachers) do
      local s = (ns.InZone(t, zone) and 0 or 2) + (ns.CanTame(t) and 0 or 1)
      if not bs or s < bs then best, bs = t, s end
    end
    return best
  end

  local function RowTooltip(row)
    local d = row.data
    if not d then return end
    local ab = d.ab
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if d.header then
      GameTooltip:AddLine(ab.name, 1, 0.82, 0)
      GameTooltip:AddLine(ab.isAll and "All pet families" or ab.famText, 1, 1, 1, true)
      GameTooltip:AddLine(ab.src == "trainer" and "Bought from a Pet Trainer" or "Learned by taming a beast that has it", 0.6, 0.8, 1)
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(ns.db.collapsed[ab.name] and "Click to expand" or "Click to collapse", 0.5, 0.5, 0.5)
      GameTooltip:Show()
      return
    end
    local r = d.rank
    GameTooltip:AddLine(("%s (Rank %d)"):format(ab.name, r.rank), 1, 0.82, 0)
    GameTooltip:AddLine(r.effect, 1, 1, 1, true)
    GameTooltip:AddLine(("Pet level %d  -  %d TP"):format(r.level, r.tp), 0.8, 0.8, 0.8)
    if not d.status and r.level > ns.PetLevel() then
      GameTooltip:AddLine(("You can learn it now - your pet needs level %d to use it."):format(r.level), 1, 0.56, 0.25, true)
    end
    if d.status == "known" then
      GameTooltip:AddLine("Learned", 0.25, 1, 0.25)
    elseif d.status == "implied" then
      GameTooltip:AddLine("Not needed - you know a higher rank", 0.25, 0.8, 0.25)
    end
    GameTooltip:AddLine(" ")
    if ab.src == "trainer" then
      GameTooltip:AddLine("Bought from a Pet Trainer", 0.6, 0.8, 1)
    elseif #r.teachers == 0 then
      GameTooltip:AddLine("No known training source", 0.6, 0.6, 0.6)
    else
      GameTooltip:AddLine("Tame one of these:", 1, 0.82, 0)
      local zone = ns.CurrentZone()
      for _, t in ipairs(r.teachers) do
        local here = ns.InZone(t, zone)
        local tame = ns.CanTame(t)
        GameTooltip:AddDoubleLine(("%s (%s %s)%s"):format(t.name, t.family, t.level, Geo.Tag(t.name)), t.zone,
          here and 0.25 or (tame and 1 or 0.6), here and 1 or (tame and 1 or 0.6), here and 0.25 or (tame and 1 or 0.6),
          here and 0.25 or 0.7, here and 1 or 0.7, here and 0.25 or 0.7)
      end
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Click: waypoint  ·  Shift-click: waypoints to all", 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
  end

  local function FS(parent, x, w)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", x, 0)
    if w then fs:SetWidth(w) end
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
  end

  local function GetRow(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, child)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.line = C(0.85, 0.65, 0.15, 0.35, row:CreateTexture(nil, "BORDER"))
    row.line:SetHeight(1)
    row.line:SetPoint("BOTTOMLEFT")
    row.line:SetPoint("BOTTOMRIGHT")

    row.toggle = row:CreateTexture(nil, "ARTWORK")
    row.toggle:SetSize(14, 14)
    row.toggle:SetPoint("LEFT", 4, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 22, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.head = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.head:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.tag:SetPoint("RIGHT", -8, 0)
    row.tag:SetJustifyH("RIGHT")
    row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.sub:SetPoint("LEFT", row.head, "RIGHT", 10, 0)
    row.sub:SetPoint("RIGHT", row.tag, "LEFT", -10, 0)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)

    row.box = row:CreateTexture(nil, "ARTWORK")
    row.box:SetSize(16, 16)
    row.box:SetPoint("LEFT", COL.check, 0)
    row.box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    row.check = row:CreateTexture(nil, "OVERLAY")
    row.check:SetAllPoints(row.box)
    row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    row.c1 = FS(row, COL.rank, 58)
    row.c2 = FS(row, COL.lvl, 56)
    row.c3 = FS(row, COL.tp, 40)
    row.c4 = FS(row, COL.pet, 50)
    row.c5 = FS(row, COL.src, LIST_W - COL.src - 6)

    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(self)
      local d = self.data
      if not d then return end
      if d.header then
        ns.db.collapsed[d.ab.name] = (not ns.db.collapsed[d.ab.name]) or nil
        p.Refresh()
        if GameTooltip:GetOwner() == self then RowTooltip(self) end
        return
      end
      local r = d.rank
      if d.ab.src == "trainer" or #r.teachers == 0 then return end
      if IsShiftKeyDown() then
        local list = {}
        for i2, t in ipairs(r.teachers) do
          if i2 > 12 then break end
          list[#list + 1] = { t = t, label = Geo.Label(d.ab, r, t) }
        end
        Geo.WaypointMany(list)
      else
        local t = BestTeacher(r, ns.CurrentZone())
        if t then Geo.Waypoint(t, Geo.Label(d.ab, r, t)) end
      end
    end)
    rows[i] = row
    return row
  end

  local function SourceText(ab, r, zone)
    if ab.src == "trainer" then return "|cff99ccffPet Trainer (any major city)|r" end
    if #r.teachers == 0 then return "|cff808080No known source|r" end
    local list = {}
    for _, t in ipairs(r.teachers) do list[#list + 1] = t end
    table.sort(list, function(a, b)
      local ah, bh = ns.InZone(a, zone), ns.InZone(b, zone)
      if ah ~= bh then return ah end
      return a.minLevel < b.minLevel
    end)
    local parts = {}
    for i = 1, math.min(2, #list) do
      local t = list[i]
      if ns.InZone(t, zone) then
        parts[i] = ("%s%s (%s, %s)|r%s"):format(GREEN, t.name, t.level, t.zone, Geo.Tag(t.name))
      else
        parts[i] = ("|cffffffff%s|r |cff9d9d9d(%s, %s)|r%s"):format(t.name, t.level, t.zone, Geo.Tag(t.name))
      end
    end
    local s = table.concat(parts, "; ")
    if #list > 2 then s = s .. (" |cff808080+%d more|r"):format(#list - 2) end
    return s
  end

  local function Matches(s, ab, r)
    if not s or s == "" then return true end
    if ab.name:lower():find(s, 1, true) then return true end
    for _, t in ipairs(r.teachers) do
      if t.name:lower():find(s, 1, true) or t.zone:lower():find(s, 1, true) or t.family:lower():find(s, 1, true) then
        return true
      end
    end
  end

  function p.Refresh()
    if not p:IsShown() then return end
    local o, lvl, fam, zone = ns.db.opts, ns.PetLevel(), ns.PetFamily(), ns.CurrentZone()
    local s = ns.search
    local searching = s and s ~= ""
    local entries = {}

    for _, ab in ipairs(abilities) do
      local show = not (o.hideTrainer and ab.src == "trainer")
        and not (o.petOnly and not ns.AbilityFitsPet(ab, fam))
        and not (o.zoneOnly and ab.src == "trainer")
      if show then
        local list, have, hereCount = {}, 0, 0
        for _, r in ipairs(ab.parsed) do
          local st = ns.Status(ab, r.rank)
          if st then have = have + 1 end
          local here = ns.HasTeacherHere(r, zone)
          if here and not st then hereCount = hereCount + 1 end
          if not (o.hideKnown and st) and not (o.hideHigh and r.level > lvl)
            and not (o.zoneOnly and not here) and Matches(s, ab, r) then
            list[#list + 1] = { ab = ab, rank = r, status = st }
          end
        end
        if #list > 0 then
          entries[#entries + 1] = { header = true, ab = ab, have = have, here = hereCount }
          if searching or not ns.db.collapsed[ab.name] then
            for _, e in ipairs(list) do entries[#entries + 1] = e end
          end
        end
      end
    end

    local y, stripe = 0, 0
    for i, d in ipairs(entries) do
      local row = GetRow(i)
      row.data = d
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
      row:SetPoint("RIGHT", child, "RIGHT")
      row:Show()
      if d.header then
        local ab = d.ab
        row:SetHeight(HEAD_H)
        y = y + HEAD_H
        stripe = 0
        row.bg:SetColorTexture(0.45, 0.33, 0.05, 0.28)
        row.line:Show()
        row.box:Hide(); row.check:Hide()
        for _, c in ipairs({ row.c1, row.c2, row.c3, row.c4, row.c5 }) do c:Hide() end
        row.toggle:Show(); row.icon:Show(); row.head:Show(); row.sub:Show(); row.tag:Show()
        local collapsed = ns.db.collapsed[ab.name] and not searching
        row.toggle:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
        row.icon:SetTexture(ab.icon)
        local complete = d.have == #ab.parsed
        row.head:SetText(complete and (GREEN .. ab.name .. "|r") or ab.name)
        local fams = ab.isAll and "all families" or ab.famText
        row.sub:SetText(("|cffffffff%d/%d|r   %s"):format(d.have, #ab.parsed, fams))
        if d.here > 0 then
          row.tag:SetText(("%s%d tameable here|r"):format(GREEN, d.here))
        elseif complete then
          row.tag:SetText(GREEN .. "Complete|r")
        elseif ab.src == "trainer" then
          row.tag:SetText("|cff99ccffPet Trainer|r")
        else
          row.tag:SetText("")
        end
      else
        local r = d.rank
        row:SetHeight(ROW_H)
        y = y + ROW_H
        stripe = stripe + 1
        row.bg:SetColorTexture(1, 1, 1, stripe % 2 == 0 and 0.04 or 0)
        row.line:Hide()
        row.toggle:Hide(); row.icon:Hide(); row.head:Hide(); row.sub:Hide(); row.tag:Hide()
        for _, c in ipairs({ row.c1, row.c2, row.c3, row.c4, row.c5 }) do c:Show() end
        row.box:Show()
        row.check:SetShown(d.status ~= nil)
        row.check:SetAlpha(d.status == "implied" and 0.45 or 1)
        -- grey = you can't get it yet (no teacher you can tame at your level)
        -- orange pet lvl = you can learn it now, your pet just can't use it yet
        local canGet = d.ab.src == "trainer" or #r.teachers == 0
        if not canGet then
          for _, t in ipairs(r.teachers) do
            if ns.CanTame(t) then canGet = true break end
          end
        end
        local color
        if d.status == "known" then color = GREEN
        elseif d.status == "implied" then color = "|cff5f9f5f"
        elseif not canGet then color = "|cff808080"
        else color = "|cffffffff" end
        row.c1:SetText(color .. "Rank " .. r.rank .. "|r")
        if not d.status and r.level > lvl then
          row.c2:SetText("|cffff9040" .. r.level .. "|r")
        else
          row.c2:SetText(color .. r.level .. "|r")
        end
        row.c3:SetText(color .. r.tp .. "|r")
        row.c4:SetText(ns.petHas[ns.Key(d.ab.name, r.rank)] and "|cff69ccf0On pet|r" or "")
        row.c5:SetText(SourceText(d.ab, r, zone))
      end
    end
    for i = #entries + 1, #rows do rows[i]:Hide(); rows[i].data = nil end
    emptyText:SetShown(#entries == 0)
    child:SetHeight(math.max(1, y))
  end
  p:SetScript("OnShow", p.Refresh)
end

------------------------------------------------------------------------
-- Tab 2: Hunt Planner
------------------------------------------------------------------------
do
  local p = panels[2]
  local intro = Text(p, "GameFontHighlightSmall", 6, -4)
  intro:SetWidth(WIDTH - 40)
  Check(p, "My pet's family only", "huntPetOnly", 2, -34, "Only count abilities your current pet's family can use.")
  Check(p, "Include dungeons", "huntDungeons", 160, -34, "Also count beasts that live inside dungeons.")
  Check(p, "Sort by most new ranks", "huntSortCount", 290, -34, "Show the zones with the most new ranks first, instead of lowest level first.")
  Check(p, "Show enemy faction zones", "huntBothFactions", 470, -34,
    "Also list zones that belong to the other faction (marked in red). Contested zones are always shown.")
  Check(p, "Show my current zone first", "huntHereFirst", 2, -56,
    "If the zone you're in has something to tame, list it at the top.")
  local questieNote = Text(p, "GameFontHighlightSmall", 210, -61)
  questieNote:SetWidth(WIDTH - 250)
  questieNote:SetWordWrap(false)
  Divider(p, -82)
  local L = MakeList(p, -86, 4)

  local function TeacherList(e)
    local names = {}
    for i, t in ipairs(e.teachers) do
      if i > 3 then names[#names + 1] = ("|cff808080+%d more|r"):format(#e.teachers - 3) break end
      names[#names + 1] = ("%s |cff9d9d9d(%s)|r%s"):format(t.name, t.level, Geo.Tag(t.name))
    end
    return table.concat(names, ", ")
  end

  local function WaypointItems(entries)
    local list = {}
    for _, e in ipairs(entries) do
      for _, t in ipairs(e.teachers) do
        if #list >= 15 then return list end
        list[#list + 1] = { t = t, label = Geo.Label(e.ab, e.rank, t) }
      end
    end
    return list
  end

  function p.Refresh()
    if not p:IsShown() then return end
    local o = ns.db.opts
    intro:SetText(("Zones with ranks you can tame at |cffffffffyour level (%d)|r, %s. " ..
      "Only the highest missing rank of each ability is counted - it covers the lower ones."):format(ns.PlayerLevel(),
      o.huntSortCount and "most new ranks first" or "lowest level first"))
    local plan = ns.HuntPlan(o.huntPetOnly, o.huntDungeons, o.huntSortCount and "count" or "level")
    local items = {}
    local lvl = ns.PlayerLevel()
    questieNote:SetText(Geo.HasQuestie() and ""
      or "|cffff9040Questie not installed: routes only include beasts you've spotted yourself.|r")

    -- the zone you're standing in goes first
    if o.huntHereFirst then
      for i, z in ipairs(plan) do
        if z.here then
          table.remove(plan, i)
          table.insert(plan, 1, z)
          break
        end
      end
    end

    for _, z in ipairs(plan) do
      local n = #z.entries
      -- level range: grey = outlevelled, green = your level, orange = above you
      local rc = (z.maxLevel < lvl) and "|cff9d9d9d" or ((z.minLevel > lvl) and "|cffff9040" or GREEN)
      local range = z.minLevel > 0 and ("  %s(%d-%d)|r"):format(rc, z.minLevel, z.maxLevel) or ""
      if ns.ZoneHostile(z.zone) then range = range .. ("  |cffff4040%s|r"):format(ns.ZoneFaction(z.zone)) end
      items[#items + 1] = {
        kind = "head",
        left = ("%s%s|r%s"):format(z.here and GREEN or "|cffffffff", z.zone, range),
        right = ("%s%d new rank%s|r%s"):format(GREEN, n, n == 1 and "" or "s", z.here and "  |cff40ff40(you're here)|r" or ""),
        button = { text = "Waypoints", onClick = function() Geo.WaypointMany(WaypointItems(z.entries)) end },
        tip = function(tt)
          tt:AddLine(z.zone, 1, 0.82, 0)
          if z.minLevel > 0 then tt:AddLine(("Recommended level %d-%d"):format(z.minLevel, z.maxLevel), 0.8, 0.8, 0.8) end
          for _, e in ipairs(z.entries) do tt:AddLine(("%s %d"):format(e.ab.name, e.rank.rank), 1, 1, 1) end
          tt:AddLine(" ")
          tt:AddLine("Waypoints: mark these beasts (TomTom arrows if installed)", 0.5, 0.5, 0.5)
        end,
      }
      for _, e in ipairs(z.entries) do
        items[#items + 1] = {
          kind = "row", icon = e.ab.icon, indent = 24,
          left = ("|cffffffff%s %d|r   %s"):format(e.ab.name, e.rank.rank, TeacherList(e)),
          right = ("|cff9d9d9dpet lvl %d|r"):format(e.rank.level),
          onClick = function()
            local list = {}
            for _, t in ipairs(e.teachers) do list[#list + 1] = { t = t, label = Geo.Label(e.ab, e.rank, t) } end
            Geo.WaypointMany(list)
          end,
          tip = function(tt)
            tt:AddLine(("%s (Rank %d)"):format(e.ab.name, e.rank.rank), 1, 0.82, 0)
            tt:AddLine(e.rank.effect, 1, 1, 1, true)
            tt:AddLine(" ")
            for _, t in ipairs(e.teachers) do
              tt:AddDoubleLine(t.name .. Geo.Tag(t.name), ("%s %s"):format(t.family, t.level), 1, 1, 1, 0.7, 0.7, 0.7)
            end
            tt:AddLine(" ")
            tt:AddLine("Click: waypoints to these beasts", 0.5, 0.5, 0.5)
          end,
        }
      end
    end
    ListSet(L, items, "Nothing left to tame at your level - nice!")
  end
  p:SetScript("OnShow", p.Refresh)
end

------------------------------------------------------------------------
-- Tab 3: Rare Pets (a collection: they don't teach anything unique)
------------------------------------------------------------------------
do
  local p = panels[ns.TAB.rares]
  local intro = Text(p, "GameFontHighlightSmall", 6, -4)
  intro:SetWidth(WIDTH - 40)
  Check(p, "Rares", "spShowRare", 2, -30, "Show rare pets.")
  Check(p, "Elites", "spShowElite", 72, -30, "Show elite pets (tough in the wild, normal once tamed).")
  Check(p, "Quest spawns", "spShowSpawned", 142, -30, "Show pets that only appear through a quest or trigger.")
  Check(p, "Dungeon / raid", "spShowDungeon", 248, -30, "Include pets that live inside dungeons and raids.")
  Check(p, "Hide tamed", "rareHideTamed", 362, -30, "Hide pets you've already tamed.")
  Check(p, "Hide above my level", "rareHideHigh", 450, -30, "Hide pets you're too low level to tame yet.")
  Check(p, "Fastest first", "rareSortSpeed", 590, -30, "Sort by attack speed (lowest number = fastest).")
  Check(p, "Show untamed specials on the map", "rarePins", 2, -52,
    "Pins for untamed rares (and outdoor elites / quest spawns) you can tame, even if they teach nothing you need.")
  local count = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  count:SetPoint("TOPRIGHT", -8, -56)

  -- columns (x is relative to the row)
  local COLS = {
    { x = 52, w = 132, head = "Name" },
    { x = 186, w = 72, head = "Type" },
    { x = 260, w = 66, head = "Family" },
    { x = 328, w = 34, head = "Lvl" },
    { x = 364, w = 58, head = "Atk speed" },
    { x = 424, w = 104, head = "Traits" },
    { x = 530, w = 104, head = "Zone" },
  }
  local headY = -80
  for _, c in ipairs(COLS) do
    local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", 2 + c.x, headY)
    fs:SetText(c.head)
  end
  local st = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  st:SetPoint("TOPRIGHT", -34, headY)
  st:SetText("Status")
  Divider(p, headY - 14)
  local L = MakeList(p, headY - 18, 22)
  local footer = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footer:SetPoint("BOTTOMLEFT", 6, 4)
  footer:SetText("Click: details & 3D model  ·  Shift-click: waypoint  ·  Right-click: mark tamed / not tamed (with that pet out, links it)  ·  Normal speed 2.0")

  local function SpeedCell(speed)
    if not speed then return "|cff808080?|r" end
    local s = ns.RS.SpeedText(speed)
    if speed < 2.0 then return s .. " |cff40ff40fast|r" end
    if speed > 2.0 then return s .. " |cffff9040slow|r" end
    return s
  end

  ----------------------------------------------------------------------
  -- Drawer: slides out beside the window with a 3D model and details
  ----------------------------------------------------------------------
  local DW = 270
  local drawer = CreateFrame("Frame", "BeastTrainingTrackerKuroPetDrawer", f, BackdropTemplateMixin and "BackdropTemplate" or nil)
  drawer:SetSize(DW, HEIGHT - 40)
  drawer:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1)) -- slides out from behind the window
  drawer:EnableMouse(true)
  drawer:Hide()
  if drawer.SetBackdrop then
    drawer:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    drawer:SetBackdropBorderColor(0.67, 0.83, 0.45, 0.9)
  end
  local dClose = CreateFrame("Button", nil, drawer, "UIPanelCloseButton")
  dClose:SetPoint("TOPRIGHT", -2, -2)
  dClose:SetScript("OnClick", function() drawer:Hide() end)

  local dName = drawer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  dName:SetPoint("TOPLEFT", 14, -14)
  dName:SetPoint("RIGHT", -30, 0)
  dName:SetJustifyH("LEFT")
  local dSub = drawer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  dSub:SetPoint("TOPLEFT", dName, "BOTTOMLEFT", 0, -4)
  dSub:SetPoint("RIGHT", -14, 0)
  dSub:SetJustifyH("LEFT")

  -- 3D model: drag to turn, wheel to zoom, slowly spins until you touch it
  local model = CreateFrame("PlayerModel", nil, drawer)
  model:SetPoint("TOPLEFT", 10, -56)
  model:SetPoint("TOPRIGHT", -10, -56)
  model:SetHeight(220)
  local modelBg = C(0, 0, 0, 0.35, model:CreateTexture(nil, "BACKGROUND"))
  modelBg:SetAllPoints()
  local noModel = model:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  noModel:SetPoint("CENTER")
  noModel:SetWidth(DW - 40)
  local modelHint = drawer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  modelHint:SetPoint("TOP", model, "BOTTOM", 0, -2)
  modelHint:SetText("Drag to turn  ·  Mouse wheel to zoom")

  local facing, zoom, spin, dragX = 0, 1, true, nil
  model:EnableMouse(true)
  model:EnableMouseWheel(true)
  model:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then dragX, spin = GetCursorPosition(), false end
  end)
  model:SetScript("OnMouseUp", function() dragX = nil end)
  model:SetScript("OnMouseWheel", function(self, delta)
    zoom = math.min(3, math.max(0.4, zoom - delta * 0.15))
    if self.SetCamDistanceScale then self:SetCamDistanceScale(zoom) end
  end)
  model:SetScript("OnUpdate", function(self, elapsed)
    if dragX then
      local x = GetCursorPosition()
      facing = facing + (x - dragX) * 0.02
      dragX = x
      self:SetFacing(facing)
    elseif spin then
      facing = facing + elapsed * 0.6
      self:SetFacing(facing)
    end
  end)

  -- NPC id: our rare list first, then Questie
  local function NpcId(name)
    if ns.rareIds and ns.rareIds[name] then return ns.rareIds[name] end
    if Geo.HasQuestie() then
      local ok, ids = pcall(NpcDB.IdsByName, name)
      if ok and ids and ids[1] then return ids[1] end
    end
  end

  local function ShowModel(name)
    facing, zoom, spin = 0, 1, true
    model:ClearModel()
    local id = NpcId(name)
    if not id or not model.SetCreature then
      noModel:SetText("No 3D model available for this beast yet." ..
        (Geo.HasQuestie() and "" or "\n\nInstall Questie to see models of elites and quest spawns."))
      noModel:Show()
      return
    end
    noModel:Hide()
    model:SetCreature(id)
    if model.SetCamDistanceScale then model:SetCamDistanceScale(zoom) end
    model:SetFacing(facing)
    -- the creature may not be in your game cache yet; try again shortly
    if C_Timer then
      C_Timer.After(0.5, function()
        if drawer:IsShown() and drawer.name == name then model:SetCreature(id); model:SetFacing(facing) end
      end)
    end
  end

  local dInfo = drawer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  dInfo:SetPoint("TOPLEFT", model, "BOTTOMLEFT", 4, -20)
  dInfo:SetPoint("RIGHT", -14, 0)
  dInfo:SetJustifyH("LEFT")
  dInfo:SetJustifyV("TOP")
  dInfo:SetSpacing(3)

  local current -- the rare shown in the drawer
  local dWaypoint = Button(drawer, "Waypoint", 110, function()
    if not current then return end
    local e = current.teaches[1]
    Geo.Waypoint(current.t, e and Geo.Label(e.ab, e.rank, current.t) or current.name)
  end)
  dWaypoint:SetPoint("BOTTOMLEFT", 14, 14)
  local dTamed = Button(drawer, "Mark tamed", 120, function()
    if current then ns.RS.SetTamed(current.name, not current.tamed) end
  end)
  dTamed:SetPoint("BOTTOMRIGHT", -14, 14)

  -- 1800 -> "30m", 37800 -> "10.5h", 129600 -> "36h", 259200 -> "3d"
  local function Dur(sec)
    if sec < 3600 then return math.floor(sec / 60 + 0.5) .. "m" end
    if sec <= 72 * 3600 then
      local h = math.floor(sec / 1800 + 0.5) / 2
      return (h == math.floor(h) and tostring(h) or ("%.1f"):format(h)) .. "h"
    end
    local d = math.floor(sec / 43200 + 0.5) / 2
    return (d == math.floor(d) and tostring(d) or ("%.1f"):format(d)) .. "d"
  end

  local function RespawnLine(r)
    if r.t.dungeon then return "Respawn: |cffffffffwhen the dungeon resets|r" end
    local rt = ns.respawnTimes and ns.respawnTimes[r.name]
    if not rt then return "Respawn: |cff808080unknown|r" end
    local range = rt[1] == rt[2] and Dur(rt[1]) or (Dur(rt[1]) .. " - " .. Dur(rt[2]))
    local spots = (rt[3] or 1) > 1 and ("  |cff9d9d9d(%d spawn points)|r"):format(rt[3]) or ""
    return "Respawn: |cffffffff" .. range .. "|r" .. spots
  end

  -- Family abilities this beast could learn (skipping the ones every family gets)
  local function FamilyAbilities(family)
    local list = {}
    for _, ab in ipairs(abilities) do
      if not ab.isAll and ns.AbilityFitsPet(ab, family) then list[#list + 1] = ab.name end
    end
    return table.concat(list, ", ")
  end

  local function FillDrawer(r)
    current = r
    local sp = r.t
    dName:SetText((r.tamed and "|cff9d9d9d" or "|cffff8000") .. r.name .. "|r")
    dSub:SetText(("%s  ·  %s, level %s\n|cff9d9d9d%s|r"):format(ns.RS.TypeText(sp), sp.family, sp.level, sp.zone))
    local cur = ns.RS.Info(r.name)
    local out = { "Attack speed: " .. SpeedCell(r.speed) .. "  |cff9d9d9d(normal 2.0)|r", RespawnLine(r) }
    for _, tr in ipairs(cur.traits) do out[#out + 1] = "|cffffd14d" .. tr.long .. "|r" end
    local fam = FamilyAbilities(sp.family)
    if fam ~= "" then out[#out + 1] = ("Can learn (%s): |cffd0d0d0%s|r"):format(sp.family, fam) end
    if #r.teaches > 0 then
      out[#out + 1] = " "
      for _, e in ipairs(r.teaches) do
        local k = ns.IsKnown(e.ab, e.rank.rank)
        out[#out + 1] = (k and "|cff808080" or "|cff40ff40") .. ("Teaches %s %d%s|r"):format(e.ab.name, e.rank.rank, k and " (known)" or "")
      end
    end
    if cur.tamed then
      out[#out + 1] = " "
      local nick = ns.db.tamedNicks and ns.db.tamedNicks[r.name]
      out[#out + 1] = "|cff40ff40" .. (type(cur.tamed) == "number" and ("Tamed " .. date("%b %d, %Y", cur.tamed)) or "Tamed")
        .. (nick and (" (" .. nick .. ")") or "") .. "|r"
    elseif not ns.CanTame(sp) then
      out[#out + 1] = " "
      out[#out + 1] = ("|cff808080You need level %d to tame it.|r"):format(sp.minLevel)
    end
    if cur.status then
      out[#out + 1] = " "
      out[#out + 1] = "|cffff9940RareScanner: " .. cur.status.text .. "|r"
    end
    local id = NpcId(r.name)
    if id then
      out[#out + 1] = " "
      out[#out + 1] = ("|cff808080NPC ID %d|r"):format(id)
    end
    dInfo:SetText(table.concat(out, "\n"))
    dTamed:SetText(r.tamed and "Mark not tamed" or "Mark tamed")
  end

  -- Slide out from behind the window, on whichever side has room
  local slideT
  local function Anchor(offset)
    drawer:ClearAllPoints()
    local right = (f:GetRight() or 0) + DW <= (UIParent:GetRight() or math.huge) / (f:GetEffectiveScale() / UIParent:GetEffectiveScale())
    if right then
      drawer:SetPoint("TOPLEFT", f, "TOPRIGHT", offset - DW, -20)
    else
      drawer:SetPoint("TOPRIGHT", f, "TOPLEFT", DW - offset, -20)
    end
  end
  drawer:SetScript("OnUpdate", function()
    if not slideT then return end
    local t = math.min(1, (GetTime() - slideT) / 0.18)
    Anchor(DW * (1 - (1 - t) ^ 2)) -- ease out
    if t >= 1 then slideT = nil end
  end)

  local function OpenDrawer(r)
    if drawer:IsShown() and drawer.name == r.name then drawer:Hide() return end -- click again: close
    local wasOpen = drawer:IsShown()
    drawer.name = r.name
    FillDrawer(r)
    ShowModel(r.name)
    if wasOpen then return end
    Anchor(0)
    slideT = GetTime()
    drawer:Show()
  end
  drawer:SetScript("OnHide", function() drawer.name, current, slideT = nil, nil, nil end)
  p:HookScript("OnHide", function() drawer:Hide() end)

  function p.Refresh()
    if not p:IsShown() then return end
    local o = ns.db.opts
    local linked = ns.RS.Loaded()
    intro:SetText("Rare, elite and quest-spawned beasts (Petopia). They teach the same abilities as normal beasts - what makes them special is " ..
      "their look and innate traits like attack speed, which stay with that pet. " ..
      (linked and "|cff40ff40Spawn timers from RareScanner.|r" or "|cff9d9d9dEnable RareScanner for spawn timers.|r"))

    local list = ns.RS.AllRares(o.rareSortSpeed)
    local tamed = 0
    local items = {}
    for _, r in ipairs(list) do
      if r.tamed then tamed = tamed + 1 end
      local tameable = ns.CanTame(r.t)
      local sp = r.t
      local typeOk = (o.spShowRare and sp.rare) or (o.spShowElite and sp.elite) or (o.spShowSpawned and sp.spawned)
      if typeOk and (o.spShowDungeon or not sp.dungeon)
        and not (o.rareHideTamed and r.tamed) and not (o.rareHideHigh and not tameable) then
        local nameColor = r.tamed and "|cff9d9d9d" or (tameable and "|cffff8000" or "|cff996030")
        local status
        if r.tamed then
          local nick = ns.db.tamedNicks and ns.db.tamedNicks[r.name]
          status = "|cff40ff40tamed|r" .. (nick and (" |cff9d9d9d(" .. nick .. ")|r") or "")
        elseif not tameable then
          status = ("|cff808080need lvl %d|r"):format(r.t.minLevel)
        else
          status = r.status and r.status.short or ""
        end
        local traits = {}
        for _, tr in ipairs(r.traits) do
          if tr.short ~= "" then traits[#traits + 1] = tr.short end
        end
        items[#items + 1] = {
          kind = "row", check = r.tamed, icon = r.icon, indent = 6,
          cols = {
            { x = COLS[1].x, w = COLS[1].w, text = nameColor .. r.name .. "|r" },
            { x = COLS[2].x, w = COLS[2].w, text = ns.RS.TypeText(sp) },
            { x = COLS[3].x, w = COLS[3].w, text = "|cffd0d0d0" .. sp.family .. "|r" },
            { x = COLS[4].x, w = COLS[4].w, text = (tameable and "|cffffffff" or "|cff808080") .. sp.level .. "|r" },
            { x = COLS[5].x, w = COLS[5].w, text = SpeedCell(r.speed) },
            { x = COLS[6].x, w = COLS[6].w, text = table.concat(traits, "  ") },
            { x = COLS[7].x, w = COLS[7].w, text = "|cff9d9d9d" .. sp.zone .. "|r" },
          },
          right = status,
          onClick = function()
            if IsShiftKeyDown() then
              local e = r.teaches[1]
              Geo.Waypoint(r.t, e and Geo.Label(e.ab, e.rank, r.t) or r.name)
            else
              OpenDrawer(r)
            end
          end,
          onRightClick = function()
            ns.RS.SetTamed(r.name, not r.tamed)
          end,
          tip = function(tt)
            local cur = ns.RS.Info(r.name)
            tt:AddLine(r.name .. "  " .. ns.RS.TypeText(r.t), 1, 0.82, 0)
            tt:AddLine(("%s, level %s - %s"):format(r.t.family, r.t.level, r.t.zone), 0.8, 0.8, 0.8)
            tt:AddLine("Attack speed: " .. SpeedCell(r.speed) .. "  |cff9d9d9d(normal 2.0, lower = faster)|r", 1, 1, 1)
            for _, tr in ipairs(cur.traits) do tt:AddLine(tr.long, 1, 0.82, 0.3, true) end
            if cur.tamed then
              tt:AddLine(type(cur.tamed) == "number" and ("Tamed " .. date("%b %d, %Y", cur.tamed)) or "Tamed", 0.25, 1, 0.25)
            end
            if #r.teaches > 0 then
              tt:AddLine(" ")
              for _, e in ipairs(r.teaches) do
                local k = ns.IsKnown(e.ab, e.rank.rank)
                tt:AddLine(("Teaches %s %d%s"):format(e.ab.name, e.rank.rank, k and " (known)" or ""),
                  k and 0.5 or 0.25, k and 0.5 or 1, k and 0.5 or 0.25)
              end
            end
            if cur.status then
              tt:AddLine(" ")
              tt:AddLine("RareScanner: " .. cur.status.text, 1, 0.6, 0.25, true)
            end
            tt:AddLine(" ")
            tt:AddLine("Click: details & 3D model  ·  Shift-click: waypoint  ·  Right-click: toggle tamed", 0.5, 0.5, 0.5, true)
          end,
        }
      end
    end
    count:SetText(("Tamed |cffffffff%d / %d|r"):format(tamed, #list))
    ListSet(L, items, "Nothing matches these filters.")
    if drawer:IsShown() then
      for _, r in ipairs(list) do
        if r.name == drawer.name then FillDrawer(r) break end
      end
    end
  end
  p:SetScript("OnShow", p.Refresh)
end

------------------------------------------------------------------------
-- Tab 4: My Pet
------------------------------------------------------------------------
do
  local p = panels[ns.TAB.pet]
  local summary = Text(p, "GameFontNormal", 6, -6)
  local tpText = Text(p, "GameFontHighlightSmall", 6, -26)
  local hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPRIGHT", -6, -10)
  hint:SetJustifyH("RIGHT")
  hint:SetText("Use the |cffffffffBeast Training|r button (top right) to teach")
  Check(p, "Remind me about upgrades", "upgradeAlert", 2, -44, "Chat reminder when you know a better rank than your pet has.")
  Check(p, "Pet level-up nudges", "levelNudge", 200, -44, "Chat message when your pet reaches the level for a new rank.")
  Divider(p, -70)
  local L = MakeList(p, -74, 4)

  function p.Refresh()
    if not p:IsShown() then return end
    if not UnitExists("pet") then
      summary:SetText("|cff9d9d9dSummon your pet to see upgrades for it.|r")
      tpText:SetText("")
      ListSet(L, {}, "No pet out")
      return
    end
    ns.ScanPet()
    local fam, plvl = ns.PetFamily() or "?", ns.PetLevel()
    summary:SetText(("%s  |cffffffff%s, level %d|r"):format(UnitName("pet") or "Pet", fam, plvl))
    if GetPetTrainingPoints then
      local total, spent = GetPetTrainingPoints()
      if total then
        tpText:SetText(("Training points: |cffffffff%d free|r of %d"):format((total or 0) - (spent or 0), total or 0))
      else
        tpText:SetText("")
      end
    else
      tpText:SetText("")
    end

    local items = {}
    -- Upgrades
    local ups = ns.Upgrades()
    items[#items + 1] = { kind = "head", left = "Upgrades", right = #ups > 0 and (GREEN .. #ups .. " available|r") or "|cff9d9d9dnone|r" }
    if #ups == 0 then
      items[#items + 1] = { kind = "note", left = "Your pet already has the best rank you know of everything it uses.", indent = 24 }
    end
    for _, u in ipairs(ups) do
      items[#items + 1] = {
        kind = "row", icon = u.ab.icon, indent = 24,
        left = ("|cffffffff%s|r   pet has %d  ->  you know %d"):format(u.ab.name, u.from, u.to),
        right = u.needLevel and ("|cff808080pet needs lvl %d|r"):format(u.needLevel) or (GREEN .. "teach it now|r"),
      }
    end

    -- Coming up
    local soon = ns.ComingUp(6)
    items[#items + 1] = { kind = "head", left = "Coming up (next 6 pet levels)", right = "" }
    if #soon == 0 then
      items[#items + 1] = { kind = "note", left = "No new ranks for your pet's abilities in the next 6 levels.", indent = 24 }
    end
    for _, s in ipairs(soon) do
      items[#items + 1] = {
        kind = "row", icon = s.ab.icon, indent = 24,
        left = ("|cffffd100Lvl %d|r   |cffffffff%s %d|r"):format(s.rank.level, s.ab.name, s.rank.rank),
        right = s.known and (GREEN .. "already learned|r") or ("|cff9d9d9d" .. ns.TeacherZones(s.ab, s.rank, 2) .. "|r"),
        tip = not s.known and function(tt)
          tt:AddLine(("%s (Rank %d)"):format(s.ab.name, s.rank.rank), 1, 0.82, 0)
          for _, t in ipairs(s.rank.teachers) do
            tt:AddDoubleLine(t.name .. Geo.Tag(t.name), t.zone, 1, 1, 1, 0.7, 0.7, 0.7)
          end
        end or nil,
      }
    end

    -- Known abilities the pet could use but doesn't have
    local fam2 = ns.PetFamily()
    local extra = {}
    for _, ab in ipairs(abilities) do
      if not ns.petRank[ab.name] and ns.AbilityFitsPet(ab, fam2) then
        local best = ns.BestKnown(ab, plvl)
        if best > 0 then extra[#extra + 1] = { ab = ab, rank = best } end
      end
    end
    items[#items + 1] = { kind = "head", left = "You know these, your pet doesn't have them", right = "" }
    if #extra == 0 then
      items[#items + 1] = { kind = "note", left = "Nothing else you've learned fits this pet right now.", indent = 24 }
    end
    for _, x in ipairs(extra) do
      local r = x.ab.parsed[x.rank]
      items[#items + 1] = {
        kind = "row", icon = x.ab.icon, indent = 24,
        left = ("|cffffffff%s %d|r"):format(x.ab.name, x.rank),
        right = r and ("|cff9d9d9d%d TP|r"):format(r.tp) or "",
      }
    end
    ListSet(L, items)
  end
  p:SetScript("OnShow", p.Refresh)
end

------------------------------------------------------------------------
-- Tab 5: Settings (optional addons, map, alerts, tracker, minimap)
------------------------------------------------------------------------
local mmCheck
do
  local p = panels[ns.TAB.map]
  local y = -2
  local function Section(text)
    local fs = Text(p, "GameFontNormal", 6, y, text)
    Divider(p, y - 16)
    y = y - 22
    return fs
  end

  -- Optional addons: green = detected, grey = not installed
  Section("Optional addons  |cff9d9d9d- BeastTrainingTracker.Kuro works on its own; these add extras|r")
  local addonRows = {}
  for i = 1, 3 do
    local r = {}
    r.dot = p:CreateTexture(nil, "ARTWORK")
    r.dot:SetSize(12, 12)
    r.dot:SetPoint("TOPLEFT", 10, y - 2)
    r.name = Text(p, "GameFontHighlight", 28, y)
    r.text = Text(p, "GameFontHighlightSmall", 130, y - 1)
    r.text:SetWidth(WIDTH - 180)
    r.text:SetWordWrap(false)
    addonRows[i] = r
    y = y - 18
  end
  y = y - 8

  Section("Map pins")
  -- What to pin on each map: click to cycle through the modes
  local PIN_MODES = {
    { key = "none", text = "None", tip = "No pins on this map." },
    { key = "ability", text = "One per ability", tip = "One pin per missing ability: the closest beast that teaches it. The fewest pins." },
    { key = "nearest", text = "Nearest spawn only", tip = "One pin per beast: the spawn point closest to you (closest to the middle of its range on other maps)." },
    { key = "all", text = "All spawns", tip = "Every known spawn point of every beast you need. Can be a lot of pins." },
  }
  local function PinModeButton(label, key, x, w)
    local b = Button(p, "", w, nil)
    b:SetPoint("TOPLEFT", x, y)
    local function Index()
      local cur = ns.db and ns.db.opts[key]
      for i, m in ipairs(PIN_MODES) do if m.key == cur then return i end end
      return 2
    end
    function b.Refresh() b:SetText(label .. ": " .. PIN_MODES[Index()].text) end
    b:SetScript("OnClick", function()
      ns.db.opts[key] = PIN_MODES[Index() % #PIN_MODES + 1].key
      b.Refresh()
      Geo.QueuePins(true)
      if GameTooltip:IsOwned(b) then b:GetScript("OnEnter")(b) end
    end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(label, 1, 0.82, 0)
      local cur = ns.db and ns.db.opts[key]
      for _, m in ipairs(PIN_MODES) do
        GameTooltip:AddLine((m.key == cur and "|cff40ff40> " or "|cffffffff  ") .. m.text .. "|r - " .. m.tip, 1, 1, 1, true)
      end
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Click to switch", 0.5, 0.5, 0.5)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
  end
  local mapPinMode = PinModeButton("World map pins", "mapPinMode", 4, 280)
  local miniPinMode = PinModeButton("Minimap pins", "minimapPinMode", 300, 280)
  y = y - 26
  Check(p, "Hide ALL beast pins", "pinsOff", 4, y, "Master switch for every pin this addon draws. Same as right-clicking the minimap button.",
    function() Geo.QueuePins(true) end)
  Check(p, "Show untamed special pets on the map", "rarePins", 300, y, "Pins for untamed rares (and outdoor elites / quest spawns) you can tame, even if they teach nothing you need.")
  y = y - 24
  do
    local miniNote = ns.Client.StableMasterMinimapPinsWanted()
      and "Shown on the world map and the minimap (this client has no native stable master tracking)."
      or "Shown on the world map. " .. (ns.Client.StableMasterNativeTrackingHint() or "")
    Check(p, "Stable master pins", "stablePins", 4, y,
      "Every stable master friendly to your faction, from QuestieDB. Click a pin to set a waypoint; /bttk stable finds the nearest. " .. miniNote,
      function() Geo.QueuePins(true) end)
  end
  y = y - 24
  Check(p, "Open the map on the first waypoint", "routeOpenMap", 4, y, "When you set waypoints, open the world map on the first stop (not in combat).")
  Check(p, "Draw the hunt route on the world map", "routeLines", 300, y, "Numbered stops joined by a dotted line, nearest first. Pick the color and opacity below.", function() ns.Geo.DrawRoute() end)
  y = y - 36

  -- Route line color + opacity
  local colorLabel = Text(p, "GameFontHighlightSmall", 10, y - 5, "Route line color")
  local swatch = CreateFrame("Button", nil, p, BackdropTemplateMixin and "BackdropTemplate" or nil)
  swatch:SetSize(48, 20)
  swatch:SetPoint("LEFT", colorLabel, "RIGHT", 12, 0)
  if swatch.SetBackdrop then
    swatch:SetBackdrop({ edgeFile = "Interface\Tooltips\UI-Tooltip-Border", edgeSize = 8 })
    swatch:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
  end
  swatch.color = swatch:CreateTexture(nil, "ARTWORK")
  swatch.color:SetPoint("TOPLEFT", 3, -3)
  swatch.color:SetPoint("BOTTOMRIGHT", -3, 3)

  local function SetRouteColor(r, g, b)
    ns.db.opts.routeColor = { r = r, g = g, b = b }
    swatch.color:SetColorTexture(r, g, b, 1)
    ns.Geo.DrawRoute()
  end

  swatch:SetScript("OnClick", function()
    local r, g, b = ns.Geo.RouteColor()
    local function apply() SetRouteColor(ColorPickerFrame:GetColorRGB()) end
    local function cancel() SetRouteColor(r, g, b) end
    if ColorPickerFrame.SetupColorPickerAndShow then
      ColorPickerFrame:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false, swatchFunc = apply, cancelFunc = cancel })
    else
      ColorPickerFrame.hasOpacity = false
      ColorPickerFrame.opacityFunc = nil
      ColorPickerFrame.previousValues = { r, g, b }
      ColorPickerFrame.func = apply
      ColorPickerFrame.cancelFunc = cancel
      ColorPickerFrame:SetColorRGB(r, g, b)
      ColorPickerFrame:Hide()
      ColorPickerFrame:Show()
    end
  end)
  swatch:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Route line color", 1, 0.82, 0)
    GameTooltip:AddLine("Click to pick the color of the dotted hunt route on the world map.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  swatch:SetScript("OnLeave", GameTooltip_Hide)

  local alpha = CreateFrame("Slider", "BeastTrainingTrackerKuroRouteAlpha", p, "OptionsSliderTemplate")
  alpha:SetWidth(150)
  alpha:SetPoint("TOPLEFT", 220, y - 10) -- same column as the pin opacity slider below
  alpha:SetMinMaxValues(0.1, 1)
  alpha:SetValueStep(0.05)
  if alpha.SetObeyStepOnDrag then alpha:SetObeyStepOnDrag(true) end
  local low = alpha.Low or _G["BeastTrainingTrackerKuroRouteAlphaLow"]
  local high = alpha.High or _G["BeastTrainingTrackerKuroRouteAlphaHigh"]
  local label = alpha.Text or _G["BeastTrainingTrackerKuroRouteAlphaText"]
  if low then low:SetText("10%") end
  if high then high:SetText("100%") end
  alpha:SetScript("OnValueChanged", function(self, v)
    v = math.floor(v * 20 + 0.5) / 20
    if label then label:SetText(("Route opacity: %d%%"):format(v * 100)) end
    if ns.db and ns.db.opts.routeAlpha ~= v then
      ns.db.opts.routeAlpha = v
      ns.Geo.DrawRoute()
    end
  end)

  local resetColor = Button(p, "Default", 80, function()
    local d = ns.Geo.ROUTE_DEFAULT
    ns.db.opts.routeAlpha = d.a
    alpha:SetValue(d.a)
    SetRouteColor(d.r, d.g, d.b)
  end)
  resetColor:SetPoint("TOPRIGHT", -8, y - 8)

  -- current values, filled in whenever Settings refreshes
  local function ShowRouteColor()
    local r, g, b, a = ns.Geo.RouteColor()
    swatch.color:SetColorTexture(r, g, b, 1)
    alpha:SetValue(a)
  end
  y = y - 40

  -- Pin look: size, opacity, how many pins per beast
  local function PinSlider(name, label, lo, hi, step, x, key, fmt)
    local s = CreateFrame("Slider", name, p, "OptionsSliderTemplate")
    s:SetWidth(150)
    s:SetPoint("TOPLEFT", x, y - 10)
    s:SetMinMaxValues(lo, hi)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local lowT = s.Low or _G[name .. "Low"]
    local highT = s.High or _G[name .. "High"]
    s.label = s.Text or _G[name .. "Text"]
    if lowT then lowT:SetText(fmt(lo)) end
    if highT then highT:SetText(fmt(hi)) end
    s:SetScript("OnValueChanged", function(self, v)
      v = math.floor(v / step + 0.5) * step
      if s.label then s.label:SetText(label .. ": " .. fmt(v)) end
      if ns.db and ns.db.opts[key] ~= v then
        ns.db.opts[key] = v
        Geo.QueuePins(true)
      end
    end)
    return s
  end
  local pinSize = PinSlider("BeastTrainingTrackerKuroPinSize", "Pin size", 4, 24, 1, 20, "pinSize",
    function(v) return ("%d px"):format(v) end)
  local pinAlpha = PinSlider("BeastTrainingTrackerKuroPinAlpha", "Pin opacity", 0.2, 1, 0.05, 220, "pinAlpha",
    function(v) return ("%d%%"):format(v * 100 + 0.5) end)
  -- how much world-map pins grow between fully zoomed out and fully zoomed in
  local pinZoom = PinSlider("BeastTrainingTrackerKuroPinZoomGrow", "Zoom growth", 1, 3, 0.25, 420, "pinZoomGrow",
    function(v) return v == 1 and "off" or ("%gx"):format(v) end)
  pinZoom:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Zoom growth", 1, 0.82, 0)
    GameTooltip:AddLine("World map only. Pins are drawn at Pin size when the map is fully zoomed out and grow to this multiple when fully zoomed in. Off = the same size at every zoom.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  pinZoom:SetScript("OnLeave", GameTooltip_Hide)
  pinZoom:HookScript("OnValueChanged", function() if ns.Geo.ApplyPinZoom then ns.Geo.ApplyPinZoom() end end)
  y = y - 40

  Section("Alerts")
  Check(p, "Alert when I target or mouse over a teacher", "alertTarget", 4, y, "Big on-screen message when a beast you can tame teaches something you need.")
  Check(p, "Alert when a teacher's nameplate appears", "alertNameplate", 300, y, "Same alert as soon as a teacher's nameplate shows up nearby (needs enemy nameplates on).")
  local soundBtn = Button(p, "Alert sound...", 120, function() if ns.ToggleAlertSoundOptions then ns.ToggleAlertSoundOptions() end end)
  soundBtn:SetPoint("TOPRIGHT", -8, y)
  y = y - 24
  Check(p, "Play a sound with alerts", "alertSound", 4, y, "Raid-warning sound when an alert fires.")
  Check(p, "Remind me about pet upgrades", "upgradeAlert", 300, y, "Chat reminder when you know a better rank than your pet has.")
  y = y - 24
  Check(p, "Pet level-up nudges", "levelNudge", 4, y, "Chat message when your pet reaches the level for a new rank.")
  Check(p, "Let RareScanner alert for rares", "rsHandlesRares", 300, y,
    "If RareScanner is installed it already alerts for rares on its list. With this on, BeastTrainingTracker.Kuro skips its own alert for those so you don't get two.")
  y = y - 24
  Check(p, "Popup when I learn a new ability", "learnToast", 4, y,
    "On-screen popup (with sound) whenever a new pet ability rank is learned - e.g. from a beast you just tamed.")
  Check(p, "Show a pet XP bar", "petXpBar", 300, y,
    "Thin bar with your pet's experience, under your pet's frame. Mouse over it for numbers. Drag to move it, right-click it for options.")
  local petXpOpts = Button(p, "Customize...", 100, function() if ns.TogglePetXPOptions then ns.TogglePetXPOptions() end end)
  petXpOpts:SetPoint("TOPRIGHT", -8, y)
  y = y - 30

  Section("Zone tracker")
  Check(p, "Show the zone tracker", "tracker", 4, y, "Small movable panel listing what you can tame in your current zone. Click a line for a waypoint.")
  Check(p, "Hide it when there's nothing to tame", "trackerAutoHide", 300, y, "Only show the tracker in zones with something new for you.")
  local resetPos = Button(p, "Reset tracker position", 160, function()
    ns.db.trackerPos = nil
    if ns.PlaceTracker then ns.PlaceTracker() end
  end)
  resetPos:SetPoint("TOPRIGHT", -8, y)
  y = y - 30

  Section("Minimap button & waypoints")
  mmCheck = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
  mmCheck:SetSize(22, 22)
  mmCheck:SetPoint("TOPLEFT", 4, y)
  local mmText = mmCheck.text or mmCheck.Text or mmCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  mmText:SetFontObject("GameFontHighlightSmall")
  mmText:ClearAllPoints()
  mmText:SetPoint("LEFT", mmCheck, "RIGHT", 2, 0)
  mmText:SetText("Show minimap button (works with minimap button collectors)")
  mmCheck:SetScript("OnClick", function() if ns.ToggleMinimapButton then ns.ToggleMinimapButton() end end)
  local clear = Button(p, "Clear waypoints", 160, function() Geo.ClearWaypoints() end)
  clear:SetPoint("TOPRIGHT", -8, y)

  -- installed version, bottom right
  local versionText = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  versionText:SetPoint("BOTTOMRIGHT", -8, 4)
  versionText:SetJustifyH("RIGHT")

  function p.Refresh()
    if not p:IsShown() then return end
    mmCheck:SetChecked(not ns.db.minimap.hide)
    ShowRouteColor()
    pinSize:SetValue(ns.db.opts.pinSize or 4)
    pinAlpha:SetValue(ns.db.opts.pinAlpha or 1)
    pinZoom:SetValue(ns.db.opts.pinZoomGrow or 1)
    mapPinMode.Refresh(); miniPinMode.Refresh()
    versionText:SetText("BeastTrainingTracker.Kuro  |cffffffff" .. ns.VersionText() .. "|r")
    for i, a in ipairs(Geo.AddonStatus()) do
      local r = addonRows[i]
      r.dot:SetTexture(a.on and "Interface\\COMMON\\Indicator-Green" or "Interface\\COMMON\\Indicator-Gray")
      r.name:SetText(a.on and ("|cff40ff40" .. a.name .. "|r") or ("|cff9d9d9d" .. a.name .. "|r"))
      r.text:SetText(a.on and a.text or ("|cff9d9d9d" .. a.text .. "|r"))
    end
  end
  p:SetScript("OnShow", p.Refresh)
end

------------------------------------------------------------------------
-- Tab 5: Backup
------------------------------------------------------------------------
-- Shown after login when Questie isn't installed: without it, beast
-- locations are limited to what you've spotted yourself.
StaticPopupDialogs["BTTK_NO_QUESTIE"] = {
  text = "BeastTrainingTracker.Kuro\n\nQuestie isn't installed, so most beast locations are unknown.\n\n"
    .. "Map pins, waypoints and hunt routes will only include beasts you've spotted yourself "
    .. "(targeted, moused over or seen a nameplate). Install Questie to see every beast's spawn points.",
  button1 = OKAY or "OK",
  button2 = "Don't remind me",
  OnCancel = function()
    -- "Don't remind me" (Escape is off for this popup, so it can't trigger this by accident)
    if ns.db then ns.db.opts.hideQuestieWarning = true end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = false,
  preferredIndex = 3,
}

ns.OnLogin(function()
  if C_Timer then
    C_Timer.After(8, function()
      if ns.db and ns.Active() and not ns.db.opts.hideQuestieWarning and not ns.Geo.HasQuestie() then
        StaticPopup_Show("BTTK_NO_QUESTIE")
      end
    end)
  end
end)

StaticPopupDialogs["BTTK_RESET_DATA"] = {
  text = "BeastTrainingTracker.Kuro\n\nWipe ALL saved learned ranks for this character?\nOpen Beast Training afterwards to resync.",
  button1 = YES or "Yes",
  button2 = NO or "No",
  OnAccept = function() ns.ResetData() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  showAlert = true,
  preferredIndex = 3,
}

local function TextArea(parent, x, y, w, h)
  local bg = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  bg:SetPoint("TOPLEFT", x, y)
  bg:SetSize(w, h)
  if bg.SetBackdrop then
    bg:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    bg:SetBackdropColor(0, 0, 0, 0.6)
    bg:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)
  end
  local sf = CreateFrame("ScrollFrame", nil, bg, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 8, -8)
  sf:SetPoint("BOTTOMRIGHT", -28, 8)
  local eb = CreateFrame("EditBox", nil, sf)
  eb:SetMultiLine(true)
  eb:SetFontObject("ChatFontNormal")
  eb:SetWidth(w - 40)
  eb:SetHeight(h - 16)
  eb:SetAutoFocus(false)
  eb:SetScript("OnEscapePressed", eb.ClearFocus)
  sf:SetScrollChild(eb)
  bg:EnableMouse(true)
  bg:SetScript("OnMouseDown", function() eb:SetFocus() end)
  return eb, bg
end

do
  local p = panels[ns.TAB.backup]
  local AREA_W = WIDTH - 40

  Text(p, "GameFontNormal", 6, -4, "Export")
  Text(p, "GameFontDisableSmall", 6, -22, "Copy this text (Ctrl+C) to back up your learned ranks or move them to another PC.")
  local exportBox = TextArea(p, 4, -40, AREA_W, 90)
  exportBox:SetScript("OnTextChanged", function(self, user)
    if user then self:SetText(ns.Export()); self:HighlightText() end
  end)
  exportBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  local selectAll = Button(p, "Select all", 100, function() exportBox:SetFocus(); exportBox:HighlightText() end)
  selectAll:SetPoint("TOPLEFT", 4, -136)

  Divider(p, -166)
  Text(p, "GameFontNormal", 6, -174, "Import")
  Text(p, "GameFontDisableSmall", 6, -192, "Paste an export (Ctrl+V) and press Import. It only ADDS ranks - nothing you have is removed.")
  local importBox = TextArea(p, 4, -210, AREA_W, 90)
  local result = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  local importBtn = Button(p, "Import", 100, function()
    local added, skipped, tamedAdded = ns.Import(importBox:GetText())
    if not added then
      result:SetText("|cffff4040" .. skipped .. "|r")
    else
      result:SetText(("%sImported: %d new rank%s, %d tamed pet%s|r%s"):format(GREEN, added, added == 1 and "" or "s",
        tamedAdded or 0, tamedAdded == 1 and "" or "s",
        skipped > 0 and ("  |cff808080(%d entries skipped)|r"):format(skipped) or ""))
      importBox:SetText("")
      exportBox:SetText(ns.Export())
    end
  end)
  importBtn:SetPoint("TOPLEFT", 4, -306)
  result:SetPoint("LEFT", importBtn, "RIGHT", 12, 0)

  Divider(p, -338)
  Text(p, "GameFontNormal", 6, -346, "|cffff6060Reset|r")
  Text(p, "GameFontDisableSmall", 6, -364, "If the saved data looks broken: wipe it, then open Beast Training to rebuild it. Export first if unsure.")
  local reset = Button(p, "Reset data", 110, function() StaticPopup_Show("BTTK_RESET_DATA") end)
  reset:SetPoint("TOPLEFT", 4, -382)

  local info = Text(p, "GameFontDisableSmall", 6, -416)
  info:SetWidth(AREA_W)

  function p.Refresh()
    if not p:IsShown() then return end
    if not exportBox:HasFocus() then exportBox:SetText(ns.Export()) end
    local explicit = 0
    for _ in pairs(ns.db.known) do explicit = explicit + 1 end
    info:SetText(("%d ranks saved for this character. A copy is also kept account-wide and restored automatically if this character's data goes missing.")
      :format(explicit))
  end
  p:SetScript("OnShow", p.Refresh)
end

------------------------------------------------------------------------
-- Alert sound picker: a list of game sounds (Play / Use) plus a custom
-- file path or FileDataID. Opened from Settings → Alerts → "Alert sound...".
------------------------------------------------------------------------
do
  local win
  local ROW_H = 22

  local function Build()
    local list = ns.ALERT_SOUNDS or {}
    win = CreateFrame("Frame", "BeastTrainingTrackerKuroAlertSound", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    win:SetSize(340, 120 + #list * ROW_H)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetMovable(true)
    win:EnableMouse(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    if win.SetBackdrop then
      win:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
      })
      win:SetBackdropColor(0, 0, 0, 1) -- the dialog texture is translucent; make the panel solid
    end
    tinsert(UISpecialFrames, win:GetName()) -- Escape closes it

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Alert sound")
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local rows = {}
    local function Mark()
      local o = ns.db.opts
      local custom = o.alertSoundCustom ~= nil and o.alertSoundCustom ~= ""
      for _, r in ipairs(rows) do
        local on = not custom and o.alertSoundId == r.id
        r.name:SetText((on and "|cff40ff40" or "|cffffffff") .. r.text .. "|r")
        r.use:SetEnabled(not on)
      end
    end

    for i, s in ipairs(list) do
      local y = -40 - (i - 1) * ROW_H
      local r = { id = s.id, text = s.name }
      r.name = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      r.name:SetPoint("TOPLEFT", 20, y - 5)
      r.play = Button(win, "Play", 50, function() pcall(PlaySound, s.id, "Master") end)
      r.play:SetPoint("TOPRIGHT", -80, y)
      r.use = Button(win, "Use", 50, function()
        ns.db.opts.alertSoundId = s.id
        ns.db.opts.alertSoundCustom = ""
        if win.customBox then win.customBox:SetText("") end
        Mark()
      end)
      r.use:SetPoint("TOPRIGHT", -24, y)
      rows[i] = r
    end

    -- custom sound: a file path inside Interface\ or a FileDataID
    local cy = -40 - #list * ROW_H - 8
    local customLabel = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    customLabel:SetPoint("TOPLEFT", 20, cy)
    customLabel:SetText("Custom: file path or FileDataID")
    local box = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    box:SetSize(190, 20)
    box:SetPoint("TOPLEFT", 26, cy - 16)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEnterPressed", function(self)
      ns.db.opts.alertSoundCustom = (self:GetText() or ""):match("^%s*(.-)%s*$")
      self:ClearFocus()
      Mark()
    end)
    win.customBox = box
    local cPlay = Button(win, "Play", 50, function()
      local v = (box:GetText() or ""):match("^%s*(.-)%s*$")
      if v ~= "" then pcall(PlaySoundFile, tonumber(v) or v, "Master") end
    end)
    cPlay:SetPoint("LEFT", box, "RIGHT", 8, 0)
    local cUse = Button(win, "Use", 50, function() box:GetScript("OnEnterPressed")(box) end)
    cUse:SetPoint("LEFT", cPlay, "RIGHT", 4, 0)
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 20, cy - 42)
    hint:SetWidth(300)
    hint:SetJustifyH("LEFT")
    hint:SetText("e.g. Interface\\AddOns\\MyAddon\\ding.ogg  -  leave empty to use the sound picked above.")

    win:SetScript("OnShow", function()
      box:SetText(ns.db.opts.alertSoundCustom or "")
      Mark()
    end)
  end

  function ns.ToggleAlertSoundOptions()
    if not ns.db then return end
    if not win then Build() end
    if win:IsShown() then win:Hide() else win:Show() end
  end
end

------------------------------------------------------------------------
-- Minimap button (LibDBIcon - One For All picks this up automatically)
------------------------------------------------------------------------
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local DBI = LibStub and LibStub("LibDBIcon-1.0", true)
local launcher

if LDB then
  launcher = LDB:NewDataObject("BeastTrainingTrackerKuro", {
    type = "launcher",
    label = "Beast Training",
    text = "Beast Training",
    icon = "Interface\\Icons\\Ability_Hunter_BeastTraining",
    OnClick = function(_, button)
      if not ns.Active() then
        ns.ToggleMain() -- hunter-only mode: window opens on Settings
      elseif button == "RightButton" then
        Geo.TogglePins()
      elseif button == "MiddleButton" then
        ns.db.opts.tracker = not ns.db.opts.tracker
        ns.Refresh()
      else
        ns.ToggleMain()
      end
    end,
    OnTooltipShow = function(tt)
      if not ns.db then return end
      tt:AddLine("|cffabd473BeastTrainingTracker.Kuro|r")
      if not ns.Active() then
        tt:AddLine("|cffff6060Disabled on this character|r (not a Hunter)", 1, 1, 1)
        tt:AddLine("|cffffffffLeft-click|r open Settings to change that", 0.6, 0.6, 0.6)
        return
      end
      local known, total = ns.Counts()
      tt:AddDoubleLine("Ranks learned", ("%d / %d"):format(known, total), 1, 0.82, 0, 1, 1, 1)
      local fam = ns.PetFamily()
      if fam then
        tt:AddDoubleLine("Pet", ("%s (%s, lvl %d)"):format(UnitName("pet") or fam, fam, UnitLevel("pet") or 0), 1, 0.82, 0, 1, 1, 1)
        local ups = 0
        for _, u in ipairs(ns.Upgrades()) do if not u.needLevel then ups = ups + 1 end end
        if ups > 0 then tt:AddDoubleLine("Upgrades to teach", ups, 1, 0.82, 0, 0.25, 1, 0.25) end
      end
      local need = ns.NeededHere()
      tt:AddLine(" ")
      if #need > 0 then
        tt:AddLine(("Tameable in %s:"):format(ns.CurrentZone()), 0.25, 1, 0.25)
        for i = 1, math.min(8, #need) do
          local e = need[i]
          local who = {}
          for _, t in ipairs(e.teachers) do
            who[#who + 1] = t.name
            if #who >= 2 then break end
          end
          tt:AddDoubleLine(("%s %d"):format(e.ab.name, e.rank.rank), table.concat(who, ", "), 1, 1, 1, 0.25, 1, 0.25)
        end
        if #need > 8 then tt:AddLine(("+%d more"):format(#need - 8), 0.5, 0.5, 0.5) end
      else
        tt:AddLine("Nothing new to tame in this zone", 0.6, 0.6, 0.6)
      end
      local plan = ns.HuntPlan(ns.db.opts.huntPetOnly, ns.db.opts.huntDungeons, "count")
      if plan[1] then
        tt:AddDoubleLine("Best next hunt", ("%s (%d)"):format(plan[1].zone, #plan[1].entries), 1, 0.82, 0, 1, 1, 1)
      end
      tt:AddLine(" ")
      tt:AddLine("|cffffffffLeft-click|r open / close", 0.6, 0.6, 0.6)
      tt:AddLine(("|cffffffffRight-click|r %s beast pins on the map"):format(ns.db.opts.pinsOff and "show" or "hide"), 0.6, 0.6, 0.6)
      tt:AddLine("|cffffffffMiddle-click|r toggle zone tracker", 0.6, 0.6, 0.6)
    end,
  })
end

function ns.ToggleMinimapButton()
  ns.db.minimap.hide = not ns.db.minimap.hide
  if DBI then
    if ns.db.minimap.hide then DBI:Hide("BeastTrainingTrackerKuro") else DBI:Show("BeastTrainingTrackerKuro") end
  end
  Say("minimap button " .. (ns.db.minimap.hide and "hidden" or "shown"))
  if mmCheck then mmCheck:SetChecked(not ns.db.minimap.hide) end
end

ns.OnRefresh(function()
  if launcher then
    local known, total = ns.Counts()
    launcher.text = ("%d/%d"):format(known, total)
  end
end)

ns.OnInit(function(db)
  if db.pos then
    f:ClearAllPoints()
    f:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
  end
  if DBI and launcher and not DBI:IsRegistered("BeastTrainingTrackerKuro") then
    DBI:Register("BeastTrainingTrackerKuro", launcher, db.minimap)
  end
end)
