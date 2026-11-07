-- Class quest alerts: when a quest for your class opens up at your level, say so and point the compass at its giver.
local ADDON, ns = ...
local Path = ns.Path

local RACEBIT = { Human = 1, Orc = 2, Dwarf = 4, NightElf = 8, Scourge = 16, Tauren = 32, Gnome = 64, Troll = 128 }
local told = {}
local cache, at = nil, 0
local byId

local function Opt() return Path.Opts() end

local function List()
  local _, class = UnitClass("player")
  return class and ns.ClassQuests and ns.ClassQuests[class]
end

local function RaceOK(mask)
  if not mask or mask == 0 then return true end
  local _, race = UnitRace("player")
  local b = race and RACEBIT[race]
  return (not b) or (mask % (b * 2) >= b)
end

local function Eligible(e, lvl, fac)
  local q = e[1]
  if e[7] ~= "AH" and e[7] ~= fac then return false end
  if lvl < e[3] or lvl - e[4] > 14 then return false end
  if not RaceOK(e[5]) then return false end
  if Path.Completed(q) or Path.InLog(q) then return false end
  local o = Opt()
  if o and o.classSkip and o.classSkip[q] then return false end
  local pre = e[11]
  if pre and #pre > 0 then
    if e[12] then for _, p in ipairs(pre) do if not Path.Completed(p) then return false end end
    else
      local any = false
      for _, p in ipairs(pre) do if Path.Completed(p) then any = true end end
      if not any then return false end
    end
  end
  return true
end

-- is this one of your class quests (so auto-accept may take it)?
function Path.IsClassQuest(q, title)
  local list = List()
  if not list then return false end
  local lvl = Path.Level()
  local fac = (UnitFactionGroup and UnitFactionGroup("player")) == "Horde" and "H" or "A"
  for _, e in ipairs(list) do
    if (e[1] == q or (not q and title and e[2] == title)) and (e[7] == "AH" or e[7] == fac) and RaceOK(e[5]) and lvl >= e[3] then return true end
  end
  return false
end

-- the nearest class quest you can pick up now
function Path.ClassPending()
  local o = Opt()
  if not o or o.classq == false then return nil end
  local now = GetTime and GetTime() or 0
  if cache ~= nil and now - at < 2 then return cache or nil end
  local list = List()
  local best, bd
  if list then
    local lvl = Path.Level()
    local fac = (UnitFactionGroup and UnitFactionGroup("player")) == "Horde" and "H" or "A"
    for _, e in ipairs(list) do
      if Eligible(e, lvl, fac) then
        local b, d = Path.Vector(e[8], e[9], e[10])
        if b and (not bd or d < bd) then best, bd = e, d end
      end
    end
  end
  local r
  if best then
    r = { kind = "A", p = { best[9], best[10] }, m = best[8], title = best[2], q = best[1], giver = best[6],
          sub = ("Class quest from " .. best[6] .. ". /path classskip to ignore it"), class = true }
    if not told[best[1]] then
      told[best[1]] = true
      local msg = ("Class quest available: %s (from %s). The compass points there."):format(best[2], best[6])
      if Path.Print then Path.Print(msg) end
      if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage("Class quest: " .. best[2] .. " - " .. best[6], 0.91, 0.67, 0.21) end
    end
  end
  cache, at = r or false, now
  return r
end

function Path.ClassSkip()
  local c = Path.ClassPending()
  local o = Opt()
  if c and o then o.classSkip = o.classSkip or {}; o.classSkip[c.q] = true; cache = nil; Path.ResetTrack(); Path.Changed(true) end
end

local f = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_LEVEL_UP", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "ZONE_CHANGED_NEW_AREA" }) do pcall(f.RegisterEvent, f, ev) end
f:SetScript("OnEvent", function() cache = nil; if Path.ResetTrack then Path.ResetTrack() end end)

local prev = Path.SlashExtra
Path.SlashExtra = function(msg, ...)
  if msg == "classskip" then Path.ClassSkip() return true end
  if prev then return prev(msg, ...) end
end
