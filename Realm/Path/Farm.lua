-- Farming spots: a gold $ on the compass for the best grinding spot in your current zone for your level.
-- Spots come from where many hostile mobs of your level live; humanoids score higher (cloth and coin).
local ADDON, ns = ...
local Path = ns.Path
local UI = ns.UI
local C = UI.C

local best, bestD, bestMap
local acc = 99
local mark

local function Secret(v) return issecretvalue and v ~= nil and issecretvalue(v) end
local function Wrap(a) a = a % (math.pi * 2); if a > math.pi then a = a - math.pi * 2 end return a end

-- ranked spots for the zone you are standing in
function Path.FarmSpots(limit)
  local out = {}
  local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local list = map and ns.Farm and ns.Farm[map]
  if not list then return out, map end
  local lvl = Path.Level()
  for _, s in ipairs(list) do
    local lo, hi = s[4], s[5]
    local mid = (lo + hi) / 2
    if mid >= lvl - 3 and mid <= lvl + 1 then
      local b, d = Path.Vector(map, s[1], s[2])
      if b then
        local score = s[3] * (1 + 0.5 * s[6]) - d / 60 - math.abs(mid - (lvl - 1)) * 2
        out[#out + 1] = { s = s, b = b, d = d, score = score }
      end
    end
  end
  table.sort(out, function(a, c) return a.score > c.score end)
  if limit then for i = #out, limit + 1, -1 do out[i] = nil end end
  return out, map
end

local function Refresh()
  local O = Path.Opts()
  best = nil
  if not O or not O.farm then return end
  local r, map = Path.FarmSpots(1)
  if r[1] then best = { s = r[1].s, map = map } end
end

local function Build()
  local c = _G.RealmCompass
  if not c or mark then return end
  mark = CreateFrame("Frame", nil, c)
  mark:SetSize(22, 18); mark:SetFrameLevel(c:GetFrameLevel() + 4)
  mark.t = mark:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  mark.t:SetPoint("CENTER"); mark.t:SetText("$"); mark.t:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
  if mark.t.SetFont then mark.t:SetFont(UI.FONT, 18, "OUTLINE") end
  mark.d = mark:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  mark.d:SetPoint("TOP", mark, "BOTTOM", 0, 1); mark.d:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
  if mark.d.SetFont then mark.d:SetFont(UI.FONT, 10, "OUTLINE") end
  mark:Hide()
end

-- called by the compass every frame
function Path.DrawFarm(heading, W, pxPerRad, half, dt)
  local O = Path.Opts()
  if not O or not O.farm then if mark then mark:Hide() end return end
  Build()
  if not mark then return end
  acc = acc + (dt or 0)
  if acc > 2 then acc = 0; Refresh() end
  if not best then mark:Hide() return end
  local b, d = Path.Vector(best.map, best.s[1], best.s[2])
  if not b then mark:Hide() return end
  local c = _G.RealmCompass
  local rel = Wrap(b - heading)
  local x = math.max(-W / 2 + 12, math.min(W / 2 - 12, rel * pxPerRad))
  mark:ClearAllPoints(); mark:SetPoint("CENTER", c, "CENTER", x, 15)
  mark.d:SetText(d >= 1000 and string.format("%.1fk", d / 1000) or tostring(math.floor(d + .5)))
  mark:Show()
end

local old = Path.SlashExtra
function Path.SlashExtra(cmd, rest)
  if cmd == "farm" then
    local r, map = Path.FarmSpots(3)
    if #r == 0 then Path.Print("no farming spots known here for your level") return true end
    for i, e in ipairs(r) do
      local s = e.s
      Path.Print(("%d. %s, level %d-%d, about %d mobs, %d yd away%s"):format(i, s[7], s[4], s[5], s[3], math.floor(e.d + .5), s[6] >= .5 and " (humanoids: cloth and coin)" or ""))
    end
    local O = Path.Opts(); if not O.farm then O.farm = true; Path.Print("$ marker turned on") end
    return true
  end
  if old then return old(cmd, rest) end
end
