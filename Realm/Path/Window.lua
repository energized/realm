-- Route window: zones, what is coming up, and the option switches.
local ADDON, ns = ...
local Path = ns.Path
local UI = ns.UI
local C = UI.C

Path.Window = {}
local W = Path.Window
local f
local chapterRows, stepRows, optBtns = {}, {}, {}

local OPTIONS = {
  { "autoAccept", "Auto accept quests", "Accepts route quests when you open a quest giver." },
  { "autoTurnin", "Auto hand in quests", "Hands in finished route quests." },
  { "smartReward", "Smart reward pick", "Picks the best upgrade for you, or the best vendor price." },
  { "offRoute", "Also accept off-route quests", "Automation is not limited to route quests." },
  { "banner", "Quest ready banner", "Message when a quest is ready to hand in." },
  { "corpse", "Compass points to corpse", "While you are a ghost." },
  { "levelTips", "Level up reminders", "Chat hint on level up." },
  { "trainers", "Class trainer stops", "Points you at your trainer every other level." },
  { "trail", "Minimap trail", "Dashed line on the minimap toward your target." },
  { "friends", "Party on compass", "Shows party members from the Party tracker." },
  { "tapWarn", "TAKEN tag", "Warns when your target is already tagged." },
  { "farm", "Farming spots ($)", "Shows the best nearby grinding spot when you have no quest." },
  { "professions", "Professions helper", "New-class profession picker, trainer stops, and level-up detours." },
  { "compact", "Compact info window", "A shorter info window under the compass." },
  { "boldMarkers", "Large compass markers", "Filled, thicker markers that are easy to spot at a glance." },
  { "panelMode", "Info window position", "Click to cycle: docked under the compass, top left of the screen, or free to drag (/path unlock first).",
    cycle = { "dock", "topleft", "free" }, names = { dock = "Docked", topleft = "Top left", free = "Free" } },
}

local function Build()
  f = CreateFrame("Frame", "RealmPathWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(560, 704); f:SetPoint("CENTER"); f:SetFrameStrata("HIGH")
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton"); f:SetClampedToScreen(true)
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  UI.Skin(f)
  if UISpecialFrames then table.insert(UISpecialFrames, "RealmPathWindow") end

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -14); title:SetText(UI.H.gold .. "Realm|r " .. UI.H.cream .. "Path|r")
  f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
  local x = CreateFrame("Button", nil, f)
  x:SetSize(22, 22); x:SetPoint("TOPRIGHT", -8, -8); UI.Button(x)
  x.t = x:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); x.t:SetPoint("CENTER"); x.t:SetText("X")
  x:SetScript("OnClick", function() f:Hide() end)

  local function Header(text, y)
    local h = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", 16, y); h:SetText(UI.H.gold .. text .. "|r")
    return h
  end
  Header("Zones", -62)
  for i = 1, 8 do
    local r = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r:SetPoint("TOPLEFT", 22, -84 - (i - 1) * 16); r:SetWidth(520); r:SetJustifyH("LEFT")
    chapterRows[i] = r
  end
  Header("Coming up", -222)
  for i = 1, 10 do
    local r = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r:SetPoint("TOPLEFT", 22, -244 - (i - 1) * 15); r:SetWidth(520); r:SetJustifyH("LEFT")
    stepRows[i] = r
  end
  Header("Options", -408)
  for i, o in ipairs(OPTIONS) do
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(258, 22); b:SetPoint("TOPLEFT", 16 + col * 268, -430 - row * 26)
    UI.Button(b)
    b.t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.t:SetPoint("LEFT", 8, 0); b.t:SetText(o[2])
    b.v = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.v:SetPoint("RIGHT", -8, 0)
    b:SetScript("OnClick", function()
      local O = Path.Opts()
      if o.cycle then
        local now, nxt = O[o[1]] or o.cycle[1], o.cycle[1]
        for k, v in ipairs(o.cycle) do if v == now then nxt = o.cycle[k % #o.cycle + 1] end end
        O[o[1]] = nxt
      else
        O[o[1]] = not O[o[1]]
      end
      Path.UpdateHUD(); Path.Changed(true)
    end)
    b:SetScript("OnEnter", function(self)
      if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(o[2]); GameTooltip:AddLine(o[3], .8, .8, .8, true); GameTooltip:Show() end
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    optBtns[i] = b
  end
  local function Act(text, xx, fn)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(120, 24); b:SetPoint("BOTTOMLEFT", xx, 14); UI.Button(b)
    b.t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.t:SetPoint("CENTER"); b.t:SetText(text)
    b:SetScript("OnClick", fn)
  end
  Act("Skip step", 16, function() Path.Skip() end)
  Act("Skip zone", 144, function() Path.SkipChapter() end)
  Act("Reset skips", 272, function() SlashCmdList["REALMPATH"]("reset") end)
  Act("Trainer", 400, function() Path.PointTrainer() end)
end

function W.Refresh()
  if not f or not f:IsShown() then return end
  local O = Path.Opts()
  local route, steps, chapters = Path.Route()
  local lvl = Path.Level()
  if route and Path.generic then f.sub:SetText(("Level %d   |   general quest route (no exact route for your race yet)"):format(lvl))
  elseif route and Path.raceOnly then f.sub:SetText(("Level %d   |   route: %s start zones (no class quests)"):format(lvl, route.info.race))
  elseif route then f.sub:SetText(("Level %d   |   route: %s %s"):format(lvl, route.info.race, route.info.class))
  else f.sub:SetText(("Level %d   |   no quest route for your class yet"):format(lvl)) end
  local s = Path.RealStep and Path.RealStep()
  local curCh = s and s.ch
  for i, r in ipairs(chapterRows) do
    local c = chapters and chapters[i]
    if c then
      local mark = (i == curCh) and ("  " .. UI.H.good .. "<- you are here|r") or ""
      if c.exit and c.exit > 0 and lvl >= c.exit then mark = "  " .. UI.H.muted .. "done|r" end
      r:SetText(("%d. %s  %s(levels %s)|r%s"):format(i, c.name, UI.H.muted, c.hint, mark)); r:Show()
    else r:Hide() end
  end
  local up = Path.Upcoming(10)
  for i, r in ipairs(stepRows) do
    local e = up[i]
    if e then r:SetText(Path.StepText(e[1])); r:Show() else r:Hide() end
  end
  for i, b in ipairs(optBtns) do
    local def = OPTIONS[i]
    if def.cycle then
      b.v:SetText(UI.H.gold .. (def.names[O[def[1]] or def.cycle[1]] or "?") .. "|r")
    else
      local on = O[def[1]] ~= false and O[def[1]]
      b.v:SetText(on and (UI.H.good .. "ON|r") or (UI.H.muted .. "off|r"))
    end
  end
end

function W.Toggle()
  if not f then Build() end
  f:SetShown(not f:IsShown())
  W.Refresh()
end
