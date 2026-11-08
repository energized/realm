-- Realm: gathering node memory. Forever ships no node database, so this learns herbs and ore
-- from your own gathering (like GatherMate) and the tracker draws them. Per-kind toggles.
local ADDON, ns = ...
local G = {}
ns.Gather = G

local KINDS = {
  herb = { label = "Herbs", short = "Herb", spells = { 2366 }, color = { .3, 1, .3 } },
  ore = { label = "Ore", short = "Ore", spells = { 2575 }, color = { 1, .65, .2 } },
  fish = { label = "Fishing spots", short = "Fish", spells = { 7620 }, color = { .3, .7, 1 } },
  chest = { label = "Chests and lockboxes", short = "Chest", spells = { 3365, 6478, 6477 }, color = { 1, .9, .2 } },
}
local ORDER = { "herb", "ore", "fish", "chest" }
local MAXPER = 400
local DB
local pending, kindByName = {}, nil

local function SpellName(id)
  if C_Spell and C_Spell.GetSpellName then
    local ok, n = pcall(C_Spell.GetSpellName, id)
    if ok and type(n) == "string" then return n end
  end
  if GetSpellInfo then
    local ok, n = pcall(GetSpellInfo, id)
    if ok and type(n) == "string" then return n end
  end
end

local function KindOfSpell(id)
  if not kindByName then
    kindByName = {}
    for k, v in pairs(KINDS) do
      for _, sid in ipairs(v.spells) do
        local n = SpellName(sid)
        if n then kindByName[n] = k end
      end
    end
  end
  local n = id and SpellName(id)
  return n and kindByName[n]
end

local function Setup()
  DB = ns.DB
  if not DB then return end
  DB.gather = DB.gather or {}
  for _, k in ipairs(ORDER) do
    if DB.gather[k] == nil then DB.gather[k] = true end
  end
  DB.nodes = DB.nodes or {}
end

function G.Color(kind) return KINDS[kind] and KINDS[kind].color or { 1, 1, 1 } end
function G.Order() return ORDER end
function G.Short(kind) return KINDS[kind] and KINDS[kind].short or kind end

-- from: the party member who reported it (nil = found by me). A node already saved at that spot is ignored.
function G.Record(kind, name, map, x, y, from)
  if not (DB and KINDS[kind] and map and x and y) then return false end
  local list = DB.nodes[map]
  if not list then list = {}; DB.nodes[map] = list end
  for _, n in ipairs(list) do
    if n.k == kind and n.n == name and math.abs(n.x - x) < 0.003 and math.abs(n.y - y) < 0.003 then return false end
  end
  if #list >= MAXPER then table.remove(list, 1) end
  list[#list + 1] = { k = kind, n = name or "?", x = x, y = y, s = from }
  return true
end

function G.IsKind(kind) return KINDS[kind] ~= nil end

-- nodes on this map whose kind is switched on
function G.Visible(map)
  local out = {}
  local list = DB and DB.nodes and DB.nodes[map]
  if not list then return out end
  for _, n in ipairs(list) do
    if DB.gather[n.k] then out[#out + 1] = n end
  end
  return out
end

function G.Enabled(kind) return DB and DB.gather and DB.gather[kind] and true or false end
function G.AnyOn()
  for _, k in ipairs(ORDER) do if G.Enabled(k) then return true end end
  return false
end

function G.Toggle(kind)
  if not (DB and KINDS[kind]) then return end
  DB.gather[kind] = not DB.gather[kind]
  ns.Print(KINDS[kind].label .. " on the tracker map: " .. (DB.gather[kind] and "|cff00ff00on|r" or "|cffff4040off|r"))
end

function G.SetAll(on)
  if not DB then return end
  for _, k in ipairs(ORDER) do DB.gather[k] = on end
  ns.Print("Gathering nodes on the tracker map: " .. (on and "|cff00ff00on|r" or "|cffff4040off|r"))
end

function G.Count()
  local c = {}
  for _, k in ipairs(ORDER) do c[k] = 0 end
  for _, list in pairs(DB and DB.nodes or {}) do
    for _, n in ipairs(list) do c[n.k] = (c[n.k] or 0) + 1 end
  end
  return c
end

function G.Command(arg)
  arg = (arg or ""):lower()
  if arg == "herb" or arg == "herbs" then G.Toggle("herb")
  elseif arg == "ore" or arg == "mining" then G.Toggle("ore")
  elseif arg == "fish" or arg == "fishing" then G.Toggle("fish")
  elseif arg == "chest" or arg == "chests" or arg == "treasure" then G.Toggle("chest")
  elseif arg == "on" then G.SetAll(true)
  elseif arg == "off" then G.SetAll(false)
  elseif arg == "clear" then
    if DB then DB.nodes = {} end
    ns.Print("Saved gathering nodes cleared.")
  else
    local c = G.Count()
    for _, k in ipairs(ORDER) do
      ns.Print(("%s: %d saved, %s"):format(KINDS[k].label, c[k], G.Enabled(k) and "shown" or "hidden"))
    end
    ns.Print("/realm nodes herb | ore | fish | chest | on | off | clear   (learned as you gather)")
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("UNIT_SPELLCAST_SENT")
ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
ev:RegisterEvent("UNIT_SPELLCAST_FAILED")
ev:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
ev:SetScript("OnEvent", function(_, event, unit, a2, a3, a4)
  if event == "PLAYER_LOGIN" then Setup() return end
  if unit ~= "player" or not DB then return end
  if event == "UNIT_SPELLCAST_SENT" then
    -- unit, target, castGUID, spellID
    local kind = KindOfSpell(a4)
    if kind then pending[a3] = { kind = kind, name = a2 } end
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    -- unit, castGUID, spellID
    local p = pending[a2]
    if not p then return end
    pending[a2] = nil
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return end
    local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or not map then return end
    local ok2, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not ok2 or not pos then return end
    local x, y = pos:GetXY()
    if x and y and not (x == 0 and y == 0) then
      -- a new find of mine is told to the party; a repeat is not
      if G.Record(p.kind, p.name, map, x, y) and ns.Tracker and ns.Tracker.ShareNode then
        pcall(ns.Tracker.ShareNode, p.kind, p.name, map, x, y)
      end
    end
  else
    pending[a2] = nil
  end
end)
