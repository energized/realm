-- Top-centre compass (N/E/S/W letters, no degrees) that slides your target along it as you turn, plus the panel under it.
local ADDON, ns = ...
local Path = ns.Path
local UI = ns.UI

local PI, TWO_PI = math.pi, math.pi * 2
local FOV = math.rad(190)
local compass, panel, marker
local labels, ticks = {}, {}
local target = { bearing = nil, dist = nil, why = nil, kind = nil }
local override                      -- manual target (trainer, corpse, a party member)
local lastDt = 0
local bannered

local C = UI.C
local COLORS = {
  A = C.gold, T = C.good, D = C.ember, G = C.blue, L = C.cream, R = C.purple,
  corpse = C.cream, trainer = C.purple, friend = C.blue, farm = C.gold, travel = C.blue, dungeon = C.purple, inn = C.ember, mail = C.gold,
}
local ICON = { A = "!", T = "?", D = "+", G = ">>", L = "L", R = "R", corpse = "X", trainer = "R", friend = "@", farm = "$", travel = ">>", dungeon = "#", inn = "H", mail = "M" }
-- travel-mode pictures (white silhouettes the game tints): tram, boat, zeppelin, flight master, flying yourself, footprints for walking
local TEXDIR = "Interface\\AddOns\\Realm\\Path\\icons\\"
local MODETEX = { tram = "tram", boat = "boat", zep = "zep", fly = "fly", flyself = "flyself", walk = "walk" }
-- which picture to show for the current travel target, or nil to keep the text glyph.
-- When you are flying yourself (in the air, or mounted where flying is allowed on a walking leg) it shows the rider.
local function ModeIcon()
  if target.kind ~= "travel" or not target.mode then return nil end
  local m = target.mode
  local flying = IsFlying and IsFlying()
  local canFly = IsMounted and IsMounted() and IsFlyableArea and IsFlyableArea()
  if (m == "walk" and (flying or canFly)) or (m == "fly" and flying) then m = "flyself" end
  return MODETEX[m]
end
Path.ModeIcon = ModeIcon
local VERB = { A = "ACCEPT QUEST", T = "HAND IN QUEST", G = "TRAVEL", L = "LEVEL UP", R = "TRAIN SPELLS" }

local function Secret(v) return issecretvalue and v ~= nil and issecretvalue(v) end
local function Font(fs, size, flags) if fs.SetFont then fs:SetFont(UI.FONT, size, flags or "OUTLINE") end end
local function Wrap(a) return (a + PI) % TWO_PI - PI end
local function Fmt(d)
  if not d then return "" end
  if d >= 1000 then return string.format("%.1fk yd", d / 1000) end
  return string.format("%d yd", math.floor(d + 0.5))
end

-- ------------------------------------------------------------ describing a step
function Path.Describe(s)
  local verb, name, subt = s.verb or VERB[s.t] or "NEXT", s.n or "?", ""
  if s.t == "A" then subt = s.npc and ("from " .. s.npc) or ""
  elseif s.t == "T" then subt = s.npc and ("to " .. s.npc) or ""
  elseif s.t == "D" then
    verb = (s.kind == "kill" and "KILL") or (s.kind == "item" and "COLLECT") or (s.kind == "obj" and "FIND") or "OBJECTIVE"
    name = s.npc or "objective"; subt = s.n or ""
  elseif s.t == "R" then subt = s.npc and ("see " .. s.npc) or ""
  end
  return verb, name, subt
end

function Path.StepText(s)
  local verb, name = Path.Describe(s)
  return verb:sub(1, 1) .. verb:sub(2):lower() .. ": " .. name
end

-- ------------------------------------------------------------ build
local BuildLegend
local function Build()
  local O = Path.Opts()
  compass = CreateFrame("Frame", "RealmCompass", UIParent)
  compass:SetSize(O.compassWidth, 30)
  compass:SetPoint("TOP", UIParent, "TOP", 0, -10)
  compass:SetFrameStrata("MEDIUM")
  compass:SetClampedToScreen(true)
  compass:SetMovable(true)
  compass:RegisterForDrag("LeftButton")
  compass:SetScript("OnDragStart", function(self) if not Path.Opts().locked then self:StartMoving() end end)
  compass:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint(); Path.Opts().pos = { p, rp, x, y }
  end)

  compass.bg = compass:CreateTexture(nil, "BACKGROUND")
  compass.bg:SetAllPoints(); compass.bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], .82)
  compass.line = compass:CreateTexture(nil, "BORDER")
  compass.line:SetPoint("BOTTOMLEFT"); compass.line:SetPoint("BOTTOMRIGHT"); compass.line:SetHeight(1)
  compass.line:SetColorTexture(C.red[1], C.red[2], C.red[3], 1)

  local names = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
  for i, n in ipairs(names) do
    local fs = compass:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Font(fs, (i % 2 == 1) and 17 or 11)
    fs:SetText(n)
    local c = (i == 1) and C.ember or ((i % 2 == 1) and C.cream or C.muted)
    fs:SetTextColor(c[1], c[2], c[3])
    labels[i] = fs
  end
  for i = 1, 24 do
    local t = compass:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(C.muted[1], C.muted[2], C.muted[3], .55); t:SetSize(1, 6)
    ticks[i] = t
  end
  local notch = compass:CreateTexture(nil, "OVERLAY")
  notch:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1); notch:SetSize(2, 30); notch:SetPoint("CENTER")

  marker = CreateFrame("Frame", nil, compass)
  marker:SetSize(40, 30); marker:SetFrameLevel(compass:GetFrameLevel() + 5)
  marker.chip = marker:CreateTexture(nil, "ARTWORK")          -- filled backing so the marker is easy to spot
  marker.chip:SetSize(38, 28); marker.chip:Hide()
  marker.icon = marker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  marker.icon:SetPoint("CENTER", marker, "CENTER", 0, 1); Font(marker.icon, 22)
  marker.chip:SetPoint("CENTER", marker.icon, "CENTER", 0, 0)
  marker.tex = marker:CreateTexture(nil, "OVERLAY")
  marker.tex:SetSize(24, 24); marker.tex:SetPoint("CENTER", marker.icon, "CENTER", 0, 0); marker.tex:Hide()
  marker.arrowL = marker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  marker.arrowL:SetPoint("RIGHT", marker.icon, "LEFT", 2, 0); Font(marker.arrowL, 13); marker.arrowL:SetText("<")
  marker.arrowR = marker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  marker.arrowR:SetPoint("LEFT", marker.icon, "RIGHT", -2, 0); Font(marker.arrowR, 13); marker.arrowR:SetText(">")
  marker.dist = compass:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  Font(marker.dist, 11)
  marker:Hide()

  -- ---------------------------------------------------------- panel
  panel = CreateFrame("Frame", "RealmCompassPanel", UIParent)
  panel:SetFrameStrata("MEDIUM")
  panel:SetPoint("TOP", compass, "BOTTOM", 0, -2)       -- re-anchored by PlacePanel
  panel:SetMovable(true); panel:SetClampedToScreen(true); panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", function(self)
    local O = Path.Opts()
    if (O.panelMode or "dock") == "free" and not O.locked then self:StartMoving() end
  end)
  panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint(); Path.Opts().panelPos = { p, rp, x, y }
  end)
  panel.bg = panel:CreateTexture(nil, "BACKGROUND")
  panel.bg:SetAllPoints(); panel.bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], .88)
  panel.accent = panel:CreateTexture(nil, "ARTWORK")
  panel.accent:SetPoint("TOPLEFT"); panel.accent:SetPoint("BOTTOMLEFT"); panel.accent:SetWidth(4)
  panel.verb = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.verb:SetPoint("TOPLEFT", 14, -8); panel.verb:SetJustifyH("LEFT"); Font(panel.verb, 12)
  panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.title:SetPoint("TOPLEFT", panel.verb, "BOTTOMLEFT", 0, -1); panel.title:SetJustifyH("LEFT"); Font(panel.title, 22)
  panel.sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.sub:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -3); panel.sub:SetJustifyH("LEFT"); Font(panel.sub, 12)
  panel.big = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  panel.big:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, -28); panel.big:SetJustifyH("RIGHT"); Font(panel.big, 34)
  panel.dist = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.dist:SetPoint("TOPRIGHT", panel.big, "BOTTOMRIGHT", 0, -2); panel.dist:SetJustifyH("RIGHT"); Font(panel.dist, 16)
  panel.tx = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  panel.tx:SetPoint("TOPLEFT", panel.sub, "BOTTOMLEFT", 0, -3); panel.tx:SetJustifyH("LEFT"); Font(panel.tx, 11, "")
  -- big at-a-glance readout for profession skill levels (leveling detours)
  panel.skill = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  panel.skill:SetPoint("TOPLEFT", panel.sub, "BOTTOMLEFT", 0, -5); panel.skill:SetJustifyH("LEFT"); Font(panel.skill, 24)
  if panel.skill.SetWordWrap then panel.skill:SetWordWrap(true) end
  if panel.tx.SetWordWrap then panel.tx:SetWordWrap(true) end
  if panel.tx.SetMaxLines then panel.tx:SetMaxLines(1) end        -- one line by default; click it for the full detail
  panel.txBtn = CreateFrame("Button", nil, panel)                  -- invisible hit area over the description
  panel.txBtn:SetFrameLevel(panel:GetFrameLevel() + 1)
  panel.txBtn:SetScript("OnClick", function()
    panel.txOpen = not panel.txOpen
    Path.UpdatePanel()
  end)
  panel.txBtn:SetScript("OnEnter", function(self)
    if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine("Click to show or hide the full detail"); GameTooltip:Show() end
  end)
  panel.txBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  panel.txBtn:Hide()
  panel.next = {}
  for i = 1, 3 do
    local f = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f:SetJustifyH("LEFT"); Font(f, 11, "")
    panel.next[i] = f
  end
  panel.prog = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  panel.prog:SetJustifyH("LEFT"); Font(panel.prog, 10, "")

  -- the button row along the bottom of the info window: skip controls on the left, Track.. / gear / Legend on the right
  local function Btn(text, w, point, x, fn, tip, icon)
    local b = CreateFrame("Button", nil, panel)
    b:SetSize(w, 20)
    b:SetPoint(point, panel, point, x, 4)
    UI.Button(b)
    b.t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.t:SetPoint("CENTER"); b.t:SetText(icon and "" or text); Font(b.t, 12, "")
    if icon then
      b.icon = b:CreateTexture(nil, "OVERLAY"); b.icon:SetSize(18, 18); b.icon:SetPoint("CENTER")
      b.icon:SetTexture(icon); b.icon:SetVertexColor(C.cream[1], C.cream[2], C.cream[3], 1)
    end
    b:SetScript("OnClick", fn)
    b:SetScript("OnEnter", function(self)
      if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(tip); GameTooltip:Show() end
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
  end
  panel.backBtn = Btn("< -1", 40, "BOTTOMLEFT", 14, function() Path.Back() end, "Bring back the last skipped step")
  panel.stepsBtn = Btn("Skip step", 80, "BOTTOMLEFT", 58, function() Path.ToggleStepList() end, "Show the next steps, click one to go there")
  panel.skipBtn = Btn("+1 >", 40, "BOTTOMLEFT", 142, function() Path.Skip() end, "Skip this step")
  panel.gearBtn = Btn("W", 28, "BOTTOMRIGHT", -62, function() if Path.Window then Path.Window.Toggle() end end, "Route window and settings", TEXDIR .. "gear")
  panel.trackBtn = Btn("Track..", 58, "BOTTOMRIGHT", -94, function() Path.ToggleTrackMenu() end, "What to track")
  BuildLegend()
end

-- ------------------------------------------------------------ tracking menu
local menu, menuRows = nil, {}
local MENU_W, menuWanted, menuNow = 210, false, 0
local MODES = { { "quest", "Quest route" }, { "free", "My quest log (free mode)" }, { "trainer", "Nearest trainer" }, { "farm", "Farming spot ($)" }, { "dungeon", "Nearby dungeon (fits you)" }, { "inn", "Inn to make home" }, { "friend", "Party member" } }
local TOGGLES = { { "farm", "Show $ on compass" }, { "friends", "Party dots on compass" }, { "classq", "Class quest alerts" }, { "discoverFlights", "Detour to new flight masters" }, { "corpse", "Corpse when dead" }, { "trail", "Dashed trail on minimap" } }

local function RefreshMenu()
  if not menu then return end
  local O = Path.Opts()
  for _, r in ipairs(menuRows) do
    if r.mode then r.v:SetText((O.trackMode or "quest") == r.mode and (UI.H.good .. "<|r") or "")
    else r.v:SetText(O[r.key] and (UI.H.good .. "ON|r") or (UI.H.muted .. "off|r")) end
  end
end

local function BuildMenu()
  if menu then return end
  menu = CreateFrame("Frame", nil, panel)
  menu:SetFrameStrata("DIALOG"); menu:SetSize(1, 24 + (#MODES + #TOGGLES) * 22 + 28)
  menu:SetPoint("TOPRIGHT", panel, "TOPLEFT", -2, 0)           -- re-anchored by PlaceMenu
  if menu.SetClipsChildren then menu:SetClipsChildren(true) end
  -- the content sits on a fixed-width body so sliding only reveals it, never squeezes it
  menu.body = CreateFrame("Frame", nil, menu)
  menu.body:SetSize(MENU_W, 24 + (#MODES + #TOGGLES) * 22 + 28)
  menu.body:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, 0)
  menu.bg = menu:CreateTexture(nil, "BACKGROUND"); menu.bg:SetAllPoints()
  menu.bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], .96)
  menu.top = menu:CreateTexture(nil, "BORDER"); menu.top:SetPoint("TOPLEFT"); menu.top:SetPoint("TOPRIGHT"); menu.top:SetHeight(2)
  menu.top:SetColorTexture(C.red[1], C.red[2], C.red[3], 1)
  local function Head(text, y)
    local h = menu.body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetPoint("TOPLEFT", 10, y); h:SetText(UI.H.gold .. text .. "|r"); Font(h, 11)
  end
  local y = -8
  Head("TRACK (compass and minimap follow it)", y); y = y - 16
  local function Row(label, fn, mode, key)
    local b = CreateFrame("Button", nil, menu.body)
    b:SetSize(194, 20); b:SetPoint("TOPLEFT", 8, y); y = y - 22
    UI.Button(b)
    b.t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.t:SetPoint("LEFT", 8, 0); b.t:SetText(label); Font(b.t, 12, "")
    b.v = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.v:SetPoint("RIGHT", -8, 0); Font(b.v, 12)
    b.mode, b.key = mode, key
    b:SetScript("OnClick", function() fn(); RefreshMenu(); Path.UpdateHUD() end)
    menuRows[#menuRows + 1] = b
  end
  for _, m in ipairs(MODES) do
    Row(m[2], function() local O = Path.Opts(); O.trackMode = m[1]; Path.ResetTrack() end, m[1], nil)
  end
  y = y - 6
  Head("SHOW", y); y = y - 16
  for _, tg in ipairs(TOGGLES) do
    Row(tg[2], function() local O = Path.Opts(); O[tg[1]] = not O[tg[1]] end, nil, tg[1])
  end
  menu:SetHeight(-y + 8)
  menu.body:SetHeight(-y + 8)
  menu:SetWidth(1)
  menu:Hide()
end

-- the Track window slides out on the left side of the info window (on the right when the info window hugs the left screen edge)
local function PlaceMenu()
  if not menu or not panel then return end
  local left = panel:GetLeft()
  local sc = panel:GetScale()
  if type(sc) ~= "number" or sc <= 0 then sc = 1 end
  local rightSide = type(left) == "number" and (left * sc) < (MENU_W + 6)
  menu:SetScale(sc)
  menu:ClearAllPoints(); menu.body:ClearAllPoints()
  if rightSide then
    menu:SetPoint("TOPLEFT", panel, "TOPRIGHT", 2, 0)
    menu.body:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, 0)
  else
    menu:SetPoint("TOPRIGHT", panel, "TOPLEFT", -2, 0)
    menu.body:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, 0)
  end
end

function Path.ToggleTrackMenu()
  BuildMenu(); RefreshMenu()
  menuWanted = not menuWanted
  PlaceMenu()
  menu:Show()
end

local function SlideMenu(dt)
  if not menu then return end
  local goal = menuWanted and MENU_W or 0
  if menuNow == goal then return end
  local step = (dt or 0.02) * 900
  if menuNow < goal then menuNow = math.min(goal, menuNow + step) else menuNow = math.max(goal, menuNow - step) end
  menu:SetWidth(math.max(1, menuNow))
  menu:SetAlpha(menuNow / MENU_W)
  if menuNow == 0 then menu:Hide() end
end

-- ------------------------------------------------------------ next-steps list (slides down from the bottom of the info window)
local list, listRows = nil, {}
local LIST_ROW, LIST_HEAD, LIST_COMPACT, LIST_MAX = 16, 24, 5, 20
local listWanted, listMore, listNow, listGoal = false, false, 0, 0

local function ListFit()                -- how many rows fit between the info window and the bottom of the screen
  local bottom = panel and panel:GetBottom()
  if type(bottom) ~= "number" then return LIST_MAX end
  local sc = panel:GetScale()
  if type(sc) ~= "number" or sc <= 0 then sc = 1 end
  local room = (bottom * sc - 24) / sc - LIST_HEAD - 8
  return math.max(LIST_COMPACT, math.min(LIST_MAX, math.floor(room / LIST_ROW)))
end

local function BuildList()
  if list then return end
  list = CreateFrame("Frame", nil, panel)
  list:SetFrameStrata("DIALOG")
  list:SetSize(panel:GetWidth() or 440, 1)
  list:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -2)
  if list.SetClipsChildren then list:SetClipsChildren(true) end
  list.bg = list:CreateTexture(nil, "BACKGROUND"); list.bg:SetAllPoints()
  list.bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], .96)
  list.edge = list:CreateTexture(nil, "BORDER")
  list.edge:SetPoint("BOTTOMLEFT"); list.edge:SetPoint("BOTTOMRIGHT"); list.edge:SetHeight(2)
  list.edge:SetColorTexture(C.red[1], C.red[2], C.red[3], 1)
  list.head = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  list.head:SetPoint("TOPLEFT", 12, -7); list.head:SetText(UI.H.gold .. "NEXT STEPS  (click one to go there)|r"); Font(list.head, 11)
  list.more = CreateFrame("Button", nil, list)
  list.more:SetSize(54, 16); list.more:SetPoint("TOPRIGHT", -8, -4)
  UI.Button(list.more)
  list.more.t = list.more:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); list.more.t:SetPoint("CENTER"); Font(list.more.t, 11, "")
  list.more:SetScript("OnClick", function() listMore = not listMore; Path.UpdatePanel() end)
  for k = 1, LIST_MAX do
    local b = CreateFrame("Button", nil, list)
    b:SetHeight(LIST_ROW - 1)
    b:SetPoint("TOPLEFT", 6, -LIST_HEAD - (k - 1) * LIST_ROW)
    b:SetPoint("TOPRIGHT", -6, -LIST_HEAD - (k - 1) * LIST_ROW)
    UI.Button(b)
    b.t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.t:SetPoint("LEFT", 6, 0); b.t:SetJustifyH("LEFT"); Font(b.t, 11, "")
    b:SetScript("OnClick", function(self) if self.idx and Path.GotoStep then Path.GotoStep(self.idx) end end)
    b:Hide()
    listRows[k] = b
  end
  list:Hide()
end

local function RefreshList()
  if not list then return end
  local W = panel:GetWidth() or 440
  list:SetWidth(W)
  local cap = listMore and ListFit() or LIST_COMPACT
  local up = (listWanted and Path.Upcoming) and Path.Upcoming(LIST_MAX) or {}
  local shown = math.min(#up, cap)
  for k = 1, LIST_MAX do
    local b, e = listRows[k], up[k]
    if e and k <= shown then
      b.idx = e[2]
      b.t:SetWidth(W - 30)
      b.t:SetText(UI.H.muted .. k .. ".|r " .. UI.H.text .. Path.StepText(e[1]) .. "|r")
      b:Show()
    else b.idx = nil; b:Hide() end
  end
  if #up > LIST_COMPACT then
    list.more.t:SetText(listMore and "Less" or "More"); list.more:Show()
  else list.more:Hide() end
  listGoal = listWanted and (LIST_HEAD + math.max(1, shown) * LIST_ROW + 6) or 0
end

function Path.ToggleStepList()
  BuildList()
  listWanted = not listWanted
  if not listWanted then listMore = false end
  list:Show()
  RefreshList()
end

local function SlideList(dt)
  if not list then return end
  if listNow == listGoal then return end
  local step = (dt or 0.02) * 900
  if listNow < listGoal then listNow = math.min(listGoal, listNow + step) else listNow = math.max(listGoal, listNow - step) end
  list:SetHeight(math.max(1, listNow))
  if listNow == 0 then list:Hide() end
end

-- ------------------------------------------------------------ slide-out legend
local legend, legendTab
local LEGEND_W, legendWanted, legendNow = 176, false, 0
local legendRows = {}                   -- each legend glyph with its filled chip, restyled by ApplyMarkerStyle
local LEGEND = {
  { "A", "Accept a quest" }, { "T", "Hand in a quest" }, { "D", "Kill or collect" }, { "G", "Travel to next zone" },
  { "L", "Level up first" }, { "R", "Train spells (trainer)" }, { "corpse", "Your corpse" }, { "friend", "Party member" },
  { "$", "Farming spot" }, { "inn", "Inn (set your home)" },
}
BuildLegend = function()
  if legend then return end
  legendTab = CreateFrame("Button", nil, compass)
  legendTab:SetSize(50, 20); legendTab:SetPoint("BOTTOMRIGHT", compass, "BOTTOMRIGHT", -4, 2)   -- re-anchored by PlaceLegendTab
  UI.Button(legendTab)
  legendTab.t = legendTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  legendTab.t:SetPoint("CENTER"); legendTab.t:SetText("Legend"); Font(legendTab.t, 11)
  legendTab:SetFrameLevel(compass:GetFrameLevel() + 8)
  legend = CreateFrame("Frame", nil, compass)
  legend:SetFrameLevel(compass:GetFrameLevel() + 6)
  legend:SetPoint("TOPLEFT", compass, "TOPRIGHT", 2, 0)
  legend:SetSize(1, 30 + #LEGEND * 18)
  if legend.SetClipsChildren then legend:SetClipsChildren(true) end
  legend.bg = legend:CreateTexture(nil, "BACKGROUND"); legend.bg:SetAllPoints()
  legend.bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], .92)
  legend.edge = legend:CreateTexture(nil, "BORDER")
  legend.edge:SetPoint("TOPLEFT"); legend.edge:SetPoint("BOTTOMLEFT"); legend.edge:SetWidth(2)
  legend.edge:SetColorTexture(C.red[1], C.red[2], C.red[3], 1)
  local head = legend:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  head:SetPoint("TOPLEFT", 12, -8); head:SetText(UI.H.gold .. "COMPASS LEGEND|r"); Font(head, 11)
  for i, e in ipairs(LEGEND) do
    local key = e[1]
    local glyph = (key == "$") and "$" or (ICON[key] or "?")
    local col = (key == "$") and C.gold or (COLORS[key] or C.cream)
    local g = legend:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    g:SetPoint("TOPLEFT", 12, -22 - (i - 1) * 18); g:SetWidth(24); g:SetJustifyH("CENTER")
    g:SetText(glyph); g:SetTextColor(col[1], col[2], col[3]); Font(g, 15)
    local chip = legend:CreateTexture(nil, "ARTWORK")
    chip:SetPoint("CENTER", g, "CENTER", 0, 0); chip:SetSize(24, 18); chip:Hide()
    legendRows[#legendRows + 1] = { g = g, chip = chip, col = col }
    local l = legend:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l:SetPoint("LEFT", g, "RIGHT", 6, 0); l:SetText(UI.H.text .. e[2] .. "|r"); Font(l, 12, "")
  end
  legend:SetAlpha(0); legend:Hide()
  legendTab:SetScript("OnClick", function()
    legendWanted = not legendWanted
    local o = Path.Opts(); if o then o.legend = legendWanted end
    legend:Show()
  end)
  legendTab:SetScript("OnEnter", function(self)
    if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine("Compass legend"); GameTooltip:Show() end
  end)
  legendTab:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  local o = Path.Opts()
  if o and o.legend then legendWanted = true; legendNow = LEGEND_W; legend:SetWidth(LEGEND_W); legend:SetAlpha(1); legend:Show() end
end

local function SlideLegend(dt)
  if not legend then return end
  local goal = legendWanted and LEGEND_W or 0
  if legendNow == goal then return end
  local step = (dt or 0.02) * 700
  if legendNow < goal then legendNow = math.min(goal, legendNow + step) else legendNow = math.max(goal, legendNow - step) end
  legend:SetWidth(math.max(1, legendNow))
  legend:SetAlpha(legendNow / LEGEND_W)
  if legendNow == 0 then legend:Hide() end
end

-- ------------------------------------------------------------ what to track (like the minimap tracking menu)
function Path.NearestTrainer()
  local _, class = UnitClass("player")
  local list = ns.Trainers and ns.Trainers[class]
  if not list then return end
  local fac = (UnitFactionGroup and UnitFactionGroup("player") == "Horde") and "H" or "A"
  local best, bd
  for _, tr in ipairs(list) do
    if tr[5] == fac or tr[5] == "AH" then
      local b, d = Path.Vector(tr[2], tr[3], tr[4])
      if b and (not bd or d < bd) then best, bd = tr, d end
    end
  end
  return best, bd
end

local trackCache, trackAt = nil, 0
local function Track()
  local O = Path.Opts()
  local mode = O and O.trackMode or "quest"
  if mode == "quest" then
    -- a class quest you can pick up now beats the route
    local cq = Path.ClassPending and Path.ClassPending()
    if cq then return cq end
    -- bags are full of things your auction house alt can sell, an inn is close and postage is affordable: mailbox first
    local mu = ns.Mule and ns.Mule.Target and ns.Mule.Target()
    if mu then return mu end
    -- the next stop is in another zone: aim at each travel leg in turn
    local tv = Path.TravelTarget and Path.TravelTarget()
    if tv then return tv end
    -- nothing left on the route (or no route for you): follow the quests you picked up yourself
    local s = Path.Current()
    if (not s) and Path.FreeTarget then return Path.FreeTarget() end
    return nil
  end
  local now = GetTime and GetTime() or 0
  if trackCache and trackCache.mode == mode and now - trackAt < 0.5 then return trackCache.o end
  local o
  if mode == "trainer" then
    local tr = Path.NearestTrainer()
    if tr then o = { kind = "trainer", p = { tr[3], tr[4] }, m = tr[2], title = tr[1], sub = "Nearest class trainer" } end
  elseif mode == "free" then
    o = Path.FreeTarget and Path.FreeTarget(true)
  elseif mode == "farm" then
    local r, map
    if Path.FarmSpots then r, map = Path.FarmSpots(1) end
    if r and r[1] then
      local s = r[1].s
      o = { kind = "farm", p = { s[1], s[2] }, m = map, title = s[7], sub = ("Farming spot, level %d-%d, about %d mobs"):format(s[4], s[5], s[3]) }
    end
  elseif mode == "dungeon" then
    o = Path.Dungeons and Path.Dungeons.Target()
  elseif mode == "inn" then
    o = Path.Inn and Path.Inn.Target()
  elseif mode == "friend" then
    local peers = ns.Tracker and ns.Tracker.Peers and ns.Tracker.Peers() or {}
    local p, name = peers[O.trackFriend or ""], O.trackFriend
    if not p then
      local bd
      for n, pp in pairs(peers) do
        if pp.map and pp.x and pp.x ~= 0 then
          local b, d = Path.Vector(pp.map, pp.x, pp.y)
          if b and (not bd or d < bd) then p, name, bd = pp, n, d end
        end
      end
    end
    if p and p.map and p.x and p.x ~= 0 then o = { kind = "friend", p = { p.x, p.y }, m = p.map, title = name, sub = "Party member" } end
  end
  trackCache, trackAt = { mode = mode, o = o }, now
  return o
end
Path.Track = Track
function Path.ResetTrack() trackCache = nil end

-- ------------------------------------------------------------ choose the point to aim at
local function Resolve()
  local s = Path.Current()
  local O = Path.Opts()
  local kind, pts, map, label
  local tr = (not override) and Track() or nil
  if override then
    kind, pts, map, label = override.kind, override.p, override.m, override.title
  elseif tr then
    kind, pts, map, label = tr.kind, tr.p, tr.m, tr.title
  elseif O.corpse and UnitIsGhost and UnitIsGhost("player") and C_DeathInfo and C_DeathInfo.GetCorpseMapPosition then
    local pmap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local cp = pmap and C_DeathInfo.GetCorpseMapPosition(pmap)
    if cp then
      local x, y
      if cp.GetXY then x, y = cp:GetXY() else x, y = cp.x, cp.y end
      if x and x ~= 0 then kind, pts, map, label = "corpse", { x, y }, pmap, "Your corpse" end
    end
  end
  if not kind and s then kind, pts, map, label = s.t, s.p, s.m, s.npc end
  if not kind or not pts or #pts < 2 then target.bearing, target.dist, target.why, target.kind, target.map = nil, nil, "none", kind, nil return end
  local bestB, bestD, why, bestX, bestY
  for i = 1, #pts, 2 do
    local b, d, w = Path.Vector(map, pts[i], pts[i + 1])
    if b and (not bestD or d < bestD) then bestB, bestD, bestX, bestY = b, d, pts[i], pts[i + 1] end
    why = w
  end
  target.bearing, target.dist, target.why, target.kind, target.label, target.map = bestB, bestD, (not bestB) and why or nil, kind, label, map
  target.x, target.y = bestX, bestY      -- map position of the nearest point (the party tracker draws it)
  target.mode = (override and override.mode) or (tr and tr.mode) or nil
  if override and override.kind ~= "friend" and bestD and bestD < 25 then override = nil; Path.UpdateHUD() end
end

function Path.SetOverride(o) override = o; Path.UpdateHUD() end
function Path.GetOverride() return override end
function Path.Target() return target end
-- how the party tracker should draw the current target: colour, text glyph, and travel picture (or nil)
function Path.TargetLook()
  local k = target.kind
  if not k then return nil end
  return COLORS[k] or C.gold, ICON[k] or "!", ModeIcon()
end

-- the same look for a target that belongs to someone else (a party member's shared goal)
function Path.KindLook(kind, pic)
  if not kind then return nil end
  return COLORS[kind] or C.gold, ICON[kind] or "!", (kind == "travel" and MODETEX[pic or ""]) or nil
end

-- plain words for what a goal is, e.g. "handing in a quest to Bob" or "travelling by tram: Deeprun Tram"
local MODEWORD = { tram = "by tram", boat = "by boat", zep = "by zeppelin", fly = "by flight path", flyself = "flying", walk = "on foot" }
function Path.GoalText(kind, pic, label)
  local l = (label and label ~= "") and label or nil
  if kind == "A" then return l and ("picking up a quest from " .. l) or "picking up a quest" end
  if kind == "T" then return l and ("handing in a quest to " .. l) or "handing in a quest" end
  if kind == "D" then return l and ("questing: " .. l) or "questing" end
  if kind == "G" or kind == "travel" then
    local how = MODEWORD[pic or ""]
    return "travelling" .. (how and (" " .. how) or "") .. (l and (": " .. l) or "")
  end
  if kind == "L" then return "levelling up first" end
  if kind == "R" or kind == "trainer" then return l and ("training at " .. l) or "visiting a trainer" end
  if kind == "corpse" then return "running back to their corpse" end
  if kind == "friend" then return l and ("going to " .. l) or "going to a party member" end
  if kind == "farm" then return l and ("farming " .. l) or "farming" end
  if kind == "dungeon" then return l and ("heading to " .. l) or "heading to a dungeon" end
  if kind == "inn" then return l and ("going to the inn: " .. l) or "going to an inn" end
  if kind == "mail" then return "going to a mailbox to send items to an alt" end
  return nil
end

-- what to tell the party about my current goal: kind, map, x, y, travel picture, label (map 0 = no position, e.g. another continent)
function Path.ShareTarget()
  local t = target
  if not t.kind then return nil end
  local pic = (t.kind == "travel") and ModeIcon() or nil
  if t.map and t.x and t.y then return t.kind, t.map, t.x, t.y, pic, t.label end
  return t.kind, 0, 0, 0, pic, t.label
end

-- /path trainer: point at the nearest trainer for your class right now
function Path.PointTrainer()
  if override then override = nil; Path.UpdateHUD(); Path.Print("waypoint cleared") return end
  local _, class = UnitClass("player")
  local list = ns.Trainers and ns.Trainers[class]
  if not list then Path.Print("no trainer list for your class") return end
  local fac = (UnitFactionGroup and UnitFactionGroup("player") == "Horde") and "H" or "A"
  local best, bd
  for _, t in ipairs(list) do
    if t[5] == fac or t[5] == "AH" then
      local b, d = Path.Vector(t[2], t[3], t[4])
      if b and (not bd or d < bd) then best, bd = t, d end
    end
  end
  if not best then Path.Print("no class trainer on this continent that I know of") return end
  override = { kind = "trainer", p = { best[3], best[4] }, m = best[2], title = best[1] }
  Path.Print("pointing at " .. best[1] .. ", " .. Fmt(bd) .. " away. /path trainer again clears it.")
  Path.UpdateHUD()
end

-- ------------------------------------------------------------ per-frame drawing
local acc, acc2 = 0, 0
local function Draw()
  if not compass or not compass:IsShown() then return end
  local W = compass:GetWidth() or 560
  local half = FOV / 2
  local facing = GetPlayerFacing and GetPlayerFacing()
  if facing == nil or Secret(facing) then return end          -- hidden in some combat situations: keep the last picture
  local heading = TWO_PI - facing
  local pxPerRad = (W / 2) / half

  if Path.DrawTrail then Path.DrawTrail(target, heading, COLORS[target.kind] or C.gold, ICON[target.kind], lastDt) end

  if Path.DrawFarm then Path.DrawFarm(heading, W, pxPerRad, half, lastDt) end

  for i, fs in ipairs(labels) do
    local rel = Wrap((i - 1) * PI / 4 - heading)
    if math.abs(rel) < half - 0.04 then
      fs:ClearAllPoints(); fs:SetPoint("CENTER", compass, "CENTER", rel * pxPerRad, 0); fs:Show()
    else fs:Hide() end
  end
  for i, t in ipairs(ticks) do
    local ang = (i - 1) * PI / 12
    local rel = Wrap(ang - heading)
    if i % 3 ~= 1 and math.abs(rel) < half - 0.04 then
      t:ClearAllPoints(); t:SetPoint("BOTTOM", compass, "BOTTOM", rel * pxPerRad, 1); t:Show()
    else t:Hide() end
  end

  if target.bearing then
    local rel = Wrap(target.bearing - heading)
    local c = COLORS[target.kind] or C.gold
    local mt = ModeIcon()
    marker.icon:SetText(mt and "" or (ICON[target.kind] or "!"))
    local bold = Path.Opts().boldMarkers ~= false
    if bold then
      marker.chip:SetColorTexture(c[1], c[2], c[3], .95); marker.chip:Show()
      marker.icon:SetTextColor(C.bg[1], C.bg[2], C.bg[3])
    else
      marker.chip:Hide(); marker.icon:SetTextColor(c[1], c[2], c[3])
    end
    if mt then
      local tc = bold and C.bg or c
      marker.tex:SetTexture(TEXDIR .. mt); marker.tex:SetVertexColor(tc[1], tc[2], tc[3], 1); marker.tex:Show()
    else
      marker.tex:Hide()
    end
    marker.arrowL:SetTextColor(c[1], c[2], c[3]); marker.arrowR:SetTextColor(c[1], c[2], c[3])
    local x
    if math.abs(rel) < half - 0.1 then
      x = rel * pxPerRad
      marker.arrowL:Hide(); marker.arrowR:Hide()
    else
      local right = rel > 0
      x = (right and 1 or -1) * (W / 2 - 18)
      marker.arrowL:SetShown(not right); marker.arrowR:SetShown(right)
    end
    marker:ClearAllPoints(); marker:SetPoint("CENTER", compass, "CENTER", x, 0)
    marker:Show()
    marker.dist:ClearAllPoints(); marker.dist:SetPoint("TOP", marker, "BOTTOM", 0, -1)
    marker.dist:SetText(Fmt(target.dist))
    marker.dist:SetTextColor(c[1], c[2], c[3]); marker.dist:Show()
  else
    marker:Hide(); marker.dist:Hide()
  end
end

-- ------------------------------------------------------------ the panel text
local function Hex(c) return UI.Hex(c) end

-- docked under the compass the panel matches its width; elsewhere it is narrower
local function PanelWidth()
  local O = Path.Opts()
  local W = O.compassWidth
  if (O.panelMode or "dock") ~= "dock" then W = math.min(W, 440) end
  return W
end

local function UpdatePanel()
  if not panel then return end
  local O = Path.Opts()
  local route, steps, chapters = Path.Route()
  local W = PanelWidth()
  panel:SetWidth(W)
  panel.title:SetWidth(W - 150); panel.sub:SetWidth(W - 150); panel.tx:SetWidth(W - 30); panel.skill:SetWidth(W - 30)
  panel.big:SetText(""); panel.dist:SetText(""); panel.verb:SetText("")
  panel.tx:SetText(""); panel.sub:SetText(""); panel.skill:SetText("")
  local s, i = Path.Current()
  local d = target.dist
  local near = d and d < 40
  local dtxt = Fmt(d)
  if target.why == "continent" then dtxt = "far away" end

  local tr = (not override) and Track() or nil
  if override or tr then
    local ov = override or tr
    local col = COLORS[ov.kind] or C.blue
    panel.verb:SetText(Hex(col) .. (override and "WAYPOINT" or (ov.kind == "travel" and "TRAVEL" or (ov.class and "CLASS QUEST" or "TRACKING"))) .. "|r"); panel.title:SetText(UI.H.cream .. (ov.title or "Target") .. "|r")
    panel.sub:SetText(UI.H.muted .. (ov.sub or "Manual waypoint. /path trainer again clears it.") .. "|r")
    panel.accent:SetColorTexture(col[1], col[2], col[3], 1)
    panel.big:SetText(near and (UI.H.good .. "HERE|r") or (UI.H.cream .. dtxt .. "|r"))
  elseif not steps then
    panel.verb:SetText(UI.H.gold .. "REALM PATH|r")
    panel.title:SetText("No quest route for your class yet")
    panel.sub:SetText(UI.H.muted .. "No route for your race yet. Trainer stops and the compass still work.|r")
    panel.accent:SetColorTexture(C.muted[1], C.muted[2], C.muted[3], 1)
  elseif not s then
    panel.verb:SetText(UI.H.good .. "DONE|r"); panel.title:SetText("Route finished")
    panel.sub:SetText(UI.H.muted .. "More zones come in later updates.|r")
    panel.accent:SetColorTexture(C.good[1], C.good[2], C.good[3], 1)
  else
    local c = COLORS[s.t] or C.gold
    local verb, name, subt = Path.Describe(s)
    if s.t == "D" then
      local have, need = Path.ObjectiveProgress(s.q, s.npc, s.kind, s.cnt)
      if not have and s.cnt and s.kind ~= "explore" then have, need = 0, s.cnt end
      if have then panel.big:SetText((have >= need and UI.H.good or UI.H.cream) .. have .. "/" .. need .. "|r") end
    end
    panel.verb:SetText(Hex(c) .. verb .. "|r")
    panel.title:SetText(UI.H.cream .. name .. "|r")
    panel.sub:SetText(UI.H.muted .. subt .. "|r")
    panel.accent:SetColorTexture(c[1], c[2], c[3], 1)
    if s.detour and s.skills then
      panel.title:SetText(s.skills)                         -- profession skill levels ARE the headline: big, colored, one row
    elseif (s.t == "G" or s.t == "L" or s.t == "R") and (not O.compact or s.virtual) then
      local txt = s.tx or ""
      if panel.txKey ~= s then panel.txKey = s; panel.txOpen = false end   -- a new step starts folded
      local long = #txt > math.floor((W - 30) / 5.6)
      local mark = long and (UI.H.gold .. (panel.txOpen and "  [-]|r" or "  [+]|r")) or ""
      if panel.tx.SetMaxLines then panel.tx:SetMaxLines(panel.txOpen and 6 or 1) end
      panel.tx:SetText(UI.H.muted .. txt .. "|r" .. mark)
      panel.txLong = long
    end
    if panel.big:GetText() == "" then
      panel.big:SetText(near and (UI.H.good .. "HERE|r") or (UI.H.cream .. dtxt .. "|r"))
    else
      panel.dist:SetText(near and (UI.H.good .. "here|r") or (UI.H.text .. dtxt .. "|r"))
    end
    -- a banner when a quest becomes ready to hand in
    if O.banner and s.t == "T" and not bannered then
      bannered = true
      if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage("Quest complete: " .. (s.n or "") .. (s.npc and (" - hand in to " .. s.npc) or ""), C.good[1], C.good[2], C.good[3]) end
    elseif s.t ~= "T" then bannered = false end
  end

  local skillShown = (panel.skill:GetText() or "") ~= ""
  panel.tx:ClearAllPoints(); panel.tx:SetPoint("TOPLEFT", skillShown and panel.skill or panel.sub, "BOTTOMLEFT", 0, skillShown and -4 or -3)
  if panel.txBtn then
    if (panel.tx:GetText() or "") ~= "" and panel.txLong then
      panel.txBtn:ClearAllPoints()
      panel.txBtn:SetPoint("TOPLEFT", panel.tx, "TOPLEFT", 0, 0)
      panel.txBtn:SetSize(W - 30, math.max(12, panel.tx:GetStringHeight() or 12))
      panel.txBtn:Show()
    else panel.txBtn:Hide() end
  end
  local up = (steps and not override and not tr and not O.compact and not (s and s.detour)) and Path.Upcoming(3) or {}
  local lastAnchor = (panel.tx:GetText() == "") and (skillShown and panel.skill or panel.sub) or panel.tx
  -- one "next" line (the Skip step list shows the rest)
  for k = 1, 3 do panel.next[k]:Hide() end
  if up[1] then
    local f = panel.next[1]
    f:ClearAllPoints(); f:SetPoint("TOPLEFT", lastAnchor, "BOTTOMLEFT", 0, -4)
    f:SetWidth(W - 20)
    f:SetText(UI.H.muted .. "next  |r" .. UI.H.text .. Path.StepText(up[1][1]) .. "|r" .. (#up > 1 and (UI.H.muted .. "  (+" .. (#up - 1) .. ")|r") or ""))
    f:Show(); lastAnchor = f
  end
  -- chapter and level ride on the top label row instead of a row of their own
  panel.prog:SetText("")
  if s and chapters and steps and not O.compact and not override and not tr then
    local ch = chapters[s.ch]
    local goal = ch and ch.exit and ch.exit > 0 and ("/" .. ch.exit) or ""
    panel.verb:SetText((panel.verb:GetText() or "") .. ("   %slvl %d%s|r"):format(UI.H.muted, Path.Level(), goal))
  end
  local h = 28 + (panel.title:GetStringHeight() or 22) + (panel.sub:GetStringHeight() or 12) + (panel.tx:GetStringHeight() or 0)
  if skillShown then h = h + (panel.skill:GetStringHeight() or 24) + 5 end
  local n = 0
  for k = 1, 3 do if panel.next[k]:IsShown() then n = n + 1 end end
  h = h + n * 13 + (n > 0 and 6 or 0) + 10
  h = h + 24                                  -- the button row along the bottom
  -- keep room for the bottom button row and the distance line above it
  local minH = ((panel.dist:GetText() or "") ~= "" and 112) or (O.compact and 92 or 78)
  panel:SetHeight(math.max(minH, h))
  RefreshList()
end
Path.UpdatePanel = UpdatePanel

-- where the info window sits: docked under the compass (default), top left of the screen, or free to drag
local function PlacePanel()
  local O = Path.Opts()
  local mode = O.panelMode or "dock"
  panel:ClearAllPoints()
  if mode == "topleft" then
    panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 12, -12)
  elseif mode == "free" then
    local p = O.panelPos
    if p then panel:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 12, -12) end
  else
    panel:SetPoint("TOP", compass, "BOTTOM", 0, -2)
  end
  panel:EnableMouse(mode == "free" and not O.locked)
end

-- the Legend button sits in the bottom right corner of the info window (of the compass when the window is hidden)
local function PlaceLegendTab()
  if not legendTab then return end
  legendTab:ClearAllPoints()
  if panel and panel:IsShown() then legendTab:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 4)
  else legendTab:SetPoint("BOTTOMRIGHT", compass, "BOTTOMRIGHT", -4, 2) end
end

-- large markers: a filled chip behind a bigger glyph, on the compass and in the legend
local function ApplyMarkerStyle()
  local O = Path.Opts()
  local bold = O.boldMarkers ~= false
  if marker then
    Font(marker.icon, bold and 26 or 22, bold and "" or "OUTLINE")
    Font(marker.arrowL, bold and 18 or 13, bold and "THICKOUTLINE" or "OUTLINE")
    Font(marker.arrowR, bold and 18 or 13, bold and "THICKOUTLINE" or "OUTLINE")
    marker:SetSize(bold and 48 or 40, 30)
  end
  for _, r in ipairs(legendRows) do
    if bold then
      r.chip:SetColorTexture(r.col[1], r.col[2], r.col[3], .95); r.chip:Show()
      r.g:SetTextColor(C.bg[1], C.bg[2], C.bg[3])
    else
      r.chip:Hide(); r.g:SetTextColor(r.col[1], r.col[2], r.col[3])
    end
  end
end

function Path.UpdateHUD()
  if not compass then return end
  local O = Path.Opts()
  compass:SetWidth(O.compassWidth)
  compass:SetScale(O.compassScale or 1)
  panel:SetScale(O.compassScale or 1)
  compass:EnableMouse(not O.locked)
  if O.pos then compass:ClearAllPoints(); compass:SetPoint(O.pos[1], UIParent, O.pos[2], O.pos[3], O.pos[4]) end
  compass:SetShown(O.hud)
  panel:SetShown(O.hud and O.panel)
  PlacePanel(); PlaceLegendTab(); ApplyMarkerStyle(); PlaceMenu()
  Resolve()
  UpdatePanel()
end

function Path.OnReady()
  if compass then return end
  Build()
  compass:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt; acc2 = acc2 + dt; lastDt = dt
    SlideLegend(dt)
    SlideMenu(dt); SlideList(dt)
    if acc >= 0.08 then acc = 0; Resolve() end
    Draw()
    if acc2 >= 0.6 then acc2 = 0; UpdatePanel() end
  end)
  Path.UpdateHUD()
end

Path.OnChange(function() if compass then Resolve(); UpdatePanel() end end)
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function() C_Timer.After(2, function() if Path.Opts() then Path.OnReady() end end) end)

-- /path infopos dock | topleft | free      (free: /path unlock first, then drag the info window)
local prevSlash = Path.SlashExtra
Path.SlashExtra = function(cmd, rest)
  if cmd == "infopos" or cmd == "panelmode" then
    local O = Path.Opts()
    local m = (rest or ""):match("^(%S+)")
    if m == "dock" or m == "docked" then O.panelMode = "dock"
    elseif m == "topleft" or m == "left" then O.panelMode = "topleft"
    elseif m == "free" then O.panelMode = "free"
    else Path.Print("/path infopos dock | topleft | free   (now: " .. (O.panelMode or "dock") .. ")") return true end
    Path.UpdateHUD()
    Path.Print("info window: " .. O.panelMode .. (O.panelMode == "free" and ". /path unlock, then drag it; /path lock when done." or ""))
    return true
  end
  if prevSlash then return prevSlash(cmd, rest) end
end
