-- Realm: opt-in party location tracker (addon messages + pop-out window).
local ADDON, ns = ...
local PREFIX = "REALM"
local peers = {}            -- short name -> { map, x, y, t }
local DB
local frame, driver
local rows, dots, pins = {}, {}, {}
local nodePins, MAXNODES = {}, 200
local MAXPINS = 40
local MAXROWS, MAXDOTS = 10, 40
local STALE = 8
local COLORS = {
  { 1, .5, 0 }, { .2, .8, 1 }, { .4, 1, .4 }, { 1, .3, .6 }, { 1, .9, .2 },
  { .7, .5, 1 }, { .3, 1, .9 }, { 1, .6, .6 }, { .8, .8, .8 }, { .6, .8, .2 },
}

local RING = "Interface\\AddOns\\Realm\\ring"
local DISC = "Interface\\AddOns\\Realm\\disc"
local ARROW = "Interface\\AddOns\\Realm\\Path\\icons\\arrow"
local TEXDIR = "Interface\\AddOns\\Realm\\Path\\icons\\"
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

-- ---------- sharing my compass goal (what I am heading for, and how) ----------
local goals = {}                 -- short name -> { kind, map, x, y, pic, label, t } as announced by that player
local lastGoal, lastGoalAt = nil, 0

local function GoalMessage()
  local P = ns.Path
  if not (DB and DB.trackShareGoal ~= false and P and P.ShareTarget) then return "G:-" end
  local ok, kind, map, x, y, pic, label = pcall(P.ShareTarget)
  if not ok or not kind then return "G:-" end
  kind = (tostring(kind):gsub("%W", ""))
  label = (tostring(label or ""):gsub("[:|%c]", " ")):sub(1, 40)
  return ("G:%s:%d:%.4f:%.4f:%s:%s"):format(kind, map or 0, x or 0, y or 0, pic or "-", label)
end

-- sent when the goal changes, and again every few seconds so late joiners and stale entries catch up
local function SendGoal(force)
  local ch = GroupChannel()
  if not ch then return end
  local msg, now = GoalMessage(), GetTime()
  local beat = (msg == "G:-") and 20 or 4
  if not force and msg == lastGoal and now - lastGoalAt < beat then return end
  lastGoal, lastGoalAt = msg, now
  pcall(Send, PREFIX, msg, ch)
end

local function GoalOf(name)
  local g = goals[name]
  if g and (GetTime() - g.t) <= 12 then return g end
end

local function GoalSuffix(kind, pic, label)
  local P = ns.Path
  local s = P and P.GoalText and P.GoalText(kind, pic, label)
  return s and ("  |cffb8c4d0> " .. s .. "|r") or ""
end

-- ---------- footprints on the map: the compass trail, drawn from a dot to its goal ----------
local FOOT_R = TEXDIR .. "step.tga"
local FOOT_L = TEXDIR .. "stepL.tga"
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local feet, trails = {}, {}      -- trails: { ax, ay, bx, by (pixels on the art), c = colour, max = most prints }
local FOOTS, STEP = 90, 13
local march, cycle = 0, 0

local function Foot(i)
  local t = feet[i]
  if not t then
    t = frame.dots:CreateTexture(nil, "ARTWORK")
    t:SetSize(11, 11)
    t.tex = false
    feet[i] = t
  end
  return t
end

local function DrawTrails(dt)
  if not (frame and frame:IsShown()) then return end
  march = march + (dt or 0) * 9
  while march >= STEP do march = march - STEP; cycle = cycle + 1 end
  local n = 0
  for _, tr in ipairs(trails) do
    local dx, dy = tr.bx - tr.ax, tr.by - tr.ay
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 24 then
      local ux, uy = dx / len, dy / len
      local ang = atan2(ux, -uy)                       -- 0 = up the map, clockwise
      local k, d = 0, 12 + march
      while d <= len - 10 and k < tr.max and n < FOOTS do
        k, n = k + 1, n + 1
        local t = Foot(n)
        local right = (k + cycle) % 2 == 0
        local side = right and 3 or -3
        t:ClearAllPoints()
        t:SetPoint("CENTER", frame.art, "TOPLEFT", tr.ax + ux * d - uy * side, -(tr.ay + uy * d + ux * side))
        if t.SetRotation then t:SetRotation(-ang) end   -- toes point at the goal
        local want = right and FOOT_R or FOOT_L
        if t.tex ~= want then t:SetTexture(want); t.tex = want end
        t:SetVertexColor(tr.c[1], tr.c[2], tr.c[3], .95)
        t:Show()
        d = d + STEP
      end
    end
  end
  for i = n + 1, #feet do feet[i]:Hide() end
end


-- ---------- zone map art + zoom ----------
local viewW, viewH = 204, 204      -- viewport size (follows the window)
local rowsN = 0
local zoom = 1
local artMap, layer, artID = nil, nil, nil
local tiles, ovTiles = {}, {}

-- Fully discovered map: MapData.lua holds every overlay of every map art, so the fog of unexplored areas is replaced.
local ovCache = {}
local OVT = 256   -- overlay pieces are always 256 pixels, whatever the base layer's tile size is
local function Overlays(id)
  if not id then return end
  local c = ovCache[id]
  if c ~= nil then return c or nil end
  local raw = ns.MapOverlays and ns.MapOverlays[id]
  if not raw then ovCache[id] = false return end
  local list = {}
  for chunk in raw:gmatch("[^|]+") do
    local head, ids = chunk:match("^([^:]+):(.+)$")
    local w, h, ox, oy = (head or ""):match("^(%d+),(%d+),(-?%d+),(-?%d+)$")
    if w then
      local files = {}
      for fid in ids:gmatch("%d+") do files[#files + 1] = tonumber(fid) end
      list[#list + 1] = { w = tonumber(w), h = tonumber(h), ox = tonumber(ox), oy = tonumber(oy), files = files }
    end
  end
  ovCache[id] = list
  return list
end

-- size of one piece (pixels) and of its texture file (next power of two, at least 16) for the last row/column
local function Piece(total, tile, idx, count)
  if idx < count then return tile, tile end
  local px = total % tile
  if px == 0 then px = tile end
  local f = 16
  while f < px do f = f * 2 end
  return px, f
end

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

  -- discovered overlays on top of the base art
  for _, t in ipairs(ovTiles) do t:Hide() end
  if not (DB and DB.trackDiscovered ~= false) then return end
  local list = Overlays(artID)
  if not list then
    if artID and DB and DB.noOverlayArt ~= artID then
      DB.noOverlayArt = artID
      ns.Print("No discovered-map data for map " .. tostring(artMap) .. " (art " .. tostring(artID) .. "); showing the base map only.")
    end
    return
  end
  local n = 0
  for _, o in ipairs(list) do
    local nw, nh = math.ceil(o.w / OVT), math.ceil(o.h / OVT)
    for j = 1, nh do
      local ph, fh = Piece(o.h, OVT, j, nh)
      for k = 1, nw do
        local fid = o.files[(j - 1) * nw + k]
        if fid then
          local pw, fw = Piece(o.w, OVT, k, nw)
          n = n + 1
          local t = ovTiles[n]
          if not t then
            t = frame.art:CreateTexture(nil, "ARTWORK")
            ovTiles[n] = t
          end
          t:ClearAllPoints()
          t:SetPoint("TOPLEFT", frame.art, "TOPLEFT", (o.ox + OVT * (k - 1)) * s, -(o.oy + OVT * (j - 1)) * s)
          t:SetSize(pw * s, ph * s)
          t:SetTexCoord(0, pw / fw, 0, ph / fh)
          t:SetTexture(fid)
          t:Show()
        end
      end
    end
  end
end

local function UpdateArt(map)
  if not frame or map == artMap then return end
  artMap, layer, artID = map, nil, nil
  if map and C_Map and C_Map.GetMapArtID then
    local ok, id = pcall(C_Map.GetMapArtID, map)
    if ok then artID = id end
  end
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
  f:SetFrameStrata("HIGH"); f:SetToplevel(true)
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
  local tp = CreateFrame("Button", nil, f.pdots)         -- compass target marker
  tp:SetSize(22, 22)
  tp:SetFrameLevel(f.pdots:GetFrameLevel() + 20)
  tp.tex = tp:CreateTexture(nil, "ARTWORK"); tp.tex:SetAllPoints()
  tp.txt = tp:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); tp.txt:SetPoint("CENTER")
  tp.info = false
  tp:SetScript("OnEnter", function(self)
    if not (self.info and GameTooltip) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.info.title)
    for _, l in ipairs(self.info.lines) do if l ~= "" then GameTooltip:AddLine(l, .8, .8, .8) end end
    GameTooltip:Show()
  end)
  tp:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  tp:Hide()
  f.tgt = tp
  for i = 1, MAXDOTS do
    local d = CreateFrame("Frame", nil, f.pdots)
    d:SetSize(20, 20)
    d.icon = d:CreateTexture(nil, "ARTWORK")
    d.icon:SetPoint("CENTER")
    d.ring = d:CreateTexture(nil, "OVERLAY")
    d.ring:SetAllPoints()
    d.ring:SetTexture(RING)
    d.arrow = d:CreateTexture(nil, "OVERLAY")          -- facing pointer, own dot only
    d.arrow:SetTexture(ARROW)
    d.arrow:SetSize(12, 12)
    d.arrow:Hide()
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
  local bx = -3                      -- bottom row, built right to left
  local function zbtn(text, w, fn)
    local b = CreateFrame("Button", nil, f.dots, "UIPanelButtonTemplate")
    b:SetSize(w, 18); b:SetText(text)
    b:SetPoint("BOTTOMRIGHT", f.map, "BOTTOMRIGHT", bx, 3)
    bx = bx - w - 2
    b:SetScript("OnClick", fn)
    return b
  end
  zbtn("+", 20, function() SetZoom(zoom * 1.5) end)
  zbtn("-", 20, function() SetZoom(zoom / 1.5) end)
  f.viewBtn = zbtn("Zone", 40, function() ns.Tracker.ToggleView() end)
  f.pinBtn = zbtn("POI", 32, function() ns.Tracker.TogglePins() end)
  f.lblBtn = zbtn("Labels", 44, function() ns.Tracker.ToggleLabels() end)
  f.nodeBtn = zbtn("Nodes", 40, function()
    if ns.Gather then ns.Gather.SetAll(not ns.Gather.AnyOn()) end
  end)

  -- one toggle per node type (herbs, ore, fishing, chests), along the top edge of the map
  f.kindBtns = {}
  if ns.Gather then
    local x = -3
    for _, kind in ipairs(ns.Gather.Order()) do
      local b = CreateFrame("Button", nil, f.dots, "UIPanelButtonTemplate")
      b:SetSize(44, 18)
      b:SetPoint("TOPRIGHT", f.map, "TOPRIGHT", x, -3)
      b:SetScript("OnClick", function() ns.Gather.Toggle(kind) end)
      b.kind = kind
      f.kindBtns[#f.kindBtns + 1] = b
      x = x - 46
    end
  end

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
    if r.SetWordWrap then r:SetWordWrap(false) end      -- a long goal must not spill onto the next row
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

-- pin colours: dungeons by fit for your group's lowest level, farming spots gold
local FITCOL = { ok = { .4, 1, .4 }, low = { 1, .8, .2 }, easy = { .6, .6, .6 }, locked = { 1, .35, .35 }, farm = { 1, .82, .2 } }
local farmCache

-- small markers for where each party member is heading
local pmarks, MAXPM = {}, 8
local function PeerMark(i)
  local m = pmarks[i]
  if m then return m end
  m = CreateFrame("Button", nil, frame.pdots)
  m:SetSize(18, 18)
  m:SetFrameLevel(frame.pdots:GetFrameLevel() + 15)
  m.ring = m:CreateTexture(nil, "BACKGROUND"); m.ring:SetAllPoints(); m.ring:SetTexture(RING)
  m.tex = m:CreateTexture(nil, "ARTWORK"); m.tex:SetSize(12, 12); m.tex:SetPoint("CENTER")
  m.txt = m:CreateFontString(nil, "OVERLAY", "GameFontNormal"); m.txt:SetPoint("CENTER")
  m.info = false
  m:SetScript("OnEnter", function(self)
    if not (self.info and GameTooltip) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.info.title)
    for _, l in ipairs(self.info.lines) do if l ~= "" then GameTooltip:AddLine(l, .8, .8, .8, true) end end
    GameTooltip:Show()
  end)
  m:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  pmarks[i] = m
  return m
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
  trails = {}                    -- rebuilt each refresh; DrawTrails animates them every frame
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
  frame.pinBtn:SetText(DB.trackPins ~= false and "POI" or "|cff888888POI|r")
  frame.lblBtn:SetText(DB.trackLabels ~= false and "Labels" or "|cff888888Labels|r")
  frame.nodeBtn:SetText((ns.Gather and ns.Gather.AnyOn()) and "Nodes" or "|cff888888Nodes|r")
  for _, b in ipairs(frame.kindBtns or {}) do
    local c = ns.Gather.Color(b.kind)
    local name = ns.Gather.Short(b.kind)
    b:SetText(ns.Gather.Enabled(b.kind) and ("|cff" .. Hex(c) .. name .. "|r") or ("|cff666666" .. name .. "|r"))
  end
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
      if p.self then
        local okg, gk, _, _, _, gpic, glabel = pcall(ns.Path and ns.Path.ShareTarget or function() end)
        if okg and gk then text = text .. GoalSuffix(gk, gpic, glabel) end
      elseif not stale then
        local g = GoalOf(p.name)
        if g then text = text .. GoalSuffix(g.kind, g.pic, g.label) end
      end
      rows[i]:SetText(text)
    end
    local dx, dy
    if not stale and p.x then dx, dy = ToDisplay(p.map, p.x, p.y, disp) end
    if dx and di < MAXDOTS then
      di = di + 1
      local d = dots[di]
      local size = p.self and 22 or 18
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
      -- facing pointer: my own dot only, sitting on the rim in the direction I face
      if p.self and GetPlayerFacing then
        local okf, face = pcall(GetPlayerFacing)
        if okf and face and not (issecretvalue and issecretvalue(face)) then
          local r = size * .5 + 4
          d.arrow:ClearAllPoints()
          d.arrow:SetPoint("CENTER", d, "CENTER", -math.sin(face) * r, math.cos(face) * r)
          d.arrow:SetRotation(face)
          d.arrow:SetVertexColor(1, 1, 1)
          d.arrow:Show()
        else
          d.arrow:Hide()
        end
      else
        d.arrow:Hide()
      end
      d:SetFrameLevel(frame.pdots:GetFrameLevel() + (p.self and 30 or di))
      d:ClearAllPoints()
      d:SetPoint("CENTER", frame.art, "TOPLEFT", dx * aw, -dy * ah)
      d:Show()
    end
  end
  for i = di + 1, MAXDOTS do dots[i]:Hide() end

  -- compass target (quest hand-in, travel leg...) drawn with the same picture the compass uses
  local tp = frame.tgt
  local T = ns.Path and ns.Path.Target and ns.Path.Target()
  local tx, ty
  if T and T.x and T.map and disp and hasPos and DB.trackTarget ~= false then
    tx, ty = ToDisplay(T.map, T.x, T.y, disp)
  end
  if tx then
    local col, glyph, pic = ns.Path.TargetLook()
    col = col or { 1, .82, .2 }
    if pic then
      tp.tex:SetTexture(TEXDIR .. pic); tp.tex:SetVertexColor(col[1], col[2], col[3]); tp.tex:Show(); tp.txt:Hide()
    else
      tp.tex:Hide(); tp.txt:SetText(glyph or "!"); tp.txt:SetTextColor(col[1], col[2], col[3]); tp.txt:Show()
    end
    tp.info = { title = T.label or "Target", lines = { T.dist and (math.floor(T.dist) .. " yd") or "" } }
    tp:ClearAllPoints()
    tp:SetPoint("CENTER", frame.art, "TOPLEFT", tx * aw, -ty * ah)
    tp:Show()
    if sx then trails[#trails + 1] = { ax = sx * aw, ay = sy * ah, bx = tx * aw, by = ty * ah, c = col, max = 30 } end
  else
    tp:Hide()
  end

  -- where the party are heading (their shared compass goal): a marker on the map and footprints from their dot
  local pm = 0
  if DB.trackTarget ~= false and disp and hasPos and ns.Path and ns.Path.KindLook then
    for i, p in ipairs(list) do
      local g = (not p.self) and p.x and (now - p.t) <= STALE and GoalOf(p.name)
      if g and g.map and g.map ~= 0 and pm < MAXPM then
        local gx, gy = ToDisplay(g.map, g.x, g.y, disp)
        if gx then
          pm = pm + 1
          local m = PeerMark(pm)
          local kc, glyph, pic = ns.Path.KindLook(g.kind, g.pic)
          kc = kc or { 1, .82, .2 }
          local pc = ClassColor(p.class, COLORS[(i - 1) % #COLORS + 1])
          m.ring:SetVertexColor(pc[1], pc[2], pc[3])
          if pic then
            m.tex:SetTexture(TEXDIR .. pic); m.tex:SetVertexColor(kc[1], kc[2], kc[3]); m.tex:Show(); m.txt:Hide()
          else
            m.tex:Hide(); m.txt:SetText(glyph or "!"); m.txt:SetTextColor(kc[1], kc[2], kc[3]); m.txt:Show()
          end
          m.info = { title = p.name .. " is heading here",
                     lines = { ns.Path.GoalText and ns.Path.GoalText(g.kind, g.pic, g.label) or "" } }
          m:ClearAllPoints()
          m:SetPoint("CENTER", frame.art, "TOPLEFT", gx * aw, -gy * ah)
          m:Show()
          local px, py = ToDisplay(p.map, p.x, p.y, disp)
          if px then trails[#trails + 1] = { ax = px * aw, ay = py * ah, bx = gx * aw, by = gy * ah, c = pc, max = 12 } end
        end
      end
    end
  end
  for i = pm + 1, #pmarks do pmarks[i]:Hide(); pmarks[i].info = false end

  -- points of interest: dungeon entrances (coloured by how well they fit you and your group) and farming spots ($)
  local poi = {}
  local function add(e) if #poi < MAXPINS then poi[#poi + 1] = e end end
  if DB.trackPins ~= false and disp and hasPos then
    local cont = DB.trackView == "continent"
    local function place(map, x, y)
      if map == disp then return x, y end
      if cont then return ToDisplay(map, x, y, disp) end      -- zone view only shows this zone's own points
    end
    local Dg = ns.Path and ns.Path.Dungeons
    if Dg and ns.Dungeons then
      local _, lowLvl = Dg.Group()
      for _, d in ipairs(ns.Dungeons) do
        local px, py = place(d[2], d[3], d[4])
        if px then
          local fit = Dg.Fit(d, lowLvl)
          add({ kind = "dungeon", x = px, y = py, c = FITCOL[fit], title = d[1],
                label = ("%s %d-%d"):format(d[1], d[5], d[6]),
                lines = { ("Levels %d-%d, %d players"):format(d[5], d[6], d[8]),
                          (Dg.FitText[fit] or "") .. " (lowest level in your group: " .. lowLvl .. ")" } })
        end
      end
    end
    if #poi == 0 then          -- no table entry for this map: use the client's own entrance list when it has one
      for _, e in ipairs(Entrances(disp)) do
        if e.position then
          local px, py = e.position:GetXY()
          add({ kind = "dungeon", x = px, y = py, c = FITCOL.ok, title = e.name or "Dungeon entrance", label = e.name,
                lines = { e.description } })
        end
      end
    end
    if ns.Path and ns.Path.FarmSpots then
      local now2, lvl = GetTime(), UnitLevel("player")
      if not farmCache or now2 - farmCache.t > 2 or farmCache.lvl ~= lvl then
        local ok, r, fmap = pcall(ns.Path.FarmSpots, 6)
        farmCache = { t = now2, lvl = lvl, r = ok and r or {}, map = ok and fmap or nil }
      end
      if farmCache.map then
        for _, e in ipairs(farmCache.r) do
          local s = e.s
          local px, py = place(farmCache.map, s[1], s[2])
          if px then
            add({ kind = "farm", x = px, y = py, c = FITCOL.farm, title = s[7],
                  label = ("%s %d-%d"):format(s[7], s[4], s[5]),
                  lines = { ("Farming spot, level %d-%d"):format(s[4], s[5]),
                            ("about %d mobs%s"):format(s[3], s[6] >= .5 and ", mostly humanoids (cloth and coin)" or "") } })
          end
        end
      end
    end
  end
  for i = 1, MAXPINS do
    local e = poi[i]
    local pin = pins[i]
    if e then
      if not pin then
        pin = CreateFrame("Button", nil, frame.dots)
        pin:SetSize(10, 10)
        pin.tex = pin:CreateTexture(nil, "ARTWORK")
        pin.tex:SetAllPoints()
        pin.s = pin:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        pin.s:SetPoint("CENTER"); pin.s:SetText("$")
        local okf, fs = pcall(pin.CreateFontString, pin, nil, "OVERLAY", "GameFontHighlightSmallOutline")
        if not okf or not fs then fs = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") end
        pin.lbl = fs
        pin.lbl:SetPoint("TOP", pin, "BOTTOM", 0, 1)
        pin.info = false
        pin:SetScript("OnEnter", function(self)
          if not (self.info and GameTooltip) then return end
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:AddLine(self.info.title or "Point of interest")
          for _, l in ipairs(self.info.lines or {}) do GameTooltip:AddLine(l, .8, .8, .8, true) end
          GameTooltip:Show()
        end)
        pin:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        pins[i] = pin
      end
      local c = e.c or FITCOL.ok
      if e.kind == "farm" then
        pin.tex:Hide(); pin.s:SetTextColor(c[1], c[2], c[3]); pin.s:Show()
      else
        pin.tex:Show(); pin.tex:SetColorTexture(c[1], c[2], c[3], 1); pin.s:Hide()
      end
      pin.lbl:SetText(e.label or "")
      pin.lbl:SetTextColor(c[1], c[2], c[3])
      pin.lbl:SetShown(DB.trackLabels ~= false)
      pin.info = e
      pin:ClearAllPoints()
      pin:SetPoint("CENTER", frame.art, "TOPLEFT", e.x * aw, -e.y * ah)
      pin:Show()
    elseif pin then
      pin:Hide(); pin.info = false
    end
  end

  -- gathering node pins (learned from your own gathering; per-kind toggles)
  local nodes = (disp and hasPos and ns.Gather) and ns.Gather.Visible(disp) or {}
  for i = 1, MAXNODES do
    local nd = nodes[i]
    local np = nodePins[i]
    if nd then
      if not np then
        np = CreateFrame("Button", nil, frame.dots)
        np:SetSize(8, 8)
        np.tex = np:CreateTexture(nil, "ARTWORK")
        np.tex:SetAllPoints()
        np.info = false
        np:SetScript("OnEnter", function(self)
          if not (self.info and GameTooltip) then return end
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:AddLine(self.info.n or "Node")
          GameTooltip:Show()
        end)
        np:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        nodePins[i] = np
      end
      local c = ns.Gather.Color(nd.k)
      np.tex:SetColorTexture(c[1], c[2], c[3], 1)
      np.info = nd
      np:ClearAllPoints()
      np:SetPoint("CENTER", frame.art, "TOPLEFT", nd.x * aw, -nd.y * ah)
      np:Show()
    elseif np then
      np:Hide(); np.info = false
    end
  end
end

-- ---------- public API ----------
ns.Tracker = {}
function ns.Tracker.Peers() return peers end
function ns.Tracker.Goals() return goals end
function ns.Tracker.Feet() local n = 0; for _, t in ipairs(feet) do if t.shown then n = n + 1 end end return n end

-- ---------- sharing gathering nodes ----------
-- N:kind:map:x:y:name  sent once when I find a NEW node; the receiver's Gather.Record ignores a spot it already has
function ns.Tracker.ShareNode(kind, name, map, x, y)
  if not (DB and DB.track and DB.trackShareNodes ~= false) then return end
  local ch = GroupChannel()
  if not ch then return end
  name = (tostring(name or "?"):gsub("[:|%c]", " ")):sub(1, 40)
  pcall(Send, PREFIX, ("N:%s:%d:%.4f:%.4f:%s"):format(kind, map, x, y, name), ch)
end

function ns.Tracker.ToggleShareNodes(on)
  if on == nil then on = (DB.trackShareNodes == false) end
  DB.trackShareNodes = on
  ns.Print("Sharing and receiving gathering nodes with the party: " .. (on and "|cff00ff00ON|r" or "|cffff4040OFF|r"))
end

-- /realm share: whether my compass goal (quest giver, trainer, tram...) is told to the party along with my position
function ns.Tracker.ToggleShareGoal(on)
  if on == nil then on = (DB.trackShareGoal == false) end
  DB.trackShareGoal = on
  ns.Print("Sharing where your compass is heading with the party: " .. (on and "|cff00ff00ON|r" or "|cffff4040OFF|r"))
  if DB.track then SendGoal(true) end
end
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
    Broadcast(); SendGoal(true)
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

function ns.Tracker.ToggleDiscovered()
  DB.trackDiscovered = (DB.trackDiscovered == false)
  Relayout()
  ns.Print("Fully discovered map: " .. (DB.trackDiscovered and "on" or "off (shows only what you explored)"))
end

function ns.Tracker.ToggleNames()
  DB.trackNames = (DB.trackNames == false)
  ns.Print("Names on the map: " .. (DB.trackNames and "on" or "off"))
end

function ns.Tracker.TogglePins()
  DB.trackPins = (DB.trackPins == false)
  ns.Print("Points of interest (dungeon entrances and farming spots): " .. (DB.trackPins and "on" or "off"))
end

function ns.Tracker.ToggleLabels()
  DB.trackLabels = (DB.trackLabels == false)
  ns.Print("Labels on points of interest: " .. (DB.trackLabels and "on" or "off"))
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
    if DB.trackLabels == nil then DB.trackLabels = true end
    if DB.trackDiscovered == nil then DB.trackDiscovered = true end
    if DB.trackShareGoal == nil then DB.trackShareGoal = true end
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
        if DB.track then Broadcast(); SendGoal(false) end
      end
      DrawTrails(dt)
      if acc < 0.2 then return end
      acc = 0
      Refresh()
    end)
  elseif event == "CHAT_MSG_ADDON" then
    if a1 ~= PREFIX or not sender then return end
    local name = Ambiguate and Ambiguate(sender, "short") or sender
    if name == UnitName("player") then return end
    if a2 == "OFF" then peers[name] = nil; goals[name] = nil return end
    if a2:sub(1, 2) == "N:" then
      -- a party member found a node: keep it unless that spot is already recorded
      local kind, nmap, nx, ny, nname = a2:match("^N:(%a+):(%d+):([%d%.]+):([%d%.]+):?(.*)$")
      nmap, nx, ny = tonumber(nmap), tonumber(nx), tonumber(ny)
      if kind and nx and ny and nmap and nmap > 0 and nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1
         and DB.trackShareNodes ~= false and ns.Gather and ns.Gather.IsKind(kind) then
        ns.Gather.Record(kind, nname ~= "" and nname or "?", nmap, nx, ny, name)
      end
      return
    end
    if a2:sub(1, 2) == "G:" then
      if a2 == "G:-" then goals[name] = nil return end
      local kind, gmap, gx, gy, pic, label = a2:match("^G:(%w+):(%d+):([%d%.]+):([%d%.]+):([%w%-]+):?(.*)$")
      if kind then
        goals[name] = { kind = kind, map = tonumber(gmap), x = tonumber(gx), y = tonumber(gy),
                        pic = (pic ~= "-") and pic or nil, label = label, t = GetTime() }
      end
      return
    end
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
      if not (UnitInParty(name) or UnitInRaid(name)) then peers[name] = nil; goals[name] = nil end
    end
    if DB and DB.track then Broadcast(); SendGoal(true) end
  end
end)
