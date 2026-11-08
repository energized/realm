-- NpcMarker: when the compass says HERE for an accept, hand-in or "see" step, a bobbing marker
-- (! gold for accept, ? green for hand-in, R purple for trainers) floats over that NPC's nameplate.
-- It needs the game to show that NPC's nameplate (friendly NPC nameplates on, NPC within nameplate range).
-- Without a nameplate nothing can be drawn over a head, so it stays hidden; the compass still works as before.
local ADDON, ns = ...
local Path = ns.Path
local UI = ns.UI

local NEAR, FAR = 40, 50        -- shown inside NEAR (the same distance the panel calls HERE), hidden again past FAR
local TIP_AFTER = 3             -- seconds at HERE with no nameplate before the one-time tip
local KIND = { A = { "!", "gold" }, T = { "?", "good" }, R = { "R", "purple" } }

local marker, shown, tipped, hereSince

local function Secret(v) return issecretvalue and v ~= nil and issecretvalue(v) end
local function Norm(s) return ((tostring(s or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))) end

local function Build()
  marker = CreateFrame("Frame", "RealmNpcMarker", UIParent)
  marker:SetSize(30, 40)
  marker:SetFrameStrata("HIGH")
  marker.glyph = marker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  marker.glyph:SetPoint("TOP", marker, "TOP", 0, 0)
  marker.arrow = marker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  marker.arrow:SetPoint("TOP", marker.glyph, "BOTTOM", 0, 4)
  marker.arrow:SetText("v")
  local font = (UI and UI.FONT) or STANDARD_TEXT_FONT
  if marker.glyph.SetFont and font then
    marker.glyph:SetFont(font, 30, "THICKOUTLINE")
    marker.arrow:SetFont(font, 16, "THICKOUTLINE")
  end
  marker:SetScript("OnUpdate", function(self)
    local bob = 3 * math.sin((GetTime and GetTime() or 0) * 6)
    self.glyph:ClearAllPoints(); self.glyph:SetPoint("TOP", self, "TOP", 0, bob)
  end)
  marker:Hide()
end

local function Hide()
  shown = false
  if marker and marker:IsShown() then marker:Hide() end
end

-- the nameplate frame whose unit has this NPC name, or nil
local function FindPlate(name)
  if not (C_NamePlate and C_NamePlate.GetNamePlates and UnitName) then return nil end
  local want = Norm(name)
  for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
    local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
    if unit then
      local n = UnitName(unit)
      if n and not Secret(n) and Norm(n) == want then return plate end
    end
  end
  return nil
end

-- friendly NPC nameplates switched off is the usual reason there is nothing to attach to: say so once, change nothing
local function TipOnce(now)
  if tipped then return end
  hereSince = hereSince or now
  if now - hereSince < TIP_AFTER then return end
  local off = false
  if GetCVar then
    local ok, v = pcall(GetCVar, "nameplateShowFriendlyNPCs")
    off = ok and v == "0"
  end
  if off then
    tipped = true
    Path.Print("quest marker needs friendly NPC nameplates. Turn them on in Options > Interface > Names, or switch it off with /path marker.")
  end
end

local function Tick()
  local O = Path.Opts and Path.Opts()
  if not O or O.npcMarker == false then Hide() return end
  local t = Path.Target and Path.Target()
  local k = t and KIND[t.kind]
  if not (k and t.label and t.dist) then Hide() hereSince = nil return end
  if t.dist >= (shown and FAR or NEAR) then Hide() hereSince = nil return end
  local plate = FindPlate(t.label)
  if not plate then
    Hide()
    TipOnce(GetTime and GetTime() or 0)
    return
  end
  hereSince = nil
  if not marker then Build() end
  local c = (UI and UI.C and UI.C[k[2]]) or { 1, .82, 0 }
  marker.glyph:SetText(k[1])
  marker.glyph:SetTextColor(c[1], c[2], c[3])
  marker.arrow:SetTextColor(c[1], c[2], c[3])
  marker:ClearAllPoints()
  marker:SetPoint("BOTTOM", plate, "TOP", 0, 2)
  marker:Show()
  shown = true
end

local driver = CreateFrame("Frame")
local acc = 0
driver:SetScript("OnUpdate", function(_, dt)
  acc = acc + (dt or 0)
  if acc < 0.2 then return end
  acc = 0
  Tick()
end)

Path.NpcMarker = { Tick = Tick, Find = FindPlate, Marker = function() return marker end, NEAR = NEAR, FAR = FAR }
