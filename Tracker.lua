local _, ns = ...

------------------------------------------------------------------------
-- Small movable "tameable in this zone" panel, like a quest tracker
------------------------------------------------------------------------
local Geo = ns.Geo
local MAX_LINES, LINE_H, W = 10, 16, 250

local t = CreateFrame("Frame", "BeastTrainingTrackerKuroMini", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
t:SetSize(W, 40)
t:SetFrameStrata("MEDIUM")
t:SetMovable(true)
t:EnableMouse(true)
t:SetClampedToScreen(true)
t:RegisterForDrag("LeftButton")
t:Hide()
if t.SetBackdrop then
  t:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  t:SetBackdropColor(0, 0, 0, 0.55)
  t:SetBackdropBorderColor(0.67, 0.83, 0.45, 0.6)
end

local icon = t:CreateTexture(nil, "ARTWORK")
icon:SetSize(16, 16)
icon:SetPoint("TOPLEFT", 8, -7)
icon:SetTexture("Interface\\Icons\\Ability_Hunter_BeastTraining")
icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

local head = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
head:SetPoint("LEFT", icon, "RIGHT", 6, 0)
head:SetPoint("RIGHT", -24, 0)
head:SetJustifyH("LEFT")
head:SetWordWrap(false)

local close = CreateFrame("Button", nil, t, "UIPanelCloseButton")
close:SetSize(20, 20)
close:SetPoint("TOPRIGHT", -2, -2)
close:SetScript("OnClick", function()
  ns.db.opts.tracker = false
  ns.Say("zone tracker hidden. Turn it back on in Settings, or /bttk tracker.")
  ns.Refresh()
end)

------------------------------------------------------------------------
-- Which teacher a line shows: your right-click pick, else one we can
-- actually put on the map, else the first listed.
------------------------------------------------------------------------
local function Located(tt)
  local info = Geo.Lookup(tt.name)
  return info and #info.spawns > 0
end

local function PickKey(e) return ns.Key(e.ab.name, e.rank.rank) end

-- Teachers with a known location first, otherwise in data order
local function NaturalOrder(e)
  local list = {}
  for i, tt in ipairs(e.teachers) do list[i] = { tt = tt, i = i, loc = Located(tt) and 0 or 1 } end
  table.sort(list, function(a, b)
    if a.loc ~= b.loc then return a.loc < b.loc end
    return a.i < b.i
  end)
  for i, x in ipairs(list) do list[i] = x.tt end
  return list
end

-- Reorder e.teachers in place (HuntPlan builds fresh lists each time)
local function OrderTeachers(e)
  local list = NaturalOrder(e)
  local pick = ns.db.trackerPick and ns.db.trackerPick[PickKey(e)]
  if pick then
    for i, tt in ipairs(list) do
      if tt.name == pick then table.remove(list, i); table.insert(list, 1, tt); break end
    end
  end
  for i, tt in ipairs(list) do e.teachers[i] = tt end
end

-- Right-click: step to the next teacher and remember it
local function CycleTeacher(e)
  if #e.teachers < 2 then return end
  local list = NaturalOrder(e)
  local cur = e.teachers[1].name
  local nxt = list[1]
  for i, tt in ipairs(list) do
    if tt.name == cur then nxt = list[i % #list + 1]; break end
  end
  ns.db.trackerPick = ns.db.trackerPick or {}
  ns.db.trackerPick[PickKey(e)] = nxt.name
  OrderTeachers(e) -- right away, so the tooltip shows the new pick
  ns.Refresh()
end

local lines = {}
local function Line(i)
  local b = lines[i]
  if b then return b end
  b = CreateFrame("Button", nil, t)
  b:SetHeight(LINE_H)
  b:SetPoint("TOPLEFT", 8, -26 - (i - 1) * LINE_H)
  b:SetPoint("RIGHT", -8, 0)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.08)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(13, 13)
  b.icon:SetPoint("LEFT", 0, 0)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)
  b.text:SetPoint("RIGHT")
  b.text:SetJustifyH("LEFT")
  b.text:SetWordWrap(false)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(self, button)
    local e = self.entry
    if not e then return end
    if button == "RightButton" then
      CycleTeacher(e)
      if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
    elseif IsShiftKeyDown() then
      local list = {}
      for _, tt in ipairs(e.teachers) do list[#list + 1] = { t = tt, label = Geo.Label(e.ab, e.rank, tt) } end
      Geo.WaypointMany(list)
    else
      local tt = e.teachers[1]
      Geo.Waypoint(tt, Geo.Label(e.ab, e.rank, tt))
    end
  end)
  b:SetScript("OnEnter", function(self)
    local e = self.entry
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(("%s (Rank %d)"):format(e.ab.name, e.rank.rank), 1, 0.82, 0)
    GameTooltip:AddLine(e.rank.effect, 1, 1, 1, true)
    GameTooltip:AddLine(("Pet level %d to use"):format(e.rank.level), 0.8, 0.8, 0.8)
    GameTooltip:AddLine(" ")
    local anyLocated = false
    for i, tt in ipairs(e.teachers) do
      local mark = i == 1 and "> " or "   "
      local located = Located(tt)
      anyLocated = anyLocated or located
      local loc = located and "" or " |cff9d9d9d(no location)|r"
      GameTooltip:AddDoubleLine(mark .. tt.name .. Geo.Tag(tt.name) .. loc, ("%s %s"):format(tt.family, tt.level), 0.25, 1, 0.25, 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine(" ")
    if not anyLocated then
      -- nothing can be waypointed, so don't offer to
      GameTooltip:AddLine("No known location for these beasts.", 1, 0.5, 0.25, true)
    elseif not Located(e.teachers[1]) then
      GameTooltip:AddLine("Shift-click: waypoint the ones with a location", 0.5, 0.5, 0.5)
      GameTooltip:AddLine("Right-click: show a different beast", 0.5, 0.5, 0.5)
    else
      GameTooltip:AddLine("Click: waypoint  ·  Shift-click: all of them", 0.5, 0.5, 0.5)
      if #e.teachers > 1 then GameTooltip:AddLine("Right-click: show a different beast", 0.5, 0.5, 0.5) end
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  lines[i] = b
  return b
end

function ns.PlaceTracker()
  t:ClearAllPoints()
  local p = ns.db and ns.db.trackerPos
  if p then
    t:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    t:SetPoint("RIGHT", UIParent, "RIGHT", -60, 120)
  end
end

t:SetScript("OnDragStart", t.StartMoving)
t:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local p, _, rp, x, y = self:GetPoint()
  ns.db.trackerPos = { p, rp, x, y }
end)

local function Update()
  local o = ns.db.opts
  if not o.tracker or not ns.Active() then t:Hide() return end
  local entries, zone = ns.NeededHere()
  if #entries == 0 and o.trackerAutoHide then t:Hide() return end

  head:SetText(("%s  |cffffffff%d|r"):format(zone ~= "" and zone or "Tameable here", #entries))
  local n = math.min(MAX_LINES, #entries)
  for i = 1, n do
    local e = entries[i]
    local b = Line(i)
    b.entry = e
    b.icon:SetTexture(e.ab.icon)
    OrderTeachers(e)
    local tt = e.teachers[1]
    local more = #e.teachers > 1 and ("|cff808080 +%d|r"):format(#e.teachers - 1) or ""
    local name = Located(tt) and tt.name or ("|cff9d9d9d" .. tt.name .. "?|r")
    b.text:SetText(("|cff40ff40%s %d|r  %s |cff9d9d9d(%s)|r%s%s"):format(e.ab.name, e.rank.rank, name, tt.level, Geo.Tag(tt.name), more))
    b:Show()
  end
  local extra = 0
  if #entries == 0 then
    local b = Line(1)
    b.entry = nil
    b.icon:SetTexture(nil)
    b.text:SetText("|cff9d9d9dNothing new to tame here|r")
    b:Show()
    n, extra = 1, 0
  elseif #entries > MAX_LINES then
    local b = Line(n + 1)
    b.entry = nil
    b.icon:SetTexture(nil)
    b.text:SetText(("|cff808080+%d more - see Hunt Planner|r"):format(#entries - MAX_LINES))
    b:Show()
    extra = 1
  end
  for i = n + extra + 1, #lines do lines[i]:Hide(); lines[i].entry = nil end
  t:SetHeight(32 + (n + extra) * LINE_H)
  t:Show()
end

ns.OnInit(function() ns.PlaceTracker() end)
ns.OnRefresh(function() if ns.db then Update() end end)
ns.OnDeactivate(function() t:Hide() end)
