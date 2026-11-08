-- Inn: which inn to make your home in the zones the route takes you to, and when the hearthstone beats walking.
-- This is advice only. The game never lets an addon use the hearthstone or set your home for you.
-- Inn positions are zone-map fractions. Five come from Realm's own route data (Grosk, Gryshka, Renee, Kauth and the
-- Darkshire tavern); the rest are typed in from memory of the classic game: close, not surveyed. When you set your home
-- while standing next to an innkeeper, Realm remembers that exact spot for that inn and uses it from then on.
local ADDON, ns = ...
local Path = ns.Path
if not Path then return end

-- { bind, map, x, y, faction, innkeeper }
--   bind = the name the game shows as your home (GetBindLocation); faction = "A" / "H" when only one side can use it;
--   innkeeper is only filled in where the name came from the route data.
ns.Inns = {
  -- Alliance
  { "Goldshire",         1429, .433, .657, "A" },
  { "Kharanos",          1426, .546, .485, "A" },
  { "Thelsamar",         1432, .355, .484, "A" },
  { "Sentinel Hill",     1436, .526, .530, "A" },
  { "Lakeshire",         1433, .266, .438, "A" },
  { "Darkshire",         1431, .7378, .4449, "A", "Tavernkeep Smitts" },
  { "Menethil Harbor",   1437, .107, .588, "A" },
  { "Refuge Pointe",     1417, .458, .472, "A" },
  { "Southshore",        1424, .508, .573, "A" },
  { "Astranaar",         1440, .366, .497, "A" },
  { "Dolanaar",          1438, .556, .598, "A" },
  { "Auberdine",         1439, .371, .438, "A" },
  { "Stormwind City",    1453, .607, .752, "A" },
  { "Ironforge",         1455, .181, .517, "A" },
  { "Darnassus",         1457, .679, .160, "A" },
  -- Horde
  { "Razor Hill",        1411, .5151, .4164, "H", "Innkeeper Grosk" },
  { "Orgrimmar",         1454, .541, .6841, "H", "Innkeeper Gryshka" },
  { "Bloodhoof Village", 1412, .4593, .6416, "H", "Innkeeper Kauth" },
  { "The Crossroads",    1413, .515, .303, "H" },
  { "Sun Rock Retreat",  1442, .453, .599, "H" },
  { "Brill",             1420, .6171, .5205, "H", "Innkeeper Renee" },
  { "The Sepulcher",     1421, .439, .407, "H" },
  { "Tarren Mill",       1424, .616, .610, "H" },
  { "Hammerfall",        1417, .734, .347, "H" },
  { "Thunder Bluff",     1456, .451, .640, "H" },
  { "Undercity",         1458, .677, .386, "H" },
}

local I = {}
Path.Inn = I

local HEARTH_ID = 6948        -- Hearthstone
local CAST = 10               -- seconds to cast it
local MIN_SAVE = 120          -- only call it worth using when it saves at least two minutes
local DETOUR = 1.3            -- roads are not straight lines: walking is this much longer than the straight distance
local ZONE_EXTRA = 60         -- seconds for the last stretch inside a zone after a zone hop
local ASSUMED_COOLDOWN = 3600 -- until the game reports the real one (read from the cooldown while it runs)

local function Faction()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  return f == "Horde" and "H" or "A"
end

local function PlayerMap()
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
  if ok and type(m) == "number" then return m end
end

local function Zone(map)
  local n = Path.TravelNames and Path.TravelNames[map]
  if n then return n end
  local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
  return info and info.name or ("map " .. tostring(map))
end

local function Dur(s)
  s = math.floor((s or 0) + .5)
  if s >= 3600 then return ("%d h %02d min"):format(math.floor(s / 3600), math.floor((s % 3600) / 60)) end
  if s >= 60 then return ("%d min %02d s"):format(math.floor(s / 60), s % 60) end
  return s .. " s"
end
local function Yd(d)
  if d >= 1000 then return ("%.1fk yd"):format(d / 1000) end
  return math.floor(d + .5) .. " yd"
end
I.Dur = Dur

-- ---------------------------------------------------------------- where the inns are
local function XY(e)
  local S = Path.State and Path.State()
  local l = S and S.innLearn and S.innLearn[e[1]]
  if l then return l[1], l[2] end
  return e[3], e[4]
end
I.XY = XY

local function Gap(ma, xa, ya, mb, xb, yb)
  if not Path.WorldPoint then return nil end
  local c1, x1, y1 = Path.WorldPoint(ma, xa, ya)
  local c2, x2, y2 = Path.WorldPoint(mb, xb, yb)
  if not c1 or c1 ~= c2 then return nil end
  local dx, dy = x2 - x1, y2 - y1
  return math.sqrt(dx * dx + dy * dy)
end

-- running speed in yards per second (7 on foot, more when mounted)
function I.Speed()
  local sp = 7
  if GetUnitSpeed then
    local ok, _, run = pcall(GetUnitSpeed, "player")
    if ok and type(run) == "number" and run > sp then sp = run end
  end
  return sp
end

-- the inn the game says is your home: the table row (or nil) and the name the game gave
function I.Bound()
  local ok, name = pcall(GetBindLocation or function() end)
  if not ok or type(name) ~= "string" or name == "" then return nil, nil end
  local l = name:lower()
  for _, e in ipairs(ns.Inns) do
    if e[1]:lower() == l then return e, name end
  end
  return nil, name
end

-- ---------------------------------------------------------------- the hearthstone
function I.Hearth()
  local count = 0
  if C_Item and C_Item.GetItemCount then count = C_Item.GetItemCount(HEARTH_ID) or 0
  elseif GetItemCount then count = GetItemCount(HEARTH_ID) or 0 end
  local start, dur = 0, 0
  if C_Container and C_Container.GetItemCooldown then start, dur = C_Container.GetItemCooldown(HEARTH_ID)
  elseif GetItemCooldown then start, dur = GetItemCooldown(HEARTH_ID) end
  local remain = 0
  if type(start) == "number" and type(dur) == "number" and start > 0 and dur > 2 then
    remain = math.max(0, start + dur - (GetTime and GetTime() or 0))
  end
  return { has = count > 0, remain = remain, duration = (type(dur) == "number" and dur > 2) and dur or nil }
end

-- ---------------------------------------------------------------- time to a quest step
-- seconds to walk (or travel) from the player to a route step; second result is the straight distance in yards
function I.WalkSeconds(step)
  if not (step and step.m and step.p and #step.p >= 2) then return nil end
  local pmap = PlayerMap()
  if not pmap then return nil end
  if pmap == step.m then
    local best
    for i = 1, #step.p, 2 do
      local _, d = Path.Vector(step.m, step.p[i], step.p[i + 1])
      if d and (not best or d < best) then best = d end
    end
    if not best then return nil end
    return best * DETOUR / I.Speed(), best
  end
  local t = Path.TravelSeconds and Path.TravelSeconds(pmap, step.m)
  return t and (t + ZONE_EXTRA) or nil
end

-- seconds from a fixed point on a map (an inn) to a route step
local function SecondsFrom(map, x, y, step)
  if not (step and step.m and step.p and #step.p >= 2) then return nil end
  if map == step.m then
    local best
    for i = 1, #step.p, 2 do
      local d = Gap(map, x, y, step.m, step.p[i], step.p[i + 1])
      if d and (not best or d < best) then best = d end
    end
    if not best then return nil end
    return best * DETOUR / I.Speed(), best
  end
  local t = Path.TravelSeconds and Path.TravelSeconds(map, step.m)
  return t and (t + ZONE_EXTRA) or nil
end

-- Should you hearth for the current route step?
-- verdict: hearth (ready and worth it), soon (worth it once the cooldown ends), walk, unknown (home not on record), none (no stone), nostep
function I.Advise()
  local step, idx = nil, nil
  if Path.Current then step, idx = Path.Current() end
  local h = I.Hearth()
  local out = { step = step, idx = idx, hearth = h }
  out.bind, out.bindName = I.Bound()
  if not (step and step.m and step.p and #step.p >= 2) then out.verdict = "nostep" return out end
  if not h.has then out.verdict = "none" return out end
  local walk = I.WalkSeconds(step)
  out.walk = walk
  if not out.bind or not walk then out.verdict = "unknown" return out end
  local bx, by = XY(out.bind)
  local leg = SecondsFrom(out.bind[2], bx, by, step)
  if not leg then out.verdict = "unknown" return out end
  out.leg = leg
  out.viaHearth = CAST + leg
  out.save = walk - out.viaHearth
  out.waitTotal = h.remain + out.viaHearth
  if out.save < MIN_SAVE then out.verdict = "walk"
  elseif h.remain > 0 then out.verdict = (walk - out.waitTotal >= MIN_SAVE) and "soon" or "walk"
  else out.verdict = "hearth" end
  return out
end

-- ---------------------------------------------------------------- which inn to call home
-- For the zone the next quest step is in: the inn closest to the quests still ahead there, and whether moving your home to it pays off.
function I.HomeAdvice()
  local step = Path.Current and Path.Current()
  if not (step and step.m) then return nil end
  local zone, fac = step.m, Faction()
  local zs = {}
  local function add(s) if s and s.m == zone and s.p and #s.p >= 2 then zs[#zs + 1] = s end end
  add(step)
  if Path.Upcoming then
    for _, u in ipairs(Path.Upcoming(12)) do add(u[1]) end
  end
  local best, bestAvg
  for _, e in ipairs(ns.Inns) do
    if e[2] == zone and (not e[5] or e[5] == fac) then
      local x, y = XY(e)
      local sum, n = 0, 0
      for _, s in ipairs(zs) do
        local d = Gap(zone, x, y, zone, s.p[1], s.p[2])
        if d then sum = sum + d; n = n + 1 end
      end
      local avg = n > 0 and sum / n or nil
      if not best or (avg and (not bestAvg or avg < bestAvg)) then best, bestAvg = e, avg end
    end
  end
  if not best then return nil end
  local out = { map = zone, inn = best, n = #zs, avg = bestAvg }
  out.tInn = bestAvg and (bestAvg * DETOUR / I.Speed()) or nil
  out.bind, out.bindName = I.Bound()
  if PlayerMap() == zone then
    local x, y = XY(best)
    local _, d = Path.Vector(zone, x, y)
    out.distToInn = d
  end
  if out.bind == best then
    out.worth, out.reason = false, "home"
  elseif out.bind then
    local tb
    if out.bind[2] == zone then
      local bx, by = XY(out.bind)
      local sum, n = 0, 0
      for _, s in ipairs(zs) do
        local d = Gap(zone, bx, by, zone, s.p[1], s.p[2])
        if d then sum = sum + d; n = n + 1 end
      end
      tb = n > 0 and (sum / n * DETOUR / I.Speed()) or nil
    else
      local t = Path.TravelSeconds and Path.TravelSeconds(out.bind[2], zone)
      tb = t and (t + ZONE_EXTRA) or nil
    end
    out.tBind = tb
    out.worth = out.n >= 3 and (tb == nil or out.tInn == nil or tb - out.tInn >= 90)
    out.reason = out.worth and "closer" or "fine"
  else
    -- home is somewhere I have no record of, or was never set
    out.worth, out.reason = out.n >= 3, out.bindName and "unknown" or "unset"
  end
  return out
end

-- ---------------------------------------------------------------- wording
local function InnName(e)
  return e[6] and (e[6] .. " in " .. e[1]) or ("the innkeeper in " .. e[1])
end

-- Where you are standing right now: if this zone has an inn you can use, quests still ahead here, and your home is
-- somewhere else (or unset), offer the nearest inn. Runs from the same timer, so it also covers login.
function I.HereAdvice()
  local zone, fac = PlayerMap(), Faction()
  if not zone then return nil end
  local ahead = 0
  local cur = Path.Current and Path.Current()
  if cur and cur.m == zone then ahead = ahead + 1 end
  if Path.Upcoming then
    for _, u in ipairs(Path.Upcoming(12)) do
      if u[1] and u[1].m == zone then ahead = ahead + 1 end
    end
  end
  if ahead < 3 then return nil end
  local best, bd
  for _, e in ipairs(ns.Inns) do
    if e[2] == zone and (not e[5] or e[5] == fac) then
      local x, y = XY(e)
      local b, d = Path.Vector(zone, x, y)
      if b and (not bd or d < bd) then best, bd = e, d end
    end
  end
  if not best then return nil end
  local bind, bindName = I.Bound()
  if bind and bind[2] == zone then return nil end
  return { map = zone, inn = best, dist = bd, bind = bind, bindName = bindName, ahead = ahead }
end

function I.HereLine(a)
  local s
  if a.bindName then s = ("Your home is %s, not in this zone."):format(a.bind and a.bind[1] or a.bindName)
  else s = "You do not have a home set." end
  return s .. (" There are %d quest steps ahead here. Make %s your home: talk to %s (about %s away) and choose 'Make this inn your home'."):format(
    a.ahead, a.inn[1], InnName(a.inn), Yd(a.dist))
end

function I.HomeLine(a)
  local e = a.inn
  local s = ("Make %s your home: talk to %s"):format(e[1], InnName(e))
  if a.distToInn then s = s .. (" (about %s away)"):format(Yd(a.distToInn)) end
  s = s .. " and choose 'Make this inn your home'."
  if a.tBind and a.tInn then
    s = s .. (" Right now your hearth goes to %s, about %s from this zone's quests; from %s it would be about %s."):format(
      a.bind[1], Dur(a.tBind), e[1], Dur(a.tInn))
  elseif a.reason == "unknown" then
    s = s .. (" Your hearth is set to %s, which I have no record of."):format(a.bindName)
  elseif a.reason == "unset" then
    s = s .. " You do not have a home set yet."
  elseif a.bind and not a.tBind then
    s = s .. (" Your hearth goes to %s, and I do not know a quick way from there to this zone."):format(a.bind[1])
  end
  return s
end

function I.HearthLine(a)
  local h, v = a.hearth, a.verdict
  local cd = Dur(h and h.duration or ASSUMED_COOLDOWN)
  if v == "hearth" then
    return ("Hearthstone: about %s faster than walking. Walking is about %s; hearth to %s is about %s (%d s cast). It is ready now, then on cooldown for about %s."):format(
      Dur(a.save), Dur(a.walk), a.bind[1], Dur(a.viaHearth), CAST, cd)
  elseif v == "soon" then
    return ("Hearthstone: ready in %s, and even after waiting it beats walking by about %s (walking is about %s, hearth to %s about %s)."):format(
      Dur(h.remain), Dur(a.walk - a.waitTotal), Dur(a.walk), a.bind[1], Dur(a.viaHearth))
  elseif v == "walk" then
    local why = (h.remain > 0 and a.save >= MIN_SAVE) and ("the hearthstone is on cooldown for another " .. Dur(h.remain))
      or "the hearthstone would not save enough time"
    return ("Walk: about %s. Hearth to %s would take about %s, and %s."):format(Dur(a.walk), a.bind[1], Dur(a.viaHearth), why)
  elseif v == "none" then
    return "No Hearthstone in your bags, so there is nothing to compare."
  elseif v == "unknown" then
    if a.bindName and not a.bind then
      return ("Your home is %s, which I have no record of, so I cannot time the hearth."):format(a.bindName)
    elseif not a.bindName then
      return "I cannot tell where your hearthstone is set. Set your home at an inn first."
    end
    return "I cannot work out a travel time for this step yet."
  end
  return "No quest step to plan for."
end

-- ---------------------------------------------------------------- compass target
function I.Target()
  local a = I.HomeAdvice()
  local e = a and a.inn
  if not e then
    local fac, bd = Faction(), nil
    for _, c in ipairs(ns.Inns) do
      if not c[5] or c[5] == fac then
        local x, y = XY(c)
        local b, d = Path.Vector(c[2], x, y)
        if b and (not bd or d < bd) then e, bd = c, d end
      end
    end
  end
  if not e then return nil end
  local x, y = XY(e)
  local home = I.Bound() == e
  return { kind = "inn", p = { x, y }, m = e[2], title = e[6] or (e[1] .. " inn"),
           sub = home and "Your home" or "Make this inn your home" }
end

-- ---------------------------------------------------------------- learning the exact spot, and chat hints
local function Learn()
  local S = Path.State and Path.State()
  if not S then return end
  local e = I.Bound()
  local pm = PlayerMap()
  if not e or pm ~= e[2] or not (C_Map and C_Map.GetPlayerMapPosition) then return end
  local pos = C_Map.GetPlayerMapPosition(pm, "player")
  if not pos then return end
  local x, y
  if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
  if type(x) ~= "number" or (x == 0 and y == 0) then return end
  S.innLearn = S.innLearn or {}
  S.innLearn[e[1]] = { x, y }
end
I.Learn = Learn

-- ---------------------------------------------------------------- the "make it your home?" popup
local declined, accepted, prevMode = {}, {}, nil
local told, lastHearth = {}, -1000

-- whole minutes for the popup ("~9 min", "~1 h 05 min"), short enough to stay on one line
local function Mins(s)
  local m = math.max(1, math.floor((s or 0) / 60 + .5))
  if m >= 60 then return ("%d h %02d min"):format(math.floor(m / 60), m % 60) end
  return m .. " min"
end
I.Mins = Mins

-- the popup in three parts: the title, the Recommended line (nil when the routing gives no reason), and the rest
function I.PopupParts(a)
  local e = a.inn
  local title = ("Make %s your home?"):format(e[1])
  local rec
  local s = ""
  if a.tBind and a.tInn then
    rec = ("Recommended: about %s closer to your quests."):format(Mins(a.tBind - a.tInn))
    -- the time comparison: two short lines (whole minutes so they never wrap), green because it is the reason
    local times = ("Hearth (%s): ~%s\nThis inn (%s): ~%s"):format(
      a.bind[1], Mins(a.tBind), e[1], Mins(a.tInn))
    s = s .. "\n\n|cff33ff33" .. times .. "|r"
  elseif a.ahead then
    rec = "Recommended: several quests are ahead in this zone, and your hearth is not set near them."
    if a.bindName then s = s .. ("\n\nYour hearth is set to %s."):format(a.bindName) end
  elseif a.reason == "unknown" then
    s = s .. ("\n\nYour hearth is set to %s, which I have no record of."):format(a.bindName)
  elseif a.reason == "unset" then
    s = s .. "\n\nYou do not have a home set yet."
  end
  if a.ahead then s = s .. ("\n\n%d quest steps are ahead in this zone."):format(a.ahead) end
  return title, rec, s .. "\n\nYes = compass recalculates to the inn.\nNo = keep your current hearth."
end

-- the whole popup as plain text (also what the dialog falls back to if the box cannot be drawn)
function I.PopupText(a)
  local title, rec, rest = I.PopupParts(a)
  return title .. (rec and ("\n\n" .. rec) or "") .. rest
end

-- The question is a Realm-styled dialog (flat table-blue panel, burn-red top edge, Realm buttons), not the stock game
-- popup: the game resizes the stock popup itself and it came out stretched across the screen. This frame has a fixed
-- width, and its height comes from its own text. Green outlined box on top, as asked: 4 edge textures + green text.
local GREEN = { 0.2, 1, 0.2 }
local dlg

local function Num(v, default)
  v = tonumber(v)
  if v and v > 0 then return v end
  return default
end

local function BuildDialog()
  local UI = ns.UI
  local f = CreateFrame("Frame", "RealmInnDialog", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(380, 220); f:SetPoint("CENTER", UIParent, "CENTER", 0, 170); f:SetFrameStrata("DIALOG")
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton"); f:SetClampedToScreen(true)
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  UI.Skin(f)
  -- Escape closes it; that is not a No, so the question can come back later
  if UISpecialFrames then table.insert(UISpecialFrames, "RealmInnDialog") end

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetPoint("TOP", f, "TOP", 0, -16); f.title:SetWidth(348); f.title:SetJustifyH("CENTER")

  local box = CreateFrame("Frame", nil, f)
  box.fs = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  box.fs:SetTextColor(GREEN[1], GREEN[2], GREEN[3]); box.fs:SetJustifyH("CENTER")
  box.edges = {}
  for i = 1, 4 do
    local t = box:CreateTexture(nil, "BORDER")
    t:SetColorTexture(GREEN[1], GREEN[2], GREEN[3], 1)
    box.edges[i] = t
  end
  local e = box.edges
  e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(2)
  e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(2)
  e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(2)
  e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(2)
  f.box = box

  f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.body:SetWidth(348); f.body:SetJustifyH("CENTER")

  local function Btn(text, point, x, key)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(130, 26); b:SetPoint(point, f, "BOTTOM", x, 16); UI.Button(b)
    b.t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); b.t:SetPoint("CENTER"); b.t:SetText(text)
    b:SetScript("OnClick", function()
      local fn = f[key]
      f:Hide()
      if fn then fn() end
    end)
    return b
  end
  f.yes = Btn(YES or "Yes", "BOTTOMRIGHT", -8, "onYes")
  f.no = Btn(NO or "No", "BOTTOMLEFT", 8, "onNo")
  f:Hide()
  return f
end

-- shows the question for advice a; onYes / onNo run when the player picks a button
function I.ShowDialog(a, onYes, onNo)
  dlg = dlg or BuildDialog()
  local f = dlg
  local title, rec, rest = I.PopupParts(a)
  f.onYes, f.onNo = onYes, onNo
  f.title:SetText(title)
  local W = 348
  local y = 16 + Num(f.title:GetStringHeight(), 18)
  if rec then
    f.box.fs:SetWidth(W - 28)
    f.box.fs:SetText(rec)
    local bh = Num(f.box.fs:GetStringHeight(), 14) + 16
    f.box:ClearAllPoints(); f.box:SetPoint("TOP", f, "TOP", 0, -(y + 10)); f.box:SetSize(W, bh)
    f.box.fs:ClearAllPoints(); f.box.fs:SetPoint("CENTER", f.box, "CENTER", 0, 0)
    f.box:Show()
    y = y + 10 + bh
  else
    f.box:Hide()
  end
  f.body:SetText((rest:gsub("^\n+", "")))
  f.body:ClearAllPoints(); f.body:SetPoint("TOP", f, "TOP", 0, -(y + 12))
  y = y + 12 + Num(f.body:GetStringHeight(), 56)
  f:SetHeight(math.min(460, math.max(150, y + 14 + 26 + 16)))
  f:Show()
end

function I.Dialog() return dlg end

local function Declined(e)
  local S = Path.State and Path.State()
  return declined[e[1]] or (S and S.innNo and S.innNo[e[1]]) or false
end

local function Decline(e)
  declined[e[1]] = true
  local S = Path.State and Path.State()
  if S then S.innNo = S.innNo or {}; S.innNo[e[1]] = true end
end

-- forget a No (one inn), or every No when e is nil
local function Forget(e)
  local S = Path.State and Path.State()
  if e then
    declined[e[1]] = nil
    if S and S.innNo then S.innNo[e[1]] = nil end
  else
    declined, accepted = {}, {}
    if S then S.innNo = nil end
  end
end
I.Forget = Forget

-- returns true when the question was shown
local function Ask(a)
  if not (CreateFrame and UIParent) then return false end
  local e = a.inn
  local ok = pcall(I.ShowDialog, a,
    function()
      accepted[e[1]] = true
      local O = Path.Opts and Path.Opts()
      if O then
        if O.trackMode ~= "inn" then prevMode = O.trackMode end
        O.trackMode = "inn"
      end
      if Path.ResetTrack then Path.ResetTrack() end
      if Path.UpdateHUD then Path.UpdateHUD() end
      Path.Print("compass is pointing at the " .. e[1] .. " inn.")
    end,
    function() Decline(e) end)
  return ok
end
I.Ask = Ask

-- asks once per key; skips inns the player said No to; waits out combat
local function Offer(k, a, fallback)
  if told[k] then return end
  if Declined(a.inn) then told[k] = true; return end
  if InCombatLockdown and InCombatLockdown() then return end
  told[k] = true
  if not Ask(a) then Path.Print(fallback) end
end

-- inn mode is only for getting to an inn to set home: once that inn is home, resume the previous mode or the quest route.
-- Runs from the timer too, because the bind event does not fire after a /reload and the mode is saved.
local function LeaveInnIfHome()
  local O = Path.Opts and Path.Opts()
  if not (O and O.trackMode == "inn") then return end
  local t = I.Target()
  if not (t and t.sub == "Your home") then return end
  O.trackMode = prevMode or "quest"; prevMode = nil
  if Path.ResetTrack then Path.ResetTrack() end
  if Path.UpdateHUD then Path.UpdateHUD() end
end
I.LeaveInnIfHome = LeaveInnIfHome

local function Tick()
  pcall(LeaveInnIfHome)
  local O = Path.Opts and Path.Opts()
  if not O or O.innTips == false then return end
  local a = I.HomeAdvice()
  if a and a.worth and PlayerMap() == a.map then
    local k = "home:" .. a.map .. ":" .. tostring(a.bindName)
    Offer(k, a, I.HomeLine(a))
    if accepted[a.inn[1]] and a.distToInn and a.distToInn < 60 then      local k2 = "here:" .. a.inn[1] .. ":" .. tostring(a.bindName)
      if not told[k2] then
        told[k2] = true
        Path.Print("You are at the " .. a.inn[1] .. " inn: talk to the innkeeper and choose 'Make this inn your home'.")
      end
    end
  end
  local hr = not (a and a.worth and PlayerMap() == a.map) and I.HereAdvice()
  if hr then
    local k3 = "now:" .. hr.map .. ":" .. tostring(hr.bindName)
    Offer(k3, hr, I.HereLine(hr))
  end
  local h = I.Advise()
  if h.verdict == "hearth" then
    local now = GetTime and GetTime() or 0
    local k = "hearth:" .. tostring(h.idx) .. ":" .. tostring(h.bindName)
    if not told[k] and now - lastHearth >= 120 then
      told[k] = true; lastHearth = now
      Path.Print(I.HearthLine(h))
    end
  end
end
I.Tick = Tick

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "HEARTHSTONE_BOUND")
local acc = 0
ev:SetScript("OnEvent", function()
  Learn()
  local O = Path.Opts and Path.Opts()
  if O and O.innTips ~= false then
    local _, name = I.Bound()
    if name then Path.Print("home is now " .. name .. ". The hearthstone goes there.") end
  end
  -- home is set: leave inn mode and go back to where the player was, or the quest route
  if O and O.trackMode == "inn" then O.trackMode = prevMode or "quest"; prevMode = nil end
  if Path.UpdateHUD then Path.UpdateHUD() end
  if Path.ResetTrack then Path.ResetTrack() end
end)
ev:SetScript("OnUpdate", function(_, dt)
  acc = acc + (dt or 0)
  if acc < 5 then return end
  acc = 0
  pcall(Tick)
end)

-- /path inn          where to make your home for this part of the route, and point the compass at it
-- /path inn tips     turn the inn and hearthstone chat hints on or off
-- /path hearth       should you use the hearthstone for the current step
local old = Path.SlashExtra
function Path.SlashExtra(cmd, rest)
  if cmd == "hearth" then
    local a = I.Advise()
    Path.Print(I.HearthLine(a))
    local h = a.hearth
    if h.has then
      Path.Print(h.remain > 0 and ("hearthstone cooldown: " .. Dur(h.remain) .. " left") or "hearthstone cooldown: ready")
    end
    if a.bindName then Path.Print("home: " .. a.bindName .. (a.bind and "" or " (not on my list)")) end
    return true
  end
  if cmd == "inn" or cmd == "home" then
    local O = Path.Opts()
    if (rest or "") == "tips" then
      O.innTips = not (O.innTips ~= false)
      Path.Print("inn and hearthstone hints " .. (O.innTips and "on" or "off"))
      if Path.Window and Path.Window.Refresh then Path.Window.Refresh() end
      return true
    end
    local a = I.HomeAdvice()
    if a and a.inn then Forget(a.inn) end
    if not a then
      Path.Print("I have no inn on record for the zone your route is in.")
    elseif a.reason == "home" then
      Path.Print(("your home is already %s, the best inn for the quests ahead in %s."):format(a.inn[1], Zone(a.map)))
    elseif a.worth then
      Path.Print(I.HomeLine(a))
    else
      Path.Print(("%s is the inn for %s, but moving your home there would not save much (or there are too few quests left in the zone)."):format(a.inn[1], Zone(a.map)))
    end
    if a and a.reason == "home" then return true end
    O.trackMode = "inn"
    if Path.ResetTrack then Path.ResetTrack() end
    if Path.UpdateHUD then Path.UpdateHUD() end
    if I.Target() then Path.Print("compass is pointing at the inn. Change it in the compass T menu.") end
    return true
  end
  if old then return old(cmd, rest) end
end
