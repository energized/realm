-- Realm Path: a leveling route (quests in a good order), a top-centre compass, quest automation and trainer stops.
local ADDON, ns = ...
local Path = {}
ns.Path = Path

local UI = ns.UI
local function Print(m) print(UI.H.gold .. "Realm|r " .. UI.H.blue .. "Path|r: " .. tostring(m)) end
Path.Print = Print

local DEFAULTS = {
  hud = true, panel = true, locked = true,
  autoAccept = true, autoTurnin = true, smartReward = true, offRoute = false,
  banner = true, classq = true, corpse = true, levelTips = true,
  trail = true, friends = true, trainers = true, tapWarn = true, farm = false, professions = true,
  panelMode = "dock", compact = false, boldMarkers = true, travelTips = true, travelGuide = true, discoverFlights = false,
  compassWidth = 560, compassScale = 1,
}
local O, S           -- options, per-character state
local route, steps, chapters
local cur, curTrainer
local aStep = {}
local warned = {}
local listeners = {}

local CQ = C_QuestLog

local function Secret(v) return issecretvalue and v ~= nil and issecretvalue(v) end

function Path.Opts() return O end
function Path.State() return S end

-- ------------------------------------------------------------ quest helpers
local function Completed(q)
  if CQ and CQ.IsQuestFlaggedCompleted then return CQ.IsQuestFlaggedCompleted(q) and true or false end
  return false
end
local function InLog(q)
  if CQ and CQ.IsOnQuest then return CQ.IsOnQuest(q) and true or false end
  if CQ and CQ.GetLogIndexForQuestID then return (CQ.GetLogIndexForQuestID(q) or 0) > 0 end
  return false
end
local function Ready(q)
  if CQ and CQ.ReadyForTurnIn then return CQ.ReadyForTurnIn(q) and true or false end
  if CQ and CQ.IsComplete then return CQ.IsComplete(q) and true or false end
  return false
end
Path.Completed, Path.InLog, Path.Ready = Completed, InLog, Ready

local function Objectives(q)
  if not (CQ and CQ.GetQuestObjectives) then return nil end
  local ok, objs = pcall(CQ.GetQuestObjectives, q)
  if ok and type(objs) == "table" then return objs end
end

-- true / false when the named objective is finished or not, nil when unknown
local function ObjectiveDone(q, name)
  local objs = Objectives(q)
  if not objs then return nil end
  name = name and name:lower()
  for _, o in ipairs(objs) do
    if name and o.text and not Secret(o.text) and o.text:lower():find(name, 1, true) then return o.finished and true or false end
  end
  return nil
end

-- live "3/10" for a kill or collect step
function Path.ObjectiveProgress(q, name)
  local objs = Objectives(q)
  if not objs then return nil end
  local lname = name and name:lower()
  local first
  for _, o in ipairs(objs) do
    if o.text and not Secret(o.text) then
      local have, need = o.text:match("(%d+)%s*/%s*(%d+)")
      if have then
        first = first or { tonumber(have), tonumber(need) }
        if lname and o.text:lower():find(lname, 1, true) then return tonumber(have), tonumber(need) end
      end
    end
  end
  if first then return first[1], first[2] end
end

-- ------------------------------------------------------------ positions
local calib = {}
local function WorldPoint(map, x, y)
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
  local cont, w = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(x, y))
  if not w then return end
  return cont, w.x, w.y
end

Path.WorldPoint = WorldPoint

-- find which world axis is north and which is east, from two probes on the map
local function Calibration(map)
  local c = calib[map]
  if c ~= nil then return c or nil end
  local c1, nx1, ny1 = WorldPoint(map, .5, .4)
  local _, nx2, ny2 = WorldPoint(map, .5, .6)
  local _, ex1, ey1 = WorldPoint(map, .6, .5)
  local _, ex2, ey2 = WorldPoint(map, .4, .5)
  if not (nx1 and nx2 and ex1 and ex2) then calib[map] = false return nil end
  local nx, ny = nx1 - nx2, ny1 - ny2          -- y goes down the map, so up (north) is minus
  local ex, ey = ex1 - ex2, ey1 - ey2
  local nl, el = math.sqrt(nx * nx + ny * ny), math.sqrt(ex * ex + ey * ey)
  if nl == 0 or el == 0 then calib[map] = false return nil end
  calib[map] = { nx = nx / nl, ny = ny / nl, ex = ex / el, ey = ey / el, cont = c1 }
  return calib[map]
end

function Path.PlayerWorld()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return end
  local map = C_Map.GetBestMapForUnit("player")
  if not map then return end
  local pos = C_Map.GetPlayerMapPosition(map, "player")
  if not pos then return end
  local x, y
  if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
  if not x or Secret(x) or Secret(y) or (x == 0 and y == 0) then return end
  local cont, wx, wy = WorldPoint(map, x, y)
  if not cont then return end
  return cont, wx, wy, map
end

-- bearing (radians from north, clockwise) and distance in yards from the player to a point on a map
function Path.Vector(tmap, tx, ty)
  local pc, px, py, pmap = Path.PlayerWorld()
  if not pc then return nil, nil, "noplayer" end
  local cal = Calibration(pmap)
  local tc, wx, wy = WorldPoint(tmap, tx, ty)
  if not tc then return nil, nil, "nopoint" end
  if tc ~= pc then return nil, nil, "continent" end
  if not cal then return nil, nil, "nocal" end
  local dx, dy = wx - px, wy - py
  local n = dx * cal.nx + dy * cal.ny
  local e = dx * cal.ex + dy * cal.ey
  local atan = math.atan2 or math.atan
  return atan(e, n), math.sqrt(dx * dx + dy * dy)
end

-- ------------------------------------------------------------ route / state
function Path.Level() return (UnitLevel and UnitLevel("player")) or 1 end

local function CharKey()
  return (UnitName and UnitName("player") or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "")
end

function Path.RouteKey()
  local _, race = UnitRace("player")
  local _, class = UnitClass("player")
  if not race or not class then return end
  return (race .. "_" .. class):upper()
end

local function Index()
  aStep = {}
  for i, s in ipairs(steps) do
    if s.t == "A" and s.q and not aStep[s.q] then aStep[s.q] = i end
  end
end

function Path.Route() return route, steps, chapters end

-- Routes are stored as functions so only the one you use is built.
local function ResolveRoute(key)
  local r = key and ns.PathRoutes and ns.PathRoutes[key]
  if type(r) == "function" then
    local ok, t = pcall(r)
    r = ok and t or nil
    ns.PathRoutes[key] = r
  end
  return r
end
Path.ResolveRoute = ResolveRoute

function Path.Load()
  local key = Path.RouteKey()
  route = ResolveRoute(key)
  Path.generic = false
  Path.raceOnly = false
  local _, race = UnitRace("player")
  local _, class = UnitClass("player")
  -- no route for this class: use the race's own start zones without class quests (class quest alerts still work)
  if not route and race then
    route = ResolveRoute(race:upper() .. "_ANY")
    if route then
      Path.raceOnly = true
      C_Timer.After(4, function()
        Print(("no %s route for %s yet, so I'm using the %s start-zone route without class quests. Class quest alerts and trainer stops still work."):format(class or "?", race, race))
      end)
    end
  end
  -- no route for this race either: use the faction's general quest route (the quests anyone can do),
  -- without the start zone and the class quests
  if not route and UnitFactionGroup then
    route = ResolveRoute(UnitFactionGroup("player") == "Horde" and "ORC_ANY" or "HUMAN_ANY")
    if route then
      Path.generic = true
      C_Timer.After(4, function()
        Print(("no exact route for %s %s yet, so I'm using the general quest route for your faction (class quests are not included). Trainer stops are for your class."):format(race or "?", class or "?"))
      end)
    end
  end
  Path.noRoute = (not route) and key or nil
  if route then steps, chapters = route.steps, route.chapters; Index() else steps, chapters = nil, nil end
end

-- ------------------------------------------------------------ resolving the current step
local function ChapterOf(s) return chapters and chapters[s.ch] end

local function Done(s, i, lvl)
  local t = s.t
  if t == "A" then return Completed(s.q) or InLog(s.q)
  elseif t == "T" then return Completed(s.q)
  elseif t == "D" then
    if Completed(s.q) then return true end
    if not InLog(s.q) then return false end
    if Ready(s.q) then return true end
    return ObjectiveDone(s.q, s.npc) == true
  elseif t == "G" then
    local _, _, _, pmap = Path.PlayerWorld()
    return pmap ~= nil and pmap == s.m
  elseif t == "L" then return lvl >= (s.need or 0)
  elseif t == "R" then return true          -- trainer stops are handled separately (see TrainerStop)
  end
  return false
end

-- "ok", "skip", or "redirect" plus the index to redirect to
local function Availability(s, i, lvl)
  local t = s.t
  if Path.generic and (s.cls or s.ch == 1) and not (s.q and InLog(s.q)) then return "skip" end
  local c = ChapterOf(s)
  local over = c and c.exit and c.exit > 0 and lvl >= c.exit
  if t == "A" then
    if InLog(s.q) then return "ok" end
    if s.rl and lvl < s.rl then return "skip" end
    if over then return "skip" end
    if s.ql and lvl - s.ql >= 8 then return "skip" end
    return "ok"
  elseif t == "D" or t == "T" then
    if Completed(s.q) then return "ok" end
    if InLog(s.q) then return "ok" end
    local a = aStep[s.q]
    if a and not S.skip[a] then
      local av = Availability(steps[a], a, lvl)
      if av == "ok" then return "redirect", a end
    end
    return "skip"
  elseif t == "G" then
    if over then return "skip" end
    return "ok"
  elseif t == "L" then
    if over then return "skip" end
    if s.opt then
      local g = "L" .. i
      if not warned[g] then
        warned[g] = true
        Print((s.tx or "The next zone is better at a higher level.") .. " (/path skip to leave, or grind a bit first.)")
      end
      return "skip"
    end
    return "ok"
  end
  return "skip"
end

function Path.Resolve()
  if not steps then cur = nil return nil end
  local lvl = Path.Level()
  local first, firstTo, n
  local best, bestTo, bestD
  local firstD
  for i = 1, #steps do
    if not S.skip[i] then
      local s = steps[i]
      if not Done(s, i, lvl) then
        local av, to = Availability(s, i, lvl)
        if av == "ok" or av == "redirect" then
          local pick = av == "redirect" and to or i
          local st = steps[pick]
          local d
          if st.m and st.p then local b, dist = Path.Vector(st.m, st.p[1], st.p[2]); d = b and dist end
          if not first then first, firstTo, firstD = i, pick, d; n = 0 end
          n = n + 1
          if d and (not bestD or d < bestD) then best, bestD = pick, d end
          -- only look a little way ahead, and stay inside the first step's chapter
          if n >= 25 or steps[i].ch ~= steps[first].ch then break end
        end
      end
    end
  end
  if first then
    -- where you actually are wins: if the next step in order is far away but another open step is close, start there
    if firstD and firstD > 500 and best and bestD < firstD * 0.5 and bestD < 400 then
      cur = best return best
    end
    cur = firstTo return firstTo
  end
  cur = nil
  return nil
end

-- ------------------------------------------------------------ trainer stops
-- Every other level (4, 6, 8, ...) your class trainer has new spells. When a trainer is close, or you are
-- two tiers behind, the compass points you at the nearest one of your faction. Opening the trainer clears it.
local function Tier(lvl) return math.floor(lvl / 2) * 2 end

local function Faction()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  return f == "Horde" and "H" or "A"
end

local trainerCache = { tier = -1 }
function Path.TrainerStop()
  if not O or O.trainers == false or not S then return nil end
  local lvl = Path.Level()
  local tier = Tier(lvl)
  if tier < 4 or tier <= (S.trainedAt or 0) or tier <= (S.trainSkip or 0) then return nil end
  local _, class = UnitClass("player")
  local list = ns.Trainers and class and ns.Trainers[class]
  if not list then return nil end
  local fac = Faction()
  local best, bd
  for _, t in ipairs(list) do
    if t[5] == fac or t[5] == "AH" then
      local b, d = Path.Vector(t[2], t[3], t[4])
      if b and (not bd or d < bd) then best, bd = t, d end
    end
  end
  if not best then return nil end
  local behind = tier - (S.trainedAt or 0) >= 4
  if bd > 650 and not behind then return nil end
  local c = class:sub(1, 1) .. class:sub(2):lower()
  return { t = "R", n = "Train " .. c .. " spells", npc = best[1], m = best[2], p = { best[3], best[4] },
           tx = "New " .. c .. " spells are ready at your trainer. /path skip to put it off.", virtual = true }, bd
end

function Path.Current()
  local pv = Path.ProfCurrent and Path.ProfCurrent()      -- professions: a leveling detour or a trainer pick
  if pv then return pv, cur or 0 end
  local trainer = Path.TrainerStop()
  if trainer then return trainer, cur or 0 end
  if not cur then return nil end
  return steps[cur], cur
end

function Path.RealStep() if not cur then return nil end return steps[cur], cur end

-- the next few steps after the current one, for the panel
function Path.Upcoming(n)
  local out = {}
  if not cur then return out end
  local lvl = Path.Level()
  local from = Path.TrainerStop() and cur - 1 or cur
  for i = from + 1, #steps do
    if #out >= n then break end
    local s = steps[i]
    if not S.skip[i] and not Done(s, i, lvl) and Availability(s, i, lvl) ~= "skip" then out[#out + 1] = { s, i } end
  end
  return out
end

function Path.Skip()
  if Path.ProfSkip and Path.ProfSkip() then Path.Changed(true) return end
  local trainer = Path.TrainerStop()
  if trainer then S.trainSkip = Tier(Path.Level()); Path.Changed(true) return end
  if cur then S.skip[cur] = true; Path.Changed(true) end
end
function Path.Back()
  local last
  for i = 1, (cur or #steps + 1) - 1 do if S.skip[i] then last = i end end
  if last then S.skip[last] = nil; Path.Changed(true) else Print("nothing to go back to") end
end
function Path.SkipChapter()
  if not cur then return end
  local ch = steps[cur].ch
  for i = cur, #steps do
    if steps[i].ch == ch then S.skip[i] = true end
  end
  Path.Changed(true)
end

function Path.OnChange(fn) listeners[#listeners + 1] = fn end
function Path.Changed(force)
  Path.Resolve()
  for _, f in ipairs(listeners) do pcall(f) end
  if Path.UpdateHUD then Path.UpdateHUD() end
  if Path.UpdatePanel then Path.UpdatePanel() end
  if Path.Window and Path.Window.Refresh then Path.Window.Refresh() end
end

-- which quests belong to the route (used by automation)
function Path.IsRouteQuest(q)
  return aStep[q] ~= nil
end
function Path.RouteQuestByName(name)
  if not steps or not name then return nil end
  for _, s in ipairs(steps) do
    if s.t == "A" and s.n == name then return s.q end
  end
end

-- ------------------------------------------------------------ events
local ev = CreateFrame("Frame")
local pending
local function Soon()
  if pending then return end
  pending = true
  C_Timer.After(0.3, function() pending = false; if O then Path.Changed() end end)
end

local function ChapterTip(lvl)
  if not chapters then return end
  for i, c in ipairs(chapters) do
    if c.exit and c.exit > 0 and lvl == c.exit then
      Print("Level " .. lvl .. ": time to leave " .. c.name .. ". " .. (c.travel or ""))
      return
    end
  end
end

ev:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "PLAYER_LEVEL_UP", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED",
                     "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "TRAINER_SHOW" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, e, a1)
  if e == "PLAYER_LOGIN" then
    RealmDB = RealmDB or {}
    RealmDB.pathOpts = RealmDB.pathOpts or {}
    for k, v in pairs(DEFAULTS) do if RealmDB.pathOpts[k] == nil then RealmDB.pathOpts[k] = v end end
    O = RealmDB.pathOpts
    RealmDB.pathChars = RealmDB.pathChars or {}
    local key = CharKey()
    RealmDB.pathChars[key] = RealmDB.pathChars[key] or { skip = {} }
    S = RealmDB.pathChars[key]
    S.skip = S.skip or {}
    Path.Load()
    C_Timer.After(1.5, function() Path.Changed(true) end)
    return
  end
  if not O then return end
  if e == "TRAINER_SHOW" then
    S.trainedAt = Tier(Path.Level())
    Path.Changed(true)
    return
  end
  if e == "PLAYER_LEVEL_UP" then
    local lvl = tonumber(a1) or Path.Level()
    if O.levelTips then
      ChapterTip(lvl)
      if Tier(lvl) == lvl and lvl >= 4 then Print("Level " .. lvl .. ": your trainer has new spells. The compass will point you at one.") end
    end
  end
  Soon()
end)

-- ------------------------------------------------------------ slash
local OPTS = { accept = "autoAccept", handin = "autoTurnin", turnin = "autoTurnin", reward = "smartReward", off = "offRoute",
               banner = "banner", corpse = "corpse", tips = "levelTips", trail = "trail",
               friends = "friends", trainers = "trainers", taken = "tapWarn", professions = "professions",
               compact = "compact", bold = "boldMarkers" }

SLASH_REALMPATH1 = "/path"
SLASH_REALMPATH2 = "/rp"
SlashCmdList["REALMPATH"] = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  if not O then return end
  if Path.SlashExtra and Path.SlashExtra(cmd, rest) then return end
  if cmd == "" or cmd == "window" then
    if Path.Window then Path.Window.Toggle() end
  elseif cmd == "hud" or cmd == "compass" then
    O.hud = not O.hud; Path.UpdateHUD(); Print("compass " .. (O.hud and "on" or "off"))
  elseif cmd == "panel" then O.panel = not O.panel; Path.UpdateHUD()
  elseif cmd == "skip" then Path.Skip()
  elseif cmd == "back" then Path.Back()
  elseif cmd == "chapter" or cmd == "nextzone" then Path.SkipChapter()
  elseif cmd == "unlock" then O.locked = false; Print("drag the compass to move it, /path lock to fix it again")
  elseif cmd == "lock" then O.locked = true; Print("compass locked")
  elseif cmd == "reset" then S.skip = {}; S.trainedAt = 0; S.trainSkip = 0; Path.Changed(true); Print("skipped steps cleared")
  elseif cmd == "width" then
    local n = tonumber(rest)
    if n then O.compassWidth = math.max(300, math.min(1000, n)); Path.UpdateHUD() end
  elseif cmd == "trainer" then if Path.PointTrainer then Path.PointTrainer() end
  elseif OPTS[cmd] then
    local k = OPTS[cmd]; O[k] = not O[k]; Print(cmd .. (O[k] and " on" or " off")); Path.Changed(true)
  else
    Print("/path (window)  skip  back  chapter  trainer  compass  panel  lock/unlock  width <n>  reset  follow <name>  target")
    Print("toggles: accept handin reward off banner corpse tips trail friends trainers taken professions")
    Print("professions: /path professions pick | set <a> <b> | none | extra | status | stop")
  end
end
