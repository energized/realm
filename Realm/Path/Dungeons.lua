-- Dungeons: where the entrances are, and which ones you (and your group) could do right now.
-- Used by the party tracker map (entrance pins), the compass (Track > Nearby dungeon) and /path dungeon.
-- Entrance coordinates are zone-map fractions typed in from memory of the classic game: close, not surveyed.
local ADDON, ns = ...
local Path = ns.Path
local UI = ns.UI

-- { name, map, x, y, recLow, recHigh, minLevel, groupSize, faction }
--   map = zone map ID of your build; recLow/recHigh = the levels the dungeon is balanced for;
--   minLevel = lowest level the game lets you in; faction = "A" / "H" when the entrance is in a capital of one side.
ns.Dungeons = {
  { "Ragefire Chasm",           1454, .52, .49, 13, 18,  8,  5, "H" },
  { "The Deadmines",            1436, .43, .73, 17, 24, 10,  5 },
  { "Wailing Caverns",          1413, .46, .37, 17, 24, 10,  5 },
  { "Shadowfang Keep",          1421, .45, .68, 22, 30, 14,  5 },
  { "Blackfathom Deeps",        1440, .14, .14, 24, 32, 15,  5 },
  { "The Stockade",             1453, .41, .56, 24, 32, 15,  5, "A" },
  { "Gnomeregan",               1426, .25, .39, 29, 38, 19,  5 },
  { "Razorfen Kraul",           1413, .41, .90, 30, 40, 20,  5 },
  { "Scarlet Monastery",        1420, .85, .32, 28, 44, 20,  5 },
  { "Razorfen Downs",           1413, .49, .94, 40, 50, 25,  5 },
  { "Uldaman",                  1418, .42, .13, 41, 51, 30,  5 },
  { "Zul'Farrak",               1446, .39, .21, 44, 54, 35,  5 },
  { "Maraudon",                 1443, .29, .62, 46, 55, 30,  5 },
  { "The Temple of Atal'Hakkar",1435, .70, .54, 50, 60, 45,  5 },
  { "Blackrock Depths",         1427, .35, .85, 52, 60, 40,  5 },
  { "Lower Blackrock Spire",    1428, .30, .38, 55, 60, 45, 10 },
  { "Upper Blackrock Spire",    1428, .30, .38, 58, 60, 45, 10 },
  { "Dire Maul",                1444, .62, .31, 55, 60, 45,  5 },
  { "Scholomance",              1422, .69, .73, 58, 60, 45,  5 },
  { "Stratholme",               1423, .31, .16, 58, 60, 45,  5 },
  { "Zul'Gurub",                1434, .54, .18, 58, 60, 56, 20 },
  { "Molten Core",              1428, .30, .38, 60, 60, 55, 40 },
  { "Onyxia's Lair",            1445, .53, .77, 60, 60, 55, 40 },
}

local D = {}
Path.Dungeons = D

local function Faction()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  return f == "Horde" and "H" or "A"
end

-- how many people could go, and the lowest level among them (you plus your party)
function D.Group()
  local n, low = 1, Path.Level()
  if IsInGroup and IsInGroup() then
    local count = (GetNumGroupMembers and GetNumGroupMembers()) or 1
    n = math.max(1, count)
    for i = 1, math.min(n - 1, 4) do
      local l = UnitLevel and UnitLevel("party" .. i)
      if l and l > 0 and l < low then low = l end
    end
  end
  return n, low
end

-- "ok" (balanced for you), "low" (a few levels under, risky), "easy" (well over), "locked" (the game will not let you in)
function D.Fit(d, level)
  if level < d[7] then return "locked" end
  if level < d[5] - 2 then return "low" end
  if level > d[6] + 6 then return "easy" end
  return "ok"
end

local FIT_TEXT = { ok = "good fit", low = "a bit low", easy = "easy now", locked = "too low to enter" }
D.FitText = FIT_TEXT

-- ranked 5-man and 10-man dungeons for the player and group, nearest and best-fitting first
function D.Suggestions(limit)
  local out = {}
  local n, low = D.Group()
  local fac = Faction()
  for _, d in ipairs(ns.Dungeons) do
    if (not d[9] or d[9] == fac) and d[8] <= 10 then
      local fit = D.Fit(d, low)
      if fit ~= "locked" and fit ~= "easy" then
        local b, dist, why = Path.Vector(d[2], d[3], d[4])
        local mid = (d[5] + d[6]) / 2
        local score = 100 - math.abs(low - mid) * 6 - (fit == "low" and 12 or 0)
        if dist then score = score - dist / 150 else score = score - 40 end
        if d[8] > n then score = score - (d[8] - n) * 1.5 end
        out[#out + 1] = { d = d, fit = fit, b = b, dist = dist, why = why, score = score, need = d[8] }
      end
    end
  end
  table.sort(out, function(a, c) return a.score > c.score end)
  if limit then for i = #out, limit + 1, -1 do out[i] = nil end end
  return out, n, low
end

local function Zone(map)
  local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
  return info and info.name or ("map " .. tostring(map))
end

local function Line(i, e, n)
  local d = e.d
  local where = e.dist and ((e.dist >= 1000 and ("%.1fk yd"):format(e.dist / 1000) or (math.floor(e.dist + .5) .. " yd")) .. " away") or "another continent"
  local grp = (e.need > n) and (", needs " .. e.need .. " players") or ""
  return ("%d. %s (%s), levels %d-%d, %s, %s%s"):format(i, d[1], Zone(d[2]), d[5], d[6], FIT_TEXT[e.fit], where, grp)
end

-- the compass target for Track > Nearby dungeon
function D.Target()
  local r = D.Suggestions(1)
  local e = r[1]
  if not e then return nil end
  local d = e.d
  return { kind = "dungeon", p = { d[3], d[4] }, m = d[2], title = d[1],
           sub = ("Dungeon, levels %d-%d, %s"):format(d[5], d[6], FIT_TEXT[e.fit]) }
end

-- ---------------------------------------------------------------- hints
local last
local function Hint(force)
  local O = Path.Opts()
  if not O or (not force and not O.dungeonTips) then return end
  local r, n, low = D.Suggestions(2)
  local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local key = tostring(map) .. ":" .. tostring(low)
  if not force and key == last then return end
  last = key
  if #r == 0 then
    if force then Path.Print("no dungeon fits level " .. low .. " right now") end
    return
  end
  local near = r[1]
  if not force and (not near.dist or near.dist > 2500) then return end    -- only when one is actually close
  Path.Print("dungeon you could run: " .. Line(1, near, n):gsub("^1%. ", "") .. "  (/path dungeon)")
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:SetScript("OnEvent", function()
  if C_Timer and C_Timer.After then C_Timer.After(3, function() pcall(Hint, false) end) end
end)

-- /path dungeon            list the best ones and aim the compass at the first
-- /path dungeon tips       turn the nearby-dungeon chat hint on or off
local old = Path.SlashExtra
function Path.SlashExtra(cmd, rest)
  if cmd == "dungeon" or cmd == "dungeons" then
    local O = Path.Opts()
    if (rest or "") == "tips" then
      O.dungeonTips = not O.dungeonTips
      Path.Print("dungeon hints " .. (O.dungeonTips and "on" or "off"))
      if Path.Window and Path.Window.Refresh then Path.Window.Refresh() end
      return true
    end
    local r, n, low = D.Suggestions(4)
    if #r == 0 then Path.Print("no dungeon fits level " .. low .. " right now") return true end
    Path.Print(("dungeons for %s (lowest level %d, %d in group):"):format(n > 1 and "your group" or "you", low, n))
    for i, e in ipairs(r) do Path.Print(Line(i, e, n)) end
    O.trackMode = "dungeon"
    if Path.ResetTrack then Path.ResetTrack() end
    if Path.UpdateHUD then Path.UpdateHUD() end
    Path.Print("compass is now pointing at " .. r[1].d[1] .. ". Change it in the compass T menu.")
    return true
  end
  if old then return old(cmd, rest) end
end

Path.DungeonHint = Hint
