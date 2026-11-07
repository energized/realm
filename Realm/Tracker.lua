-- Realm: opt-in party location tracker (addon messages + pop-out window).
local ADDON, ns = ...
local PREFIX = "REALM"
local peers = {}            -- short name -> { map, x, y, t }
local DB
local frame, driver
local rows, dots, pins = {}, {}, {}
local MAXPINS = 40
local MAXROWS, MAXDOTS = 10, 40
local STALE = 8
local COLORS = {
  { 1, .5, 0 }, { .2, .8, 1 }, { .4, 1, .4 }, { 1, .3, .6 }, { 1, .9, .2 },
  { .7, .5, 1 }, { .3, 1, .9 }, { 1, .6, .6 }, { .8, .8, .8 }, { .6, .8, .2 },
}

local RING = "Interface\\AddOns\\Realm\\ring"
local DISC = "Interface\\AddOns\\Realm\\disc"
local CLASS_ART = "Interface\\TargetingFrame\\UI-Classes-Circles"
local CLASS_TC = {
  WARRIOR = { 0, .25, 0, .25 }, MAGE = { .25, .5, 0, .25 }, ROGUE = { .5, .75, 0, .25 },
  DRUID = { .75, 1, 0, .25 }, HUNTER = { 0, .25, .25, .5 }, SHAMAN = { .25, .5, .25, .5 },
  PRIEST = { .5, .75, .25, .5 }, WARLOCK = { .75, 1, .25, .5 }, PALADIN = { 0, .25, .5, .75 },
  DEATHKNIGHT = { .25, .5, .5, .75 }, MONK = { .5, .75, .5, .75 }, DEMONHUNTER = { .75, 1, .5, .75 },
}
local function ClassColor(class, fallback)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return { c.r, c.g, c.b } end
  return fallback
end
local function ClassCoords(class)
  return class and ((CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]) or CLASS_TC[class])
end
local function PeerClass(name, p)
  if p.class and p.class ~= "" then return p.class end
  local ok, _, cls = pcall(UnitClass, name)
  if ok then return cls end
end

local Send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
local function RegisterPrefix()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  elseif RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(PREFIX)
  end
end

local function GroupChannel()
  if IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) then return "INSTANCE_CHAT" end
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
end

local function MyPos()
  if not (C_Map and C_Map.GetBestMapForUnit) then return end
  local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
  if not ok or not map then return end
  local x, y
  if C_Map.GetPlayerMapPosition then
    local ok2, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if ok2 and pos then x, y = pos:GetXY() end
    if x == 0 and y == 0 then x, y = nil, nil end
  end
  return map, x, y     -- x, y are nil inside instances (the game hides them)
end

local function MapName(map)
  local info = map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
  return info and info.name or "Unknown"
end

local function WorldPos(map, x, y)
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
  local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
  if not ok or not pos then return end
  local wx, wy = pos:GetXY()
  return cont, wx, wy
end

local function Yards(m1, x1, y1, m2, x2, y2)
  local c1, ax, ay = WorldPos(m1, x1, y1)
  local c2, bx, by = WorldPos(m2, x2, y2)
  if c1 and c1 == c2 then return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end
end

local function ContinentOf(map)
  local cont = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
  local m, guard = map, 0
  while m and m ~= 0 and guard < 12 do
    local ok, info = pcall(C_Map.GetMapInfo, m)
    if not ok or not info then return end
    if info.mapType == cont then return m end
    m, guard = info.parentMapID, guard + 1
  end
end

-- convert (map, x, y) to coordinates on the map we are displaying
local function ToDisplay(map, x, y, disp)
  if not (map and x and disp) then return end
  if map == disp then return x, y end
  if not (C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return end
  local ok, cont, wpos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
  if not ok or not wpos then return end
  local ok2, _, pos = pcall(C_Map.GetMapPosFromWorldPos, cont, wpos, disp)
  if not ok2 or not pos then return end
  local px, py = pos:GetXY()
  if px and py and px >= 0 and px <= 1 and py >= 0 and py <= 1 then return px, py end
end

local pinCache = {}
local function Entrances(map)
  if pinCache[map] ~= nil then return pinCache[map] end
  local list = {}
  if C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap then
    local ok, res = pcall(C_EncounterJournal.GetDungeonEntrancesForMap, map)
    if ok and type(res) == "table" then list = res end
  end
  pinCache[map] = list
  return list
end

-- ---------- sending ----------
local function Broadcast()
  local ch = GroupChannel()
  if not ch then return end
  local map, x, y = MyPos()
  local _, cls = UnitClass("player")
  cls = cls or ""
  if map and x then
    pcall(Send, PREFIX, ("P:%d:%.4f:%.4f:%s"):format(map, x, y, cls), ch)
  elseif map then
    pcall(Send, PREFIX, ("I:%d:%s"):format(map, cls), ch)   -- in an instance: map only
  end
end

local function SendOff()
  local ch = GroupChannel()
  if ch then pcall(Send, PREFIX, "OFF", ch) end
end


-- ---------- zone map art + zoom ----------
local viewW, viewH = 204, 204      -- viewport size (follows the window)
local rowsN = 0
local zoom = 1
local artMap, layer = nil, nil
local tiles = {}

local function ArtSize()
  if layer then
    local s = viewW * zoom / layer.lw
    return layer.lw * s, layer.lh * s
  end
  return viewW * zoom, viewW * zoom
end

-- No map art from the client: draw a labelled grid (a line every 10%) so positions are still readable.
local gridLines, gridText = {}, nil
local function GridShow(on, w, h)
  if not frame then return end
  if not on then
    for _, t in ipairs(gridLines) do t:Hide() end
    if gridText then gridText:Hide() end
    return
  end
  for i = 1, 9 do
    local v, hz = gridLines[i], gridLines[9 + i]
    if not v then
      v = frame.art:CreateTexture(nil, "BACKGROUND"); v:SetColorTexture(.64, .69, .75, .22); gridLines[i] = v
      hz = frame.art:CreateTexture(nil, "BACKGROUND"); hz:SetColorTexture(.64, .69, .75, .22); gridLines[9 + i] = hz
    end
    v:ClearAllPoints(); v:SetPoint("TOPLEFT", frame.art, "TOPLEFT", w * i / 10, 0); v:SetSize(1, h); v:Show()
    hz:ClearAllPoints(); hz:SetPoint("TOPLEFT", frame.art, "TOPLEFT", 0, -h * i / 10); hz:SetSize(w, 1); hz:Show()
  end
  if not gridText then
    gridText = frame.art:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    gridText:SetPoint("TOPLEFT", frame.art, "TOPLEFT", 4, -4)
    gridText:SetText("No map art for this zone. Grid lines are every 10%.")
  end
  gridText:Show()
end

local function Relayout()
  if not frame then return end
  local w, h = ArtSize()
  frame.art:SetSize(w, h)
  for _, t in ipairs(tiles) do t:Hide() end
  GridShow(not layer, w, h)
  if not layer then return end
  local s = viewW * zoom / layer.lw
  for i, tex in ipairs(layer.texs) do
    local t = tiles[i]
    if not t then
      t = frame.art:CreateTexture(nil, "BACKGROUND")
      tiles[i] = t
    end
    local col, row = (i - 1) % layer.cols, math.floor((i - 1) / layer.cols)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", frame.art, "TOPLEFT", col * layer.tw * s, -row * layer.th * s)
    t:SetSize(layer.tw * s, layer.th * s)
    t:SetTexture(tex)
    t:Show()
  end
end

local function UpdateArt(map)
  if not frame or map == artMap then return end
  artMap, layer = map, nil
  if map and C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures then
    pcall(function()
      local layers = C_Map.GetMapArtLayers(map)
      local l = layers and layers[1]
      local texs = l and C_Map.GetMapArtLayerTextures(map, 1)
      if l and texs and #texs > 0 then
        layer = { tw = l.tileWidth, th = l.tileHeight, lw = l.layerWidth, lh = l.layerHeight,
                  cols = math.ceil(l.layerWidth / l.tileWidth), texs = texs }
      end
    end)
  end
  Relayout()
end

local function SetZoom(z)
  zoom = math.max(1, math.min(8, z))
  if DB then DB.trackZoom = zoom end
  Relayout()
end

-- ---------- UI ----------
local function Build()
  local f = CreateFrame("Frame", "RealmTracker", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  local sz = DB.trackSize
  f:SetSize(sz and sz[1] or 230, sz and sz[2] or 340)
  f:SetPoint("CENTER")
  f:SetResizable(true)
  pcall(function()
    if f.SetResizeBounds then f:SetResizeBounds(200, 220, 900, 900)
    else f:SetMinResize(200, 220); f:SetMaxResize(900, 900) end
  end)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    DB.trackPos = { p, rp, x, y }
  end)
  ns.UI.Skin(f)

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOPLEFT", 8, -8)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() ns.Tracker.Show(false) end)

  -- mini map viewport (clips the art so zoom stays inside the box)
  f.map = CreateFrame("Frame", nil, f)
  f.map:SetPoint("TOPLEFT", 8, -28)
  f.AnchorMap = function(n)
    f.map:ClearAllPoints()
    f.map:SetPoint("TOPLEFT", 8, -28)
    f.map:SetPoint("BOTTOMRIGHT", -8, 14 + n * 16)
  end
  f.AnchorMap(2)
  if f.map.SetClipsChildren then f.map:SetClipsChildren(true) end
  local bg = f.map:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(.118, .165, .22, 1)
  f.art = CreateFrame("Frame", nil, f.map)
  f.art:SetPoint("TOPLEFT", f.map, "TOPLEFT", 0, 0)
  f.art:SetSize(viewW, viewH)

  -- dots live in a frame ABOVE the art, otherwise the map covers them
  f.dots = CreateFrame("Frame", nil, f.map)
  f.dots:SetAllPoints(f.map)
  f.dots:SetFrameLevel(f.art:GetFrameLevel() + 3)
  f.zone = f.dots:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.zone:SetPoint("BOTTOMLEFT", 3, 3)
  f.pdots = CreateFrame("Frame", nil, f.map)           -- player dots: above dungeon pins
  f.pdots:SetAllPoints(f.map)
  f.pdots:SetFrameLevel(f.dots:GetFrameLevel() + 8)
  for i = 1, MAXDOTS do
    local d = CreateFrame("Frame", nil, f.pdots)
    d:SetSize(20, 20)
    d.icon = d:CreateTexture(nil, "ARTWORK")
    d.icon:SetPoint("CENTER")
    d.ring = d:CreateTexture(nil, "OVERLAY")
    d.ring:SetAllPoints()
    d.ring:SetTexture(RING)
    local ok, fs = pcall(d.CreateFontString, d, nil, "OVERLAY", "GameFontHighlightSmallOutline")
    if not ok or not fs then fs = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") end
    d.label = fs
    d.label:SetPoint("TOP", d, "BOTTOM", 0, 2)
    d:Hide()
    dots[i] = d
  end

  -- zoom: mouse wheel over the map, plus + / - buttons
  f.map:EnableMouseWheel(true)
  f.map:SetScript("OnMouseWheel", function(_, delta)
    SetZoom(zoom * (delta > 0 and 1.3 or 1 / 1.3))
  end)
  local function zbtn(text, x, fn)
    local b = CreateFrame("Button", nil, f.dots, "UIPanelButtonTemplate")
    b:SetSize(20, 18); b:SetText(text)
    b:SetPoint("BOTTOMRIGHT", f.map, "BOTTOMRIGHT", x, 3)
    b:SetScript("OnClick", fn)
    return b
  end
  zbtn("+", -3, function() SetZoom(zoom * 1.5) end)
  zbtn("-", -25, function() SetZoom(zoom / 1.5) end)
  f.viewBtn = zbtn("Zone", -47, function() ns.Tracker.ToggleView() end)
  f.viewBtn:SetWidth(44)
  f.pinBtn = zbtn("Pins", -93, function() ns.Tracker.TogglePins() end)
  f.pinBtn:SetWidth(36)

  -- maximize toggle
  local maxb = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  maxb:SetSize(34, 16); maxb:SetText("Max")
  maxb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -26, -6)
  maxb:SetScript("OnClick", function() ns.Tracker.ToggleMax() end)

  for i = 1, MAXROWS do
    local r = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r:SetPoint("TOPLEFT", f.map, "BOTTOMLEFT", 0, -6 - (i - 1) * 16)
    r:SetPoint("TOPRIGHT", f.map, "BOTTOMRIGHT", 0, -6 - (i - 1) * 16)
    r:SetJustifyH("LEFT")
    rows[i] = r
  end

  -- resize grip (bottom-right corner)
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    DB.trackSize = { f:GetWidth(), f:GetHeight() }
  end)

  f:Hide()
  return f
end

local function Hex(c)
  return ("%02x%02x%02x"):format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

local function Refresh()
  if not frame or not frame:IsShown() then return end
  local w, h = frame.map:GetWidth(), frame.map:GetHeight()
  if w and h and w > 20 and h > 20 and (w ~= viewW or h ~= viewH) then
    viewW, viewH = w, h
    Relayout()
  end
  local myMap, mx, my = MyPos()
  local hasPos = mx ~= nil
  local disp = myMap
  if DB.trackView == "continent" and hasPos then disp = ContinentOf(myMap) or myMap end
  UpdateArt(disp)
  local now = GetTime()
  local me = UnitName("player")

  local list = {}
  if myMap then list[#list + 1] = { name = me, map = myMap, x = mx, y = my, t = now, self = true } end
  for name, p in pairs(peers) do
    list[#list + 1] = { name = name, map = p.map, x = p.x, y = p.y, t = p.t }
  end
  table.sort(list, function(a, b)
    if a.self ~= b.self then return a.self end
    return a.name < b.name
  end)

  frame.title:SetText(DB.track and "Realm |cff00ff00● sharing|r" or "Realm |cffff4040● not sharing|r")
  frame.viewBtn:SetText(DB.trackView == "continent" and "Cont" or "Zone")
  frame.pinBtn:SetText(DB.trackPins ~= false and "Pins" or "|cff888888Pins|r")
  local label = disp and MapName(disp) or "No map data here"
  if myMap and not hasPos then label = label .. " (instance)" end
  frame.zone:SetText(label)

  -- camera: keep me centered, clamped to the map edges
  local aw, ah = ArtSize()
  local sx, sy = ToDisplay(myMap, mx, my, disp)
  local cx, cy = (sx or .5) * aw, (sy or .5) * ah
  local function clamp(off, size, view)
    if size <= view then return (view - size) / 2 end
    return math.max(view - size, math.min(0, off))
  end
  local ox, oy = clamp(viewW / 2 - cx, aw, viewW), clamp(viewH / 2 - cy, ah, viewH)
  frame.art:ClearAllPoints()
  frame.art:SetPoint("TOPLEFT", frame.map, "TOPLEFT", ox, -oy)

  local n = math.max(1, math.min(#list, MAXROWS))
  if n ~= rowsN then rowsN = n; frame.AnchorMap(n) end

  local di = 0
  for i = 1, MAXROWS do rows[i]:SetText("") end
  for i, p in ipairs(list) do
    p.class = p.self and select(2, UnitClass("player")) or PeerClass(p.name, p)
    local c = ClassColor(p.class, COLORS[(i - 1) % #COLORS + 1])
    local stale = (now - p.t) > STALE
    if i <= MAXROWS then
      local text
      if p.self then
        text = ("|cff%s%s|r  %s"):format(Hex(c), p.name, MapName(p.map))
        if not p.x then text = text .. "  |cff888888(no position inside instances)|r" end
      elseif stale then
        text = ("|cff808080%s  (no signal)|r"):format(p.name)
      elseif not p.x then
        text = ("|cff%s%s|r  in %s  |cff888888(instance)|r"):format(Hex(c), p.name, MapName(p.map))
      else
        local yd = (mx and Yards(myMap, mx, my, p.map, p.x, p.y)) or nil
        local where = (p.map == myMap) and "" or (" - " .. MapName(p.map))
        text = ("|cff%s%s|r  %s%s"):format(Hex(c), p.name,
          yd and (math.floor(yd) .. " yd") or "?", where)
      end
      rows[i]:SetText(text)
    end
    local dx, dy
    if not stale and p.x then dx, dy = ToDisplay(p.map, p.x, p.y, disp) end
    if dx and di < MAXDOTS then
      di = di + 1
      local d = dots[di]
      local size = p.self and 28 or 22
      d:SetSize(size, size)
      d.icon:SetSize(size * .8, size * .8)
      local tc = ClassCoords(p.class)
      if tc then
        d.icon:SetTexture(CLASS_ART)
        d.icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        d.icon:SetVertexColor(1, 1, 1)
      else
        d.icon:SetTexture(DISC)
        d.icon:SetTexCoord(0, 1, 0, 1)
        d.icon:SetVertexColor(c[1], c[2], c[3])
      end
      d.ring:SetVertexColor(c[1], c[2], c[3])
      d.label:SetText(p.name)
      d.label:SetTextColor(c[1], c[2], c[3])
      d.label:SetShown(DB.trackNames ~= false)
      d:SetFrameLevel(frame.pdots:GetFrameLevel() + (p.self and 30 or di))
      d:ClearAllPoints()
      d:SetPoint("CENTER", frame.art, "TOPLEFT", dx * aw, -dy * ah)
      d:Show()
    end
  end
  for i = di + 1, MAXDOTS do dots[i]:Hide() end

  -- dungeon entrance pins
  local ents = (DB.trackPins ~= false and disp and hasPos) and Entrances(disp) or {}
  for i = 1, MAXPINS do
    local e = ents[i]
    local pin = pins[i]
    if e and e.position then
      if not pin then
        pin = CreateFrame("Button", nil, frame.dots)
        pin:SetSize(10, 10)
        pin.tex = pin:CreateTexture(nil, "ARTWORK")
        pin.tex:SetAllPoints()
        pin.tex:SetColorTexture(.75, .45, 1, 1)
        pin.info = false
        pin:SetScript("OnEnter", function(self)
          if not (self.info and GameTooltip) then return end
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:AddLine(self.info.name or "Dungeon entrance")
          if self.info.description then GameTooltip:AddLine(self.info.description, .8, .8, .8, true) end
          GameTooltip:Show()
        end)
        pin:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        pins[i] = pin
      end
      local px, py = e.position:GetXY()
      pin.info = e
      pin:ClearAllPoints()
      pin:SetPoint("CENTER", frame.art, "TOPLEFT", px * aw, -py * ah)
      pin:Show()
    elseif pin then
      pin:Hide(); pin.info = false
    end
  end
end

-- ---------- public API ----------
ns.Tracker = {}
function ns.Tracker.Peers() return peers end
function ns.Tracker.Show(show)
  if show == nil then show = not frame:IsShown() end
  DB.trackShown = show
  frame:SetShown(show)
  Refresh()
end

function ns.Tracker.SetTrack(on)
  if on == nil then on = not DB.track end
  DB.track = on
  if on then
    ns.Print("Sharing your location with your group. |cff00ff00ON|r")
    Broadcast()
  else
    SendOff()
    ns.Print("Location sharing |cffff4040OFF|r")
  end
  Refresh()
end

local maximized = false
function ns.Tracker.ToggleMax()
  maximized = not maximized
  frame:SetScale(maximized and 2.2 or (DB.trackScale or 1))
end

function ns.Tracker.ToggleView()
  DB.trackView = (DB.trackView == "continent") and "zone" or "continent"
  zoom = 1; DB.trackZoom = 1
  Relayout()
  ns.Print("Tracker view: " .. (DB.trackView == "continent" and "continent" or "zone"))
end

function ns.Tracker.ToggleNames()
  DB.trackNames = (DB.trackNames == false)
  ns.Print("Names on the map: " .. (DB.trackNames and "on" or "off"))
end

function ns.Tracker.TogglePins()
  DB.trackPins = (DB.trackPins == false)
  ns.Print("Dungeon entrance pins: " .. (DB.trackPins and "on" or "off"))
end

function ns.Tracker.Where()
  local map, x, y = MyPos()
  if map and x then
    ns.Print(("You are at %.1f, %.1f in %s (map %d). View: %s. Zoom %.1fx. Art: %s"):format(x * 100, y * 100, MapName(map), map, DB.trackView or "zone", zoom, layer and "loaded" or "none"))
  elseif map then
    ns.Print(("In %s (map %d). The game hides positions inside instances, so there is no dot here."):format(MapName(map), map))
  else
    ns.Print("No map data available here.")
  end
end

function ns.Tracker.SetScale(s)
  s = tonumber(s)
  if not s then ns.Print("Usage: /realm scale 0.7 - 3") return end
  s = math.max(0.7, math.min(3, s))
  DB.trackScale = s
  frame:SetScale(s)
  ns.Print("Tracker scale: " .. s)
end

-- ---------- events ----------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:SetScript("OnEvent", function(_, event, a1, a2, _, sender)
  if event == "PLAYER_LOGIN" then
    DB = ns.DB
    DB.track = DB.track or false
    DB.trackView = DB.trackView or "zone"
    if DB.trackPins == nil then DB.trackPins = true end
    RegisterPrefix()
    frame = Build()
    if DB.trackPos then
      frame:ClearAllPoints()
      frame:SetPoint(DB.trackPos[1], UIParent, DB.trackPos[2], DB.trackPos[3], DB.trackPos[4])
    end
    frame:SetScale(DB.trackScale or 1)
    zoom = math.max(1, math.min(8, DB.trackZoom or 1))
    if DB.trackShown then frame:Show() end

    local acc, bcast = 0, 0
    driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, dt)
      acc, bcast = acc + dt, bcast + dt
      if bcast >= 1 then
        bcast = 0
        if DB.track then Broadcast() end
      end
      if acc < 0.2 then return end
      acc = 0
      Refresh()
    end)
  elseif event == "CHAT_MSG_ADDON" then
    if a1 ~= PREFIX or not sender then return end
    local name = Ambiguate and Ambiguate(sender, "short") or sender
    if name == UnitName("player") then return end
    if a2 == "OFF" then peers[name] = nil return end
    local map, x, y, cls = a2:match("^P:(%d+):([%d%.]+):([%d%.]+):?(%u*)$")
    if map then
      peers[name] = { map = tonumber(map), x = tonumber(x), y = tonumber(y), class = cls, t = GetTime() }
    else
      local inst, icls = a2:match("^I:(%d+):?(%u*)$")
      if inst then peers[name] = { map = tonumber(inst), class = icls, t = GetTime() } end
    end
  elseif event == "GROUP_ROSTER_UPDATE" then
    -- drop people who left the group
    for name in pairs(peers) do
      if not (UnitInParty(name) or UnitInRaid(name)) then peers[name] = nil end
    end
    if DB and DB.track then Broadcast() end
  end
end)
