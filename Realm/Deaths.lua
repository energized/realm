-- Death Loop: a running death counter on the minimap. Each character keeps its own count.
local ADDON, ns = ...
local DL = {}
ns.Deaths = DL

local ICON = "Interface\\AddOns\\Realm\\icon"
local DB, win
local dead = false

local function Print(m) print("|cffe8ab35Realm|r |cffff5a4fdeaths|r: " .. tostring(m)) end

local function Key()
  local name = UnitName("player") or "?"
  local realm = (GetRealmName and GetRealmName()) or ""
  return name .. "-" .. realm, name, realm
end

local function Me()
  local key, name, realm = Key()
  local c = DB.chars[key]
  if not c then
    c = { deaths = 0, name = name, realm = realm }
    DB.chars[key] = c
  end
  local _, token = UnitClass("player")
  c.class = token or c.class
  c.level = UnitLevel("player") or c.level
  return c, key
end

local function Short(n)
  if n >= 100000 then return math.floor(n / 1000) .. "k" end
  if n >= 10000 then return string.format("%.1fk", n / 1000):gsub("%.0k", "k") end
  return tostring(n)
end

local function ClassHex(token)
  local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
  if c then return string.format("%02x%02x%02x", math.floor(c.r * 255 + .5), math.floor(c.g * 255 + .5), math.floor(c.b * 255 + .5)) end
  return "ffffff"
end

local function Ago(t)
  if not t then return "never" end
  local d = (time and time() or 0) - t
  if d < 60 then return "just now" end
  if d < 3600 then return math.floor(d / 60) .. "m ago" end
  if d < 86400 then return math.floor(d / 3600) .. "h ago" end
  return math.floor(d / 86400) .. "d ago"
end

local function Total()
  local n = 0
  for _, c in pairs(DB.chars) do n = n + (c.deaths or 0) end
  return n
end
DL.Total = Total

-- ------------------------------------------------------------ display
local function Refresh()
  local c = Me()
  if ns.Minimap and ns.Minimap.SetCount then ns.Minimap.SetCount(Short(c.deaths or 0)) end
  if win and win:IsShown() then DL.Rebuild() end
end
DL.Refresh = Refresh

local function Pulse()
  if ns.Minimap and ns.Minimap.Pulse then ns.Minimap.Pulse() end
end

function DL.Died()
  local c = Me()
  c.deaths = (c.deaths or 0) + 1
  c.lastTime = time and time() or nil
  c.lastZone = (GetZoneText and GetZoneText()) or ""
  local sub = GetSubZoneText and GetSubZoneText() or ""
  if sub ~= "" then c.lastZone = c.lastZone .. " - " .. sub end
  Refresh()
  Pulse()
  if not DB.quiet then Print("death #" .. c.deaths .. " for " .. c.name .. ". Total across characters: " .. Total()) end
end

-- ------------------------------------------------------------ window
local rows = {}
function DL.Rebuild()
  if not win then return end
  local list = {}
  for key, c in pairs(DB.chars) do list[#list + 1] = { key = key, c = c } end
  table.sort(list, function(a, b) return (a.c.deaths or 0) > (b.c.deaths or 0) end)
  local meKey = Key()
  for i, e in ipairs(list) do
    local r = rows[i]
    if not r then
      r = CreateFrame("Frame", nil, win)
      r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
      r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.name:SetPoint("TOPLEFT", 10, -6)
      r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
      r.num = r:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge"); r.num:SetPoint("RIGHT", -12, 0)
      rows[i] = r
    end
    r:SetSize(316, 40)
    r:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -52 - (i - 1) * 43)
    r.bg:SetColorTexture(.118, .165, .22, (e.key == meKey) and 1 or .7)
    r.name:SetText("|cff" .. ClassHex(e.c.class) .. e.c.name .. "|r" .. (e.key == meKey and "  |cff888888(you)|r" or ""))
    r.sub:SetText((e.c.realm or "") .. "   last: " .. Ago(e.c.lastTime) .. ((e.c.lastZone and e.c.lastZone ~= "") and ("  " .. e.c.lastZone) or ""))
    r.num:SetText("|cffff4444" .. (e.c.deaths or 0) .. "|r")
    r:Show()
  end
  for i = #list + 1, #rows do rows[i]:Hide() end
  win.total:SetText("Total deaths: |cffff4444" .. Total() .. "|r")
  win:SetHeight(100 + #list * 43)
end

local function BuildWindow()
  win = CreateFrame("Frame", "RealmDeathsWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  win:SetSize(340, 160)
  win:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
  win:SetFrameStrata("HIGH")
  win:SetMovable(true); win:EnableMouse(true); win:SetClampedToScreen(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", function(s) s:StartMoving() end)
  win:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
  ns.UI.Skin(win)
  if UISpecialFrames then table.insert(UISpecialFrames, "RealmDeathsWindow") end
  local bar = win:CreateTexture(nil, "ARTWORK")
  bar:SetPoint("TOPLEFT", 1, -1); bar:SetPoint("TOPRIGHT", -1, -1); bar:SetHeight(2); bar:SetColorTexture(.77, .13, .106, 1)
  local logo = win:CreateTexture(nil, "OVERLAY"); logo:SetSize(30, 30); logo:SetPoint("TOPLEFT", 12, -10); logo:SetTexture(ICON)
  local t = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  t:SetPoint("LEFT", logo, "RIGHT", 8, 0); t:SetText("|cffff5a4fDeath|r |cffe9edf3Loop|r")
  win.total = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  win.total:SetPoint("BOTTOMLEFT", 14, 12)
  local x = CreateFrame("Button", nil, win)
  x:SetSize(22, 22); x:SetPoint("TOPRIGHT", -8, -8)
  x.bg = x:CreateTexture(nil, "BACKGROUND"); x.bg:SetAllPoints(); x.bg:SetColorTexture(.133, .196, .29, 1)
  x.l = x:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); x.l:SetPoint("CENTER"); x.l:SetText("X")
  x:SetScript("OnClick", function() win:Hide() end)
  win:Hide()
end

function DL.Toggle()
  if not win then BuildWindow() end
  if win:IsShown() then win:Hide() else win:Show(); DL.Rebuild() end
end


-- ------------------------------------------------------------ tooltip lines for the minimap button
function DL.Tooltip(tip)
  local c = Me()
  tip:AddLine(" ")
  tip:AddDoubleLine("Deaths: " .. c.name, "|cffff4444" .. (c.deaths or 0) .. "|r", 1, 1, 1)
  tip:AddLine("Last death: " .. Ago(c.lastTime) .. ((c.lastZone and c.lastZone ~= "") and (" in " .. c.lastZone) or ""), .7, .7, .7)
  local others = {}
  for _, o in pairs(DB.chars) do if o ~= c then others[#others + 1] = o end end
  table.sort(others, function(a, b) return (a.deaths or 0) > (b.deaths or 0) end)
  for i = 1, math.min(#others, 6) do
    local o = others[i]
    tip:AddDoubleLine("|cff" .. ClassHex(o.class) .. o.name .. "|r", tostring(o.deaths or 0), 1, 1, 1, 1, .5, .5)
  end
  tip:AddDoubleLine("All characters", "|cffff4444" .. Total() .. "|r", .8, .8, .8)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_DEAD")
ev:RegisterEvent("PLAYER_ALIVE")
ev:RegisterEvent("PLAYER_UNGHOST")
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    local R = ns.DB
    R.deaths = R.deaths or { chars = {} }
    DB = R.deaths
    DB.chars = DB.chars or {}
    -- one-time import of the old Death Loop counts
    if not R.deathsImported then
      R.deathsImported = true
      if DeathLoopDB and DeathLoopDB.chars then
        for k, c in pairs(DeathLoopDB.chars) do if not DB.chars[k] then DB.chars[k] = c end end
        if DeathLoopDB.quiet then DB.quiet = true end
      end
    end
    dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") or false
    Refresh()
  elseif event == "PLAYER_DEAD" then
    if DB and not dead then dead = true; DL.Died() end
  else
    if not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then dead = false end
  end
end)

SLASH_REALMDEATHS1 = "/dl"
SLASH_REALMDEATHS2 = "/deathloop"
SlashCmdList["REALMDEATHS"] = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if not DB then return end
  if msg == "" then DL.Toggle()
  elseif msg == "quiet" then
    DB.quiet = not DB.quiet; Print("chat messages " .. (DB.quiet and "off" or "on"))
  elseif msg == "reset" then
    Print("this will zero THIS character. Type /dl reset confirm to do it.")
  elseif msg == "reset confirm" then
    local c = Me(); c.deaths = 0; c.lastTime = nil; c.lastZone = nil; Refresh(); Print("counter reset for " .. c.name)
  elseif msg == "total" or msg == "stats" then
    local c = Me(); Print(c.name .. ": " .. (c.deaths or 0) .. " deaths. All characters: " .. Total())
  else
    Print("/dl (list)  /dl total  /dl quiet  /dl reset")
  end
end
