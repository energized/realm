-- Realm: minimap button (draggable around the minimap).
local ADDON, ns = ...
ns.Minimap = {}

local ICON = "Interface\\AddOns\\Realm\\icon"
local button, DB
local RADIUS_PAD = 5

local function Place()
  if not button then return end
  local angle = math.rad(DB.mmAngle or 215)
  local r = (Minimap:GetWidth() / 2) + RADIUS_PAD
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function CursorAngle()
  local mx, my = Minimap:GetCenter()
  local scale = Minimap:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  cx, cy = cx / scale, cy / scale
  local atan = math.atan2 or math.atan
  return math.deg(atan(cy - my, cx - mx))
end

local function Build()
  local b = CreateFrame("Button", "RealmMinimapButton", Minimap)
  b:SetSize(36, 36)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
  b:RegisterForDrag("LeftButton")

  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexture(ICON)

  b.glow = b:CreateTexture(nil, "OVERLAY")
  b.glow:SetPoint("CENTER")
  b.glow:SetSize(50, 50)
  b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  b.glow:SetBlendMode("ADD")
  b.glow:SetVertexColor(1, .55, 0, .9)
  b.glow:Hide()

  -- death counter badge
  b.count = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.count:SetPoint("BOTTOM", b, "TOP", 0, -4)
  b.count:SetTextColor(1, .25, .25)
  if b.count.SetFont then b.count:SetFont("Fonts\\ARIALN.TTF", 11, "OUTLINE") end

  b:SetScript("OnEnter", function(self)
    self.glow:Show()
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cffe8ab35Realm|r")
    local sharing = DB.track and "|cff33ff66sharing|r" or "|cffff4040not sharing|r"
    GameTooltip:AddLine("Location: " .. sharing, 1, 1, 1)
    if ns.Deaths and ns.Deaths.Tooltip and ns.DB.deaths then ns.Deaths.Tooltip(GameTooltip) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffffd100Left-click|r  Realm menu", .8, .8, .8)
    GameTooltip:AddLine("|cffffd100Right-click|r  The Boys (gear and guides)", .8, .8, .8)
    GameTooltip:AddLine("|cffffd100Ctrl-click|r  Death counter list", .8, .8, .8)
    GameTooltip:AddLine("|cffffd100Shift-click|r  Exchange settings", .8, .8, .8)
    GameTooltip:AddLine("|cffffd100Middle-click|r  Toggle location sharing", .8, .8, .8)
    GameTooltip:AddLine("|cffffd100Drag|r  Move this button", .8, .8, .8)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self)
    self.glow:Hide()
    if GameTooltip then GameTooltip:Hide() end
  end)

  b:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" then
      if ns.TB and ns.TB.Window then ns.TB.Window.Toggle() end
    elseif btn == "MiddleButton" then
      ns.Tracker.SetTrack()
    elseif IsShiftKeyDown() then
      ns.Exchange.Command("settings")
    elseif IsControlKeyDown and IsControlKeyDown() then
      ns.Deaths.Toggle()
    else
      ns.Minimap.ToggleMenu()
    end
  end)

  b:SetScript("OnDragStart", function(self)
    self.dragging = true
    if GameTooltip then GameTooltip:Hide() end
    self:SetScript("OnUpdate", function()
      DB.mmAngle = CursorAngle()
      Place()
    end)
  end)
  b:SetScript("OnDragStop", function(self)
    self.dragging = false
    self:SetScript("OnUpdate", nil)
  end)
  return b
end

-- ------------------------------------------------------------ menu
local menu
local function BuildMenu()
  local f = CreateFrame("Frame", "RealmMenu", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true)
  ns.UI.Skin(f)
  if UISpecialFrames then table.insert(UISpecialFrames, "RealmMenu") end
  local items = {
    { "Exchange (market)", function() ns.Exchange.Command("") end },
    { "Party tracker", function() ns.Tracker.Show() end },
    { "Leveling path and compass", function() if ns.Path and ns.Path.Window then ns.Path.Window.Toggle() end end },
    { "The Boys: gear and guides", function() if ns.TB and ns.TB.Window then ns.TB.Window.Toggle() end end },
    { "Death counter", function() ns.Deaths.Toggle() end },
    { "Toggle location sharing", function() ns.Tracker.SetTrack() end },
  }
  f:SetSize(196, 12 + #items * 24)
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetPoint("TOPLEFT", 10, -7); title:SetText("|cffe8ab35Realm|r")
  f:SetHeight(30 + #items * 24)
  for i, it in ipairs(items) do
    local btn = CreateFrame("Button", nil, f)
    btn:SetSize(184, 22); btn:SetPoint("TOPLEFT", 6, -22 - (i - 1) * 24)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND"); btn.bg:SetAllPoints(); btn.bg:SetColorTexture(.133, .196, .29, 1)
    btn.hl = btn:CreateTexture(nil, "HIGHLIGHT"); btn.hl:SetAllPoints(); btn.hl:SetColorTexture(.77, .13, .106, .4)
    btn.t = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.t:SetPoint("LEFT", 8, 0); btn.t:SetText(it[1])
    btn:SetScript("OnClick", function() f:Hide(); it[2]() end)
  end
  f:Hide()
  return f
end

function ns.Minimap.ToggleMenu()
  if not menu then menu = BuildMenu() end
  if menu:IsShown() then menu:Hide() return end
  menu:ClearAllPoints()
  menu:SetPoint("TOPRIGHT", button, "BOTTOMLEFT", 6, 4)
  menu:Show()
end

function ns.Minimap.SetCount(t)
  if button then button.count:SetText(t) end
end

function ns.Minimap.Pulse()
  if not button then return end
  button.glow:SetVertexColor(1, .1, .1, 1); button.glow:Show(); button.flashT = 0
  button:SetScript("OnUpdate", function(self, dt)
    self.flashT = (self.flashT or 0) + dt
    local a = 1 - self.flashT / 1.2
    if a <= 0 then self.glow:Hide(); self.glow:SetVertexColor(1, .55, 0, .9); self:SetScript("OnUpdate", nil)
    else self.glow:SetAlpha(a) end
  end)
end

function ns.Minimap.Toggle()
  DB.mmHide = not DB.mmHide
  button:SetShown(not DB.mmHide)
  ns.Print("Minimap button " .. (DB.mmHide and "hidden. /realm minimap shows it again." or "shown."))
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  DB = ns.DB
  if DB.mmAngle == nil then DB.mmAngle = 215 end
  if DB.mmHide == nil then DB.mmHide = false end
  button = Build()
  Place()
  button:SetShown(not DB.mmHide)
end)
