-- Realm Path: professions helper.
--  * a new character is offered the common profession pairings for its class
--  * the route points at a trainer for each pick when one is on the way
--  * a gathering profession that has fallen behind the zone you advanced to gets a suggested detour to a nearby
--    spot (by flight master when it is far), and the compass returns to the route once the skill is high enough
-- Everything here can be switched off with /path professions.
local ADDON, ns = ...
local Path = ns.Path
local UI = ns.UI
local Prof = {}
Path.Prof = Prof

local GATHER = { Mining = true, Herbalism = true }       -- professions that have gathering spots in ProfData
local PRIMARY = { "Mining", "Herbalism", "Skinning", "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring" }
local SECONDARY = { "First Aid", "Cooking", "Fishing" }
local SKILLID = { [171] = "Alchemy", [164] = "Blacksmithing", [333] = "Enchanting", [202] = "Engineering", [182] = "Herbalism",
                  [165] = "Leatherworking", [186] = "Mining", [393] = "Skinning", [197] = "Tailoring",
                  [185] = "Cooking", [129] = "First Aid", [356] = "Fishing" }
local LOWER = {}
for _, n in ipairs(PRIMARY) do LOWER[n:lower()] = n end
for _, n in ipairs(SECONDARY) do LOWER[n:lower()] = n end
for k, v in pairs({ mine = "Mining", miner = "Mining", herb = "Herbalism", herbalist = "Herbalism", skin = "Skinning",
                    alch = "Alchemy", blacksmith = "Blacksmithing", smith = "Blacksmithing", enchant = "Enchanting",
                    engineer = "Engineering", leather = "Leatherworking", tailor = "Tailoring", firstaid = "First Aid",
                    fish = "Fishing", cook = "Cooking" }) do LOWER[k] = v end
local function Canon(name) if name == nil then return nil end return LOWER[tostring(name):lower()] end
Prof.Canon = Canon

-- Commonly chosen pairings per class (community convention, not measured usage).
Prof.COMBOS = {
  WARRIOR = { { "Mining", "Blacksmithing", "Make your own weapons and armor from the ore you mine." },
              { "Mining", "Engineering", "Strong early gold and handy gadgets." },
              { "Herbalism", "Alchemy", "Your own potions, and herbs sell well." } },
  PALADIN = { { "Mining", "Blacksmithing", "Plate and weapons for yourself." },
              { "Herbalism", "Alchemy", "Potions and a steady herb income." },
              { "Mining", "Engineering", "Gadgets and gold from ore." } },
  HUNTER  = { { "Skinning", "Leatherworking", "Skin what you kill, craft leather and mail." },
              { "Mining", "Engineering", "Scopes, ammo and gadgets." },
              { "Herbalism", "Alchemy", "Potions and herb income." } },
  ROGUE   = { { "Skinning", "Leatherworking", "Leather gear from your own kills." },
              { "Mining", "Engineering", "Gadgets and gold from ore." },
              { "Herbalism", "Alchemy", "Potions and herb income." } },
  PRIEST  = { { "Tailoring", "Enchanting", "Cloth gear, and enchants for it." },
              { "Herbalism", "Alchemy", "Potions and herb income." },
              { "Mining", "Engineering", "Gadgets and gold from ore." } },
  SHAMAN  = { { "Skinning", "Leatherworking", "Leather and mail you can wear." },
              { "Herbalism", "Alchemy", "Potions and herb income." },
              { "Mining", "Blacksmithing", "Weapons and armor from your own ore." } },
  MAGE    = { { "Tailoring", "Enchanting", "Cloth gear, and enchants for it." },
              { "Mining", "Engineering", "Gadgets and gold from ore." },
              { "Herbalism", "Alchemy", "Potions and herb income." } },
  WARLOCK = { { "Tailoring", "Enchanting", "Cloth gear, and enchants for it." },
              { "Herbalism", "Alchemy", "Potions and herb income." },
              { "Mining", "Engineering", "Gadgets and gold from ore." } },
  DRUID   = { { "Herbalism", "Alchemy", "Potions and herb income." },
              { "Skinning", "Leatherworking", "Leather gear from your own kills." },
              { "Tailoring", "Enchanting", "Cloth to sell, and enchants." } },
}

local RADIUS = 650        -- yards: a trainer this close counts as "on the way"
local FAR = 900           -- yards: a gathering spot farther than this is reached by flight master when one is near
local BEHIND = 15         -- skill points behind the zone's pace before it is worth a suggestion

local function Print(m) Path.Print(m) end
local function Faction()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  return f == "Horde" and "H" or "A"
end
local function MapName(m)
  local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
  return (info and info.name) or ("map " .. tostring(m))
end
local function State() return Path.State and Path.State() end
local function On()
  local O = Path.Opts()
  return O and O.professions ~= false and O.professions
end

-- ------------------------------------------------------------ what the character knows
function Prof.Known()
  local out = {}
  local function add(name, rank, maxr)
    local c = Canon(name)
    if c then out[c] = { rank = tonumber(rank) or 0, max = tonumber(maxr) or 0 } end
  end
  if GetProfessions and GetProfessionInfo then
    local ok, a, b, c, d, e = pcall(GetProfessions)
    if ok then
      for _, idx in ipairs({ a, b, c, d, e }) do
        if idx then
          local ok2, name, _, rank, maxr, _, _, line = pcall(GetProfessionInfo, idx)
          if ok2 then add(SKILLID[line] or name, rank, maxr) end
        end
      end
    end
  end
  if next(out) == nil and GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, header, _, rank, _, _, maxr = GetSkillLineInfo(i)
      if name and not header then add(name, rank, maxr) end
    end
  end
  return out
end

-- ------------------------------------------------------------ geometry helpers
local function Dist(m1, x1, y1, m2, x2, y2)
  if not Path.WorldPoint then return nil end
  local c1, ax, ay = Path.WorldPoint(m1, x1, y1)
  local c2, bx, by = Path.WorldPoint(m2, x2, y2)
  if not c1 or c1 ~= c2 then return nil end
  return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

local function NearestTrainer(name)
  local best, bd
  local fac = Faction()
  for _, t in ipairs((ns.ProfTrainers and ns.ProfTrainers[name]) or {}) do
    if t.f == "AH" or t.f == fac then
      local b, d = Path.Vector(t.m, t.x, t.y)
      if b and (not bd or d < bd) then best, bd = t, d end
    end
  end
  return best, bd
end

-- ------------------------------------------------------------ profession choices
local function Wanted()
  local S = State()
  local P = S and S.prof
  local out = {}
  if not P then return out end
  for _, n in ipairs(P.want or {}) do out[#out + 1] = n end
  if P.extra then for _, n in ipairs(SECONDARY) do out[#out + 1] = n end end
  return out
end

function Prof.Choose(list, extra)
  local S = State()
  if not S then return end
  local want = {}
  for _, n in ipairs(list or {}) do local c = Canon(n); if c then want[#want + 1] = c end end
  S.prof = { want = want, extra = extra ~= false and #want > 0, done = {}, skip = {} }
  S.profAsked = true
  if #want == 0 then
    Print("professions: no picks. I will not point you at profession trainers. (/path professions pick to choose later)")
  else
    Print("professions: " .. table.concat(want, " + ") .. (S.prof.extra and " (and First Aid, Cooking, Fishing)" or "") ..
          ". The compass will point at a trainer when one is on your way.")
    for _, n in ipairs(Wanted()) do
      local have = ns.ProfTrainers and ns.ProfTrainers[n] and #ns.ProfTrainers[n] > 0
      if not have then Print(("no %s trainer location in my data: find one in a major city."):format(n)) end
    end
  end
  Path.Changed(true)
end

-- the trainer stop for a pick that is not learned yet
function Prof.LearnStop()
  if not On() then return nil end
  local S = State()
  local P = S and S.prof
  if not P then return nil end
  local known = Prof.Known()
  local best, bd, bp
  for _, name in ipairs(Wanted()) do
    if not known[name] and not (P.skip and P.skip[name]) then
      local t, d = NearestTrainer(name)
      if t and d <= RADIUS and (not bd or d < bd) then best, bd, bp = t, d, name end
    end
  end
  if not best then return nil end
  return { t = "R", n = "Learn " .. bp, npc = best.n, m = best.m, p = { best.x, best.y },
           tx = ("%s teaches %s. /path skip to put it off."):format(best.n, bp), virtual = true, prof = bp,
           verb = "LEARN PROFESSION" }, bd
end

-- ------------------------------------------------------------ pace and gathering spots
function Prof.Need()
  local _, _, chapters = Path.Route()
  local s = Path.RealStep and Path.RealStep()
  local c = s and chapters and chapters[s.ch]
  if c and c.skill then return c.skill, c.name, s.ch end
  local lvl = Path.Level()
  local cap = lvl < 10 and 75 or lvl < 20 and 150 or lvl < 35 and 225 or 300
  return math.min(lvl * 5, cap), c and c.name, s and s.ch or 0
end

function Prof.FindSpot(name, skill)
  local best, bs
  local lvl = Path.Level()
  for _, e in ipairs((ns.ProfSpots and ns.ProfSpots[name]) or {}) do
    if e.req <= skill and (not e.lv or e.lv <= lvl + 2) then
      local b, d = Path.Vector(e.m, e.x, e.y)
      if b then
        local sc = d + 40 * (skill - e.req)       -- close wins, and a node near your skill beats a trivial one
        if not bs or sc < bs then best, bs = e, sc end
      end
    end
  end
  return best
end

local function NearestFlight(m, x, y, fromPlayer)
  local best, bd
  local fac = Faction()
  for _, t in ipairs(ns.FlightMasters or {}) do
    if t.f == "AH" or t.f == fac then
      local d
      if fromPlayer then local b, dd = Path.Vector(t.m, t.x, t.y); d = b and dd
      else d = Dist(t.m, t.x, t.y, m, x, y) end
      if d and (not bd or d < bd) then best, bd = t, d end
    end
  end
  return best, bd
end

-- A leveling detour holds one or more professions: S.profDetour = { items = { { prof, target, m, x, y, node, zone }, ... } }.
-- A detour saved by an older version has those fields on the detour itself, so it is wrapped into one item.
local function Norm(D)
  if D and not D.items then
    D.items = { { prof = D.prof, target = D.target, m = D.m, x = D.x, y = D.y, node = D.node, zone = D.zone } }
  end
  return D
end
local function RankOf(known, name) local k = known[name]; return k and k.rank or 0 end
local function Names(list)
  local out = {}
  for _, it in ipairs(list) do out[#out + 1] = it.prof end
  return table.concat(out, " + ")
end

-- the step the compass shows while a leveling detour is active
function Prof.DetourStep()
  if not On() then return nil end
  local S = State()
  local D = Norm(S and S.profDetour)
  if not D then return nil end
  local known = Prof.Known()
  local left, lines = {}, {}
  for _, it in ipairs(D.items) do
    local r = RankOf(known, it.prof)
    if r >= it.target then
      lines[#lines + 1] = ("%s%s %d/%d  done|r"):format(UI.H.good, it.prof, r, it.target)
    else
      lines[#lines + 1] = ("%s%s %d/%d|r"):format(UI.H.cream, it.prof, r, it.target)
      left[#left + 1] = it
    end
  end
  local act = left[1]
  if not act then return nil end                   -- everything is done: the compass is back on the route
  local skills = table.concat(lines, "      ")        -- drawn large by the compass panel, not in the small step text
  local b, dist = Path.Vector(act.m, act.x, act.y)
  if b and dist > FAR then
    local here, hd = NearestFlight(nil, nil, nil, true)
    local there = NearestFlight(act.m, act.x, act.y, false)
    if here and there and hd <= FAR and (here.n ~= there.n or here.m ~= there.m) then
      return { t = "G", n = "Fly toward " .. (act.zone or "the spot"), npc = here.n, m = here.m, p = { here.x, here.y },
               tx = ("Take the flight path toward %s to level %s. /path skip cancels the detour."):format(act.zone or "the spot", act.prof),
               skills = skills,
               virtual = true, detour = true, verb = "FLIGHT PATH" }
    end
  end
  local title = (#left == 1) and ("Level %s to %d"):format(act.prof, act.target) or ("Level " .. Names(left))
  local after = left[2] and ("the compass moves on to " .. left[2].prof) or "the compass returns to your route"
  return { t = "L", n = title, npc = act.node, m = act.m, p = { act.x, act.y },
           tx = ("Gather %s here until %s reaches %d, then %s. /path skip cancels."):format(act.node, act.prof, act.target, after),
           skills = skills,
           virtual = true, detour = true, verb = "LEVEL PROFESSION" }
end

function Prof.Current()
  local d = Prof.DetourStep()
  if d then return d end
  return Prof.LearnStop()
end

function Prof.Skip()
  local S = State()
  if not S then return false end
  if S.profDetour then
    Print(("detour for %s cancelled."):format(Names(Norm(S.profDetour).items))); S.profDetour = nil
    return true
  end
  local step = Prof.LearnStop()
  if step and S.prof then
    S.prof.skip = S.prof.skip or {}
    S.prof.skip[step.prof] = true
    Print(("%s put off. /path professions pick to choose again."):format(step.prof))
    return true
  end
  return false
end

-- ------------------------------------------------------------ prompt window
local pf
local ShowPrompt
local function BuildPrompt()
  pf = CreateFrame("Frame", "RealmPathProf", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  pf:SetSize(460, 200); pf:SetPoint("CENTER", 0, 120); pf:SetFrameStrata("DIALOG")
  pf:SetMovable(true); pf:EnableMouse(true); pf:RegisterForDrag("LeftButton"); pf:SetClampedToScreen(true)
  pf:SetScript("OnDragStart", pf.StartMoving); pf:SetScript("OnDragStop", pf.StopMovingOrSizing)
  UI.Skin(pf)
  if UISpecialFrames then table.insert(UISpecialFrames, "RealmPathProf") end
  pf.title = pf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); pf.title:SetPoint("TOPLEFT", 16, -14)
  pf.body = pf:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  pf.body:SetPoint("TOPLEFT", 16, -44); pf.body:SetWidth(428); pf.body:SetJustifyH("LEFT")
  pf.btns = {}
end

ShowPrompt = function(title, text, buttons)
  if InCombatLockdown and InCombatLockdown() then
    C_Timer.After(5, function() ShowPrompt(title, text, buttons) end)
    return
  end
  if not pf then BuildPrompt() end
  pf.title:SetText(UI.H.gold .. title .. "|r")
  pf.body:SetText(text)
  local bh = (pf.body.GetStringHeight and pf.body:GetStringHeight()) or 40
  local y = -(52 + bh)
  for i, def in ipairs(buttons) do
    local b = pf.btns[i]
    if not b then
      b = CreateFrame("Button", nil, pf)
      b:SetSize(428, 28); UI.Button(b)
      b.t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.t:SetPoint("LEFT", 8, 0); b.t:SetWidth(412); b.t:SetJustifyH("LEFT")
      pf.btns[i] = b
    end
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", 16, y)
    b.t:SetText(def.label)
    b:SetScript("OnClick", function() pf:Hide(); if def.fn then def.fn() end end)
    b:Show()
    y = y - 32
  end
  for i = #buttons + 1, #pf.btns do pf.btns[i]:Hide() end
  pf:SetHeight(-y + 16)
  pf:Show()
end
Prof.ShowPrompt = ShowPrompt

function Prof.OpenPicker()
  local _, class = UnitClass("player")
  local combos = class and Prof.COMBOS[class]
  if not combos then Print("no profession pairings for your class in my list. Use /path professions set <name> <name>.") return end
  local cname = class:sub(1, 1) .. class:sub(2):lower()
  local text = "Common pairings for a " .. cname .. " (a community convention, not usage statistics). " ..
               "Pick one and the compass will stop at a trainer when one is on your way. First Aid, Cooking and Fishing are added unless you turn that off with /path professions extra."
  local btns = {}
  for _, c in ipairs(combos) do
    btns[#btns + 1] = { label = ("%s + %s  -  %s"):format(c[1], c[2], c[3]), fn = function() Prof.Choose({ c[1], c[2] }) end }
  end
  btns[#btns + 1] = { label = "No professions for now", fn = function() Prof.Choose({}) end }
  btns[#btns + 1] = { label = "Ask me later (/path professions pick)", fn = function() local S = State(); if S then S.profAsked = true end end }
  ShowPrompt("Choose your professions", text, btns)
end

-- ------------------------------------------------------------ the pace check
-- one detour item for a profession that has fallen behind, or nil (with a chat line saying why)
local function Plan(name, k, need, zone)
  local target = need
  if k.max and k.max > 0 and k.max < need then target = k.max end
  if k.max and k.max > 0 and k.rank >= k.max then
    Print(("%s is %d, which is the most your current rank allows. %s is paced for about %d: train the next rank at a %s trainer when your level allows."):format(name, k.rank, zone or "This zone", need, name))
    return nil
  end
  local spot = Prof.FindSpot(name, k.rank)
  if not spot then
    Print(("%s is %d and %s is paced for about %d, but I have no gathering spot for it on this continent at your level. Level it where you can, or turn this off with /path professions."):format(name, k.rank, zone or "this zone", need))
    return nil
  end
  local where = MapName(spot.m)
  Print(("%s is %d and %s is paced for about %d. Closest place to level it: %s in %s."):format(name, k.rank, zone or "this zone", need, spot.node, where))
  return { prof = name, rank = k.rank, target = target, m = spot.m, x = spot.x, y = spot.y, node = spot.node, zone = where }
end

-- put the items on the detour; a profession already listed is replaced by its new item
local function Accept(S, cand)
  local D = Norm(S.profDetour)
  local keep = {}
  for _, it in ipairs(D and D.items or {}) do
    local replaced = false
    for _, c in ipairs(cand) do if c.prof == it.prof then replaced = true end end
    if not replaced then keep[#keep + 1] = it end
  end
  for _, c in ipairs(cand) do keep[#keep + 1] = c end
  S.profDetour = { items = keep }
  Path.Changed(true)
end

-- one prompt for every profession that is behind, so two of them share one detour
local function Offer(S, cand, need, zone)
  local adding = S.profDetour ~= nil
  local text
  if #cand == 1 then
    local c = cand[1]
    text = ("%s is %d. %s is paced for about %d.\n\nClosest place to level it: %s in %s. Route there until %s reaches %d, then back to the quest route?"):format(c.prof, c.rank, zone or "This zone", need, c.node, c.zone, c.prof, c.target)
    if adding then text = text .. " It will be added to the detour you already have." end
  else
    local parts, spots = {}, {}
    for _, c in ipairs(cand) do
      parts[#parts + 1] = ("%s is %d"):format(c.prof, c.rank)
      spots[#spots + 1] = ("%s in %s (%s)"):format(c.node, c.zone, c.prof)
    end
    text = ("%s. %s is paced for about %d.\n\nClosest places: %s. One window will track each skill and turn a finished one green. Route there until all reach their goal, then back to the quest route?"):format(table.concat(parts, ", "), zone or "This zone", need, table.concat(spots, "; "))
  end
  ShowPrompt("Level your " .. Names(cand), text,
    { { label = adding and "Add to my route" or "Route me there", fn = function() Accept(S, cand) end },
      { label = "Not now", fn = function() end } })
end

local checking
function Prof.Check()
  if checking or not On() then return end
  local S = State()
  if not S then return end
  checking = true
  local ok, err = pcall(function()
    local lvl = Path.Level()
    -- a new character is offered the picker once
    if not S.prof and not S.profAsked and lvl <= 5 then
      S.profAsked = true
      Prof.OpenPicker()
      return
    end
    local known = Prof.Known()
    local D = Norm(S.profDetour)
    if D then
      -- a finished profession stays on the list (shown green) until every one is done
      local open = 0
      for _, it in ipairs(D.items) do
        local r = RankOf(known, it.prof)
        if r >= it.target then
          if not it.done then
            it.done = true
            local rest
            for _, o in ipairs(D.items) do
              if not o.done and RankOf(known, o.prof) < o.target then rest = rest or o.prof end
            end
            Print(("%s is now %d.%s"):format(it.prof, r, rest and (" Next: " .. rest .. ".") or " Back to the route."))
          end
        else
          open = open + 1
        end
      end
      if open == 0 then S.profDetour = nil; return end
    end
    local need, zone, ch = Prof.Need()
    S.profAdvised = S.profAdvised or {}
    local cand = {}
    for _, name in ipairs(PRIMARY) do
      local k = GATHER[name] and known[name]
      local listed = false
      if S.profDetour then
        for _, it in ipairs(S.profDetour.items) do
          if it.prof == name then listed = true end        -- a finished one is not offered again until the detour ends
        end
      end
      if k and need and not listed and k.rank + BEHIND <= need then
        local key = name .. ":" .. tostring(ch)
        if not S.profAdvised[key] then
          S.profAdvised[key] = true
          local item = Plan(name, k, need, zone)
          if item then cand[#cand + 1] = item end
        end
      end
    end
    if #cand > 0 then Offer(S, cand, need, zone) end
  end)
  checking = false
  if not ok then Print("professions check failed: " .. tostring(err)) end
end

function Prof.Status()
  local S = State()
  local P = S and S.prof
  local known = Prof.Known()
  local need, zone = Prof.Need()
  Print("professions " .. (On() and "on" or "off") .. ". Picks: " .. ((P and #P.want > 0) and table.concat(P.want, " + ") or "none") ..
        (P and P.extra and " (+ First Aid, Cooking, Fishing)" or ""))
  for _, name in ipairs(Wanted()) do
    local k = known[name]
    Print(("  %s: %s"):format(name, k and ("%d/%d"):format(k.rank, k.max) or "not learned"))
  end
  Print(("  this zone (%s) is paced for about %d"):format(zone or "?", need or 0))
  if S and S.profDetour then
    for _, it in ipairs(Norm(S.profDetour).items) do
      Print(("  detour active: %s %d/%d"):format(it.prof, RankOf(known, it.prof), it.target))
    end
  end
end

-- ------------------------------------------------------------ slash and events
local prev = Path.SlashExtra
Path.SlashExtra = function(cmd, rest)
  if cmd == "professions" or cmd == "prof" then
    rest = rest or ""
    if rest == "" and cmd == "professions" then return false end        -- plain toggle is handled by Path
    local sub, arg = rest:match("^(%S*)%s*(.-)$")
    local S = State()
    if rest == "" or sub == "status" then Prof.Status()
    elseif sub == "pick" or sub == "choose" then Prof.OpenPicker()
    elseif sub == "none" then Prof.Choose({})
    elseif sub == "set" then
      local list = {}
      for w in arg:gmatch("%S+") do local c = Canon(w); if c then list[#list + 1] = c end end
      if #list == 0 then Print("usage: /path professions set mining herbalism") else Prof.Choose(list) end
    elseif sub == "extra" then
      if S and S.prof then S.prof.extra = not S.prof.extra; Print("First Aid, Cooking, Fishing: " .. (S.prof.extra and "on" or "off")); Path.Changed(true)
      else Print("pick your professions first: /path professions pick") end
    elseif sub == "stop" then Prof.Skip()
    else Print("/path professions  (toggle)   pick  set <a> <b>  none  extra  status  stop") end
    return true
  end
  if prev then return prev(cmd, rest) end
end

local ev = CreateFrame("Frame")
local pending
for _, e in ipairs({ "SKILL_LINES_CHANGED", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function()
  if pending then return end
  pending = true
  C_Timer.After(0.6, function() pending = false; if Path.Opts() then Path.Changed() end end)
end)

Path.OnChange(function() Prof.Check() end)
Path.ProfCurrent = Prof.Current
Path.ProfSkip = Prof.Skip
