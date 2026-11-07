-- Realm Travel: when the route target is in a zone you are not in, say how to get there
-- (walk, Deeprun Tram, boat, zeppelin, flight master). Built on a small table of zone links.
local ADDON, ns = ...
local Path = ns.Path
if not Path then return end

local NAME = {
  [1426] = "Dun Morogh", [1429] = "Elwynn Forest", [1431] = "Duskwood", [1432] = "Loch Modan",
  [1433] = "Redridge Mountains", [1436] = "Westfall", [1437] = "Wetlands", [1417] = "Arathi Highlands",
  [1424] = "Hillsbrad Foothills", [1420] = "Tirisfal Glades", [1421] = "Silverpine Forest",
  [1411] = "Durotar", [1412] = "Mulgore", [1413] = "The Barrens", [1438] = "Teldrassil",
  [1439] = "Darkshore", [1440] = "Ashenvale", [1442] = "Stonetalon Mountains",
  [1453] = "Stormwind City", [1455] = "Ironforge", [1454] = "Orgrimmar", [1456] = "Thunder Bluff",
  [1457] = "Darnassus", [1458] = "Undercity",
}
Path.TravelNames = NAME

-- { zoneA, zoneB, how, text A->B, text B->A, faction }   how: walk, tram, boat, zep, fly
-- Text is optional for walking. Flights only help when you have already found that flight master.
local LINKS = {
  -- Alliance, Eastern Kingdoms
  { 1426, 1455, "walk", "Walk into Ironforge through the main gate.", "Leave Ironforge by the main gate into Dun Morogh.", "A" },
  { 1426, 1432, "walk", "Take the road east out of Dun Morogh, through the tunnel into Loch Modan.", "Take the road west out of Loch Modan, through the tunnel into Dun Morogh.", "A" },
  { 1432, 1437, "walk", "Take the road north out of Loch Modan into the Wetlands.", "Take the road south out of the Wetlands into Loch Modan.", "A" },
  { 1437, 1417, "walk", nil, nil, "A" },
  { 1417, 1424, "walk" },
  { 1455, 1453, "tram", "Enter the Deeprun Tram in Ironforge and ride it to Stormwind.", "Enter the Deeprun Tram in Stormwind's Dwarven District and ride it to Ironforge.", "A" },
  { 1453, 1429, "walk", "Leave Stormwind by the main gate into Elwynn Forest.", "Walk north into Stormwind City.", "A" },
  { 1429, 1433, "walk", "Take the road east from Goldshire toward Lakeshire in Redridge.", "Take the road west out of Redridge into Elwynn Forest.", "A" },
  { 1429, 1436, "walk", nil, nil, "A" },
  { 1429, 1431, "walk", "Take the road south from Goldshire into Duskwood.", "Take the road north out of Duskwood into Elwynn Forest.", "A" },
  { 1433, 1431, "walk", "Head south from Lakeshire along the road into Duskwood.", "Head north from Darkshire along the road into Redridge.", "A" },
  { 1436, 1431, "walk", nil, nil, "A" },
  { 1455, 1453, "fly", "Fly from Ironforge to Stormwind (only if you already know both flight masters).", "Fly from Stormwind to Ironforge (only if you already know both flight masters).", "A" },
  { 1455, 1432, "fly", "Fly from Ironforge to Thelsamar in Loch Modan (only if you already know it).", "Fly from Thelsamar to Ironforge (only if you already know it).", "A" },
  { 1455, 1437, "fly", "Fly from Ironforge to Menethil Harbor in the Wetlands (only if you already know it).", "Fly from Menethil Harbor to Ironforge (only if you already know it).", "A" },
  { 1453, 1433, "fly", "Fly from Stormwind to Lakeshire in Redridge (only if you already know it).", "Fly from Lakeshire to Stormwind (only if you already know it).", "A" },
  { 1453, 1431, "fly", "Fly from Stormwind to Darkshire in Duskwood (only if you already know it).", "Fly from Darkshire to Stormwind (only if you already know it).", "A" },
  { 1453, 1436, "fly", "Fly from Stormwind to Sentinel Hill in Westfall (only if you already know it).", "Fly from Sentinel Hill to Stormwind (only if you already know it).", "A" },
  -- Alliance, Kalimdor
  { 1437, 1439, "boat", "Take the boat from Menethil Harbor in the Wetlands to Auberdine in Darkshore.", "Take the boat from Auberdine in Darkshore to Menethil Harbor in the Wetlands.", "A" },
  { 1439, 1438, "boat", "Take the boat from Auberdine to Rut'theran Village in Teldrassil.", "Take the boat from Rut'theran Village to Auberdine in Darkshore.", "A" },
  { 1438, 1457, "walk", "Climb the tree into Darnassus.", "Leave Darnassus down through Teldrassil.", "A" },
  { 1439, 1440, "walk", nil, nil, "A" },
  -- Horde, Kalimdor
  { 1411, 1454, "walk", "Walk into Orgrimmar through the front gate.", "Leave Orgrimmar by the front gate into Durotar.", "H" },
  { 1411, 1413, "walk", nil, nil, "H" },
  { 1454, 1413, "walk", "Leave Orgrimmar by the back gate and follow the road to the Barrens.", "Follow the road to Orgrimmar and go in by the back gate.", "H" },
  { 1412, 1413, "walk", nil, nil, "H" },
  { 1412, 1456, "walk", "Walk up the lifts into Thunder Bluff.", "Take the lift down out of Thunder Bluff into Mulgore.", "H" },
  { 1413, 1442, "walk", nil, nil, "H" },
  { 1413, 1440, "walk", nil, nil, "H" },
  { 1442, 1440, "walk", nil, nil, "H" },
  { 1454, 1413, "fly", "Fly from Orgrimmar to the Crossroads in the Barrens (only if you already know it).", "Fly from the Crossroads to Orgrimmar (only if you already know it).", "H" },
  { 1413, 1456, "fly", "Fly from the Crossroads to Thunder Bluff (only if you already know both).", "Fly from Thunder Bluff to the Crossroads (only if you already know both).", "H" },
  { 1413, 1442, "fly", "Fly from the Crossroads to Sun Rock Retreat in Stonetalon (only if you already know it).", "Fly from Sun Rock Retreat to the Crossroads (only if you already know it).", "H" },
  { 1413, 1440, "fly", "Fly from the Crossroads to Splintertree Post in Ashenvale (only if you already know it).", "Fly from Splintertree Post to the Crossroads (only if you already know it).", "H" },
  -- Horde, Eastern Kingdoms
  { 1420, 1458, "walk", "Go down into Undercity.", "Leave Undercity up into Tirisfal Glades.", "H" },
  { 1420, 1421, "walk", nil, nil, "H" },
  { 1421, 1424, "walk", nil, nil, "H" },
  { 1411, 1420, "zep", "Take the zeppelin from the tower outside Orgrimmar to Undercity (you arrive in Tirisfal Glades).", "Take the zeppelin from the tower outside Undercity to Orgrimmar (you arrive in Durotar).", "H" },
  { 1458, 1421, "fly", "Fly from Undercity to the Sepulcher in Silverpine (only if you already know it).", "Fly from the Sepulcher to Undercity (only if you already know it).", "H" },
  { 1458, 1424, "fly", "Fly from Undercity to Tarren Mill in Hillsbrad (only if you already know it).", "Fly from Tarren Mill to Undercity (only if you already know it).", "H" },
}

local COST = { walk = 3, tram = 2, boat = 3, zep = 3, fly = 2 }
local LEG = { walk = "Walk", tram = "Take the Deeprun Tram", boat = "Take the boat", zep = "Take the zeppelin", fly = "Fly" }

local function Nm(m)
  if NAME[m] then return NAME[m] end
  if C_Map and C_Map.GetMapInfo then
    local ok, info = pcall(C_Map.GetMapInfo, m)
    if ok and info and info.name then return info.name end
  end
  return "zone " .. tostring(m)
end

local function Faction()
  return (UnitFactionGroup and UnitFactionGroup("player") == "Horde") and "H" or "A"
end

-- Flight masters you have found: filled in whenever you open a flight master's map (see the end of the file).
-- Stored per character as zone map ids.
local function Known()
  local S = Path.State and Path.State()
  return S and S.flights or {}
end
local function HasFlights() return next(Known()) ~= nil end

-- allowFly: true = any flight, a table of zone ids = only flights between zones in it, false/nil = none
local function LinkOK(l, allowFly)
  if l[3] ~= "fly" then return true end
  if allowFly == true then return true end
  if type(allowFly) == "table" then return allowFly[l[1]] and allowFly[l[2]] and true or false end
  return false
end

-- cheapest chain of links from one zone to another (small graph, so a plain Dijkstra will do)
local function Dijkstra(from, to, fac, allowFly)
  local adj = {}
  for _, l in ipairs(LINKS) do
    if (not l[6] or l[6] == fac) and LinkOK(l, allowFly) then
      adj[l[1]] = adj[l[1]] or {}; adj[l[2]] = adj[l[2]] or {}
      table.insert(adj[l[1]], { to = l[2], l = l, fwd = true })
      table.insert(adj[l[2]], { to = l[1], l = l, fwd = false })
    end
  end
  if not adj[from] or not adj[to] then return nil end
  local dist, prev, done = { [from] = 0 }, {}, {}
  while true do
    local u, ud
    for n, d in pairs(dist) do if not done[n] and (not ud or d < ud) then u, ud = n, d end end
    if not u then break end
    if u == to then break end
    done[u] = true
    for _, e in ipairs(adj[u] or {}) do
      local nd = ud + (COST[e.l[3]] or 3)
      if dist[e.to] == nil or nd < dist[e.to] then dist[e.to] = nd; prev[e.to] = { u, e } end
    end
  end
  if dist[to] == nil then return nil end
  local chain, n = {}, to
  while n ~= from do
    local p = prev[n]
    table.insert(chain, 1, { from = p[1], to = n, l = p[2].l, fwd = p[2].fwd })
    n = p[1]
  end
  return chain, dist[to]
end

local function StepText(c)
  local txt = c.fwd and c.l[4] or c.l[5]
  if txt and c.l[3] == "fly" then
    local k = Known()
    if k[c.l[1]] and k[c.l[2]] then txt = txt:gsub(" %(only if you already know[^)]*%)", "") end
  end
  if txt then return txt end
  return ("%s from %s to %s."):format(LEG[c.l[3]] or "Go", Nm(c.from), Nm(c.to))
end

local function Lines(chain)
  local out = {}
  for i, c in ipairs(chain) do out[i] = ("%d. %s"):format(i, StepText(c)) end
  return out
end

-- returns the fastest directions, and the directions that need no flight master (nil when they match)
function Path.TravelPlan(from, to)
  if not from or not to or from == to then return nil end
  local fac = Faction()
  -- once you have opened a flight master, only flights between towns you have found are used
  local fast = Dijkstra(from, to, fac, HasFlights() and Known() or true)
  if not fast then return nil end
  local walk = Dijkstra(from, to, fac, false)
  local usesFly = false
  for _, c in ipairs(fast) do if c.l[3] == "fly" then usesFly = true end end
  if HasFlights() then return Lines(fast), nil end
  return Lines(fast), (usesFly and walk) and Lines(walk) or nil
end

local function PlayerMap()
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
  if ok and type(m) == "number" then return m end
end

local function TargetMap()
  local t = Path.Target and Path.Target()
  return t and t.map, t and t.label
end

-- one line for the info panel, nil when you are already in the right zone or the way is unknown
function Path.TravelTip()
  local from = PlayerMap()
  local to = TargetMap()
  if not from or not to or from == to then return nil end
  local fast = Path.TravelPlan(from, to)
  if not fast then return nil end
  local more = #fast > 1 and ("  (+%d more, /path travel)"):format(#fast - 1) or ""
  return ("To %s: %s%s"):format(Nm(to), (fast[1]:gsub("^%d+%.%s*", "")), more)
end

local function PrintPlan(auto)
  local from = PlayerMap()
  local to, label = TargetMap()
  if not from or not to then
    if not auto then Path.Print("I need a target and your position first. Open the compass, then try again.") end
    return
  end
  if from == to then
    if not auto then Path.Print("you are already in " .. Nm(to) .. ".") end
    return
  end
  local fast, walk = Path.TravelPlan(from, to)
  if not fast then
    if not auto then Path.Print(("I don't have directions from %s to %s yet."):format(Nm(from), Nm(to))) end
    return
  end
  Path.Print(("from %s to %s%s:"):format(Nm(from), Nm(to), label and (" (" .. label .. ")") or ""))
  for _, l in ipairs(fast) do Path.Print(l) end
  if walk then
    Path.Print("if you have not found those flight masters, go this way instead:")
    for _, l in ipairs(walk) do Path.Print(l) end
  end
end
Path.PrintTravel = PrintPlan

-- tell the player once when a zone change leaves them away from the route
local told = {}
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "ZONE_CHANGED_NEW_AREA")
pcall(ev.RegisterEvent, ev, "PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function()
  C_Timer.After(2, function()
    local O = Path.Opts()
    if not O or O.travelTips == false then return end
    local from = PlayerMap()
    local to = TargetMap()
    if not from or not to or from == to then return end
    local key = from .. ">" .. to
    if told[key] then return end
    told[key] = true
    PrintPlan(true)
  end)
end)

local prev = Path.SlashExtra
Path.SlashExtra = function(cmd, rest)
  if cmd == "travel" or cmd == "way" or cmd == "directions" then
    if (rest or ""):match("^chat") then
      local O = Path.Opts()
      O.travelTips = (O.travelTips == false)
      Path.Print("travel tips in chat " .. (O.travelTips and "on" or "off"))
    else
      PrintPlan(false)
    end
    return true
  end
  if prev then return prev(cmd, rest) end
end

-- ------------------------------------------------------------ travel as route waypoints
-- While the route's next stop is in another zone, the compass aims at each leg in turn (the tram entrance,
-- the dock, the next zone) and moves on to the next leg when you arrive in the zone that leg leads to.
-- When the last leg is done the normal route takes over again. Legs avoid flight masters (Realm cannot tell
-- which ones you know); if you fly, the plan simply re-plans from wherever you land.
-- Points are map fractions and approximate: they only steer the compass, arrival is detected by zone.

-- a point in each zone to walk toward when the next leg is "walk into that zone"
local HUB = {
  [1426] = { .4772, .527 }, [1455] = { .5, .5 }, [1432] = { .3483, .4928 }, [1437] = { .10, .57 },
  [1417] = { .46, .47 }, [1424] = { .50, .57 }, [1453] = { .5, .5 }, [1429] = { .42, .65 },
  [1433] = { .1018, .7146 }, [1436] = { .56, .53 }, [1431] = { .7534, .4875 }, [1439] = { .37, .44 },
  [1438] = { .56, .59 }, [1457] = { .5, .5 }, [1440] = { .37, .50 }, [1411] = { .52, .43 },
  [1454] = { .5, .5 }, [1413] = { .52, .30 }, [1412] = { .47, .60 }, [1456] = { .5, .5 },
  [1442] = { .47, .60 }, [1420] = { .60, .52 }, [1458] = { .5, .5 }, [1421] = { .44, .40 },
}
-- where to stand in the zone you are leaving to take a tram, boat or zeppelin: "from>to"
local DOCK = {
  ["1455>1453"] = { .76, .51 }, ["1453>1455"] = { .63, .08 },
  ["1437>1439"] = { .05, .63 }, ["1439>1437"] = { .33, .43 },
  ["1439>1438"] = { .33, .43 }, ["1438>1439"] = { .56, .92 },
  ["1411>1420"] = { .50, .13 }, ["1420>1411"] = { .61, .59 },
}

local journey, planKey, planChain, lastIdx

-- Towns that have a flight master in our zone table, for the optional "pick up unknown flight masters" detour.
local FM = {}
for _, l in ipairs(LINKS) do
  if l[3] == "fly" then FM[l[1]] = true; FM[l[2]] = true end
end
local skipped = {}      -- zones where you chose to skip the detour (until /reload)

local function Short(c)
  local kind = c.l[3]
  if kind == "walk" then return "Go to " .. Nm(c.to) end
  return (LEG[kind] or "Go") .. " to " .. Nm(c.to)
end

-- the current leg as a compass target, or nil when no travel is needed
function Path.TravelTarget()
  local O = Path.Opts()
  if not O or O.travelGuide == false then return nil end
  local s = Path.Current and Path.Current()
  local to = s and s.m
  local from = PlayerMap()
  if not to or not from or from == to then journey, planKey, planChain, lastIdx = nil, nil, nil, nil return nil end
  if journey and journey.to ~= to then journey, lastIdx = nil, nil end
  local nk = 0
  for _ in pairs(Known()) do nk = nk + 1 end
  local key = from .. ">" .. to .. ":" .. nk
  if key ~= planKey then
    planKey = key
    -- flights are used only between flight masters you have found; nil in the tram or any zone not in the table
    planChain = Dijkstra(from, to, Faction(), Known())
  end
  local chain = planChain
  if not chain or #chain == 0 then return nil end      -- keep the journey: the tram ride has no zone of its own
  -- optional detour: you are in a town whose flight master you have not opened yet, so go and open it once.
  -- This is not a numbered travel step; the journey carries on afterwards.
  if O.discoverFlights and FM[from] and not Known()[from] and not skipped[from] and HUB[from] then
    local hp = HUB[from]
    return { kind = "travel", p = { hp[1], hp[2] }, m = from,
             title = "Find the flight master in " .. Nm(from),
             sub = "Optional detour: open its map once so Realm can route flights from here. /path flights skip to skip." }
  end
  if not journey then journey = { to = to, total = #chain, nk = nk } end
  -- you found a flight master mid-journey: the plan changed, so count the steps afresh
  if journey.nk ~= nk then journey.total, journey.nk, lastIdx = #chain, nk, nil end
  if #chain > journey.total then journey.total = #chain end
  local c = chain[1]
  local idx = journey.total - #chain + 1
  local dock = DOCK[c.from .. ">" .. c.to]
  local pt, map
  if dock then pt, map = dock, c.from
  elseif c.l[3] == "fly" then pt, map = HUB[c.from], c.from      -- the flight master is in town: aim at the town
  else pt, map = HUB[c.to], c.to end
  if lastIdx and idx > lastIdx then
    Path.Print(("travel step %d of %d: %s"):format(idx, journey.total, StepText(c)))
  end
  lastIdx = idx
  return { kind = "travel", p = pt and { pt[1], pt[2] } or {}, m = map,
           title = Short(c), sub = ("Step %d of %d.  %s"):format(idx, journey.total, StepText(c)),
           step = idx, total = journey.total }
end

-- ------------------------------------------------------------ remember the flight masters you have found
-- Opening a flight master's map lists every node with a type; CURRENT and REACHABLE ones are found.
-- Names look like "Town, Zone": match the town first, then the zone, against the zones in our table.
local function MatchZone(part)
  part = part and part:gsub("^%s+", ""):gsub("%s+$", ""):lower()
  if not part or part == "" then return nil end
  for id, nm in pairs(NAME) do
    local l = nm:lower()
    if l == part or l:find(part, 1, true) == 1 or part:find(l, 1, true) == 1 then return id end
  end
end

local tx = CreateFrame("Frame")
pcall(tx.RegisterEvent, tx, "TAXIMAP_OPENED")
tx:SetScript("OnEvent", function()
  local S = Path.State and Path.State()
  if not S or not NumTaxiNodes or not TaxiNodeName or not TaxiNodeGetType then return end
  S.flights = S.flights or {}
  local found = 0
  for i = 1, (NumTaxiNodes() or 0) do
    local ok, t = pcall(TaxiNodeGetType, i)
    if ok and (t == "CURRENT" or t == "REACHABLE") then
      local ok2, name = pcall(TaxiNodeName, i)
      if ok2 and type(name) == "string" then
        local town, zone = name:match("^(.-),%s*(.+)$")
        local id = MatchZone(town or name) or MatchZone(zone)
        if id and not S.flights[id] then S.flights[id] = true; found = found + 1 end
      end
    end
  end
  planKey = nil
  if found > 0 and Path.Changed then Path.Changed(true) end
end)

local prevTx = Path.SlashExtra
Path.SlashExtra = function(cmd, rest)
  if cmd == "flights" then
    local arg = ((rest or ""):match("^%s*(%S+)") or ""):lower()
    local O = Path.Opts()
    if arg == "detour" or arg == "on" or arg == "off" then
      if arg == "detour" then O.discoverFlights = not O.discoverFlights else O.discoverFlights = (arg == "on") end
      skipped = {}
      Path.Print("flight master detours " .. (O.discoverFlights and "on: I will point you at flight masters you have not opened yet" or "off"))
      if Path.Changed then Path.Changed(true) end
      return true
    elseif arg == "skip" then
      local m = PlayerMap()
      if m then skipped[m] = true; Path.Print("skipping the flight master in " .. Nm(m) .. " for now") end
      if Path.Changed then Path.Changed(true) end
      return true
    end
    local names = {}
    for id in pairs(Known()) do names[#names + 1] = Nm(id) end
    table.sort(names)
    Path.Print(#names > 0 and ("flight masters I have seen you find: " .. table.concat(names, ", ")) or
      "I have not seen you open a flight master yet. Talk to one and I will remember what you have found.")
    return true
  end
  if prevTx then return prevTx(cmd, rest) end
end
