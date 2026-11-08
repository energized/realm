-- Replay: records PvP encounters from the live combat log and keeps the last few.
-- Addons cannot read WoWCombatLog.txt, so this listens to the live events instead. It holds a short
-- rolling buffer and only turns it into a saved recording when a PvP encounter starts:
--   battleground / arena : from entering the match until it is over or you leave
--   open world           : from the first hostile player hit on you or your group until ~10s after the last one
-- Battlegrounds are NOT recorded (energizedGG, 2026-11-08): this is for open-world encounters and ganks.
-- Once an open-world fight is running it also keeps other players nearby who fight each other (a 1v1 that
-- grows into a 4v5 is one recording), within the per-recording size cap below.
local ADDON, ns = ...
local RP = {}
ns.Replay = RP

local PRE_ROLL   = 30     -- seconds of events kept before an open-world fight is noticed
local BUF_MAX    = 1500   -- hard cap on the rolling buffer
local MAX_EVENTS = 6000   -- per recording; past this the oldest DROP events go, so the end of the fight stays
local MAX_POS    = 4000
local DROP       = 1000
local SAMPLE     = 0.5    -- seconds between position samples
local OPEN_END   = 10     -- open world: seconds after the last PvP hit (once out of combat)
local OPEN_HARD  = 30     -- open world: seconds after the last PvP hit no matter what
local MIN_WORLD  = 5      -- open-world fights shorter than this many events are not kept
local KEEP_DEFAULT, KEEP_MAX = 5, 10

-- combat log object flags
local F_MINE, F_PARTY, F_RAID = 0x1, 0x2, 0x4
local F_HOSTILE, F_PLAYER = 0x40, 0x400

-- saved event codes (the number is what is stored)
local CODES = {
  "SWING_DAMAGE", "RANGE_DAMAGE", "SPELL_DAMAGE", "SPELL_PERIODIC_DAMAGE",
  "SPELL_HEAL", "SPELL_PERIODIC_HEAL",
  "SPELL_AURA_APPLIED", "SPELL_AURA_REMOVED", "SPELL_CAST_SUCCESS",
  "SPELL_INTERRUPT", "SPELL_DISPEL", "UNIT_DIED",
}
local CODE = {}
for i, n in ipairs(CODES) do CODE[n] = i end
RP.CODES = CODES

local KINDOF = {
  SWING_DAMAGE = "dmg", RANGE_DAMAGE = "dmg", SPELL_DAMAGE = "dmg", SPELL_PERIODIC_DAMAGE = "dmg",
  SPELL_HEAL = "heal", SPELL_PERIODIC_HEAL = "heal",
  SPELL_AURA_APPLIED = "aura", SPELL_AURA_REMOVED = "aura",
  SPELL_CAST_SUCCESS = "cast", SPELL_INTERRUPT = "int", SPELL_DISPEL = "int", UNIT_DIED = "died",
}
-- hits that tell us an open-world PvP fight has begun
local TRIGGER = {
  SWING_DAMAGE = true, RANGE_DAMAGE = true, SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true,
  SPELL_AURA_APPLIED = true, SPELL_INTERRUPT = true, SPELL_DISPEL = true,
}
local LABEL = { bg = "battleground", arena = "arena", world = "open world", manual = "manual" }

local DB            -- ns.DB
local cfg           -- ns.DB.replay
local rec           -- the recording in progress, or nil
local apiNote       -- set when the game gives us no combat log
local finishedInst  -- the match in this instance is already saved
local instMode      -- "bg", "arena" or nil, refreshed on every zone change (not per combat event)
local frame = CreateFrame("Frame")

local function Print(m) print("|cffe8ab35Realm|r |cff7fd4ffreplay|r: " .. tostring(m)) end
local function Say(m) if not (cfg and cfg.quiet) then Print(m) end end

local function Has(f, bit) return type(f) == "number" and math.floor(f / bit) % 2 == 1 end
local function Mine(f) return Has(f, F_MINE) or Has(f, F_PARTY) or Has(f, F_RAID) end

local function Mmss(s)
  s = math.floor((s or 0) + .5)
  return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function Short(n)
  if n >= 1000000 then return string.format("%.1fm", n / 1000000) end
  if n >= 1000 then return string.format("%.1fk", n / 1000) end
  return tostring(math.floor(n))
end

local function Ago(t)
  if not t then return "never" end
  local d = (time and time() or 0) - t
  if d < 60 then return "just now" end
  if d < 3600 then return math.floor(d / 60) .. "m ago" end
  if d < 86400 then return math.floor(d / 3600) .. "h ago" end
  return math.floor(d / 86400) .. "d ago"
end

local function ZoneName() return (GetZoneText and GetZoneText()) or "?" end

-- ------------------------------------------------------------ rolling buffer
local buf, bh, bt = {}, 1, 0
local function ClearBuf() buf, bh, bt = {}, 1, 0 end
local function Push(ev)
  bt = bt + 1; buf[bt] = ev
  local cut = ev.gt - PRE_ROLL
  while bh <= bt and (buf[bh].gt < cut or bt - bh >= BUF_MAX) do buf[bh] = nil; bh = bh + 1 end
end

-- ------------------------------------------------------------ recording
local Finish   -- forward

local function Add(ev)
  if rec.nev >= MAX_EVENTS then
    local keep, n = {}, 0
    for i = DROP + 1, rec.nev do n = n + 1; keep[n] = rec.ev[i] end
    rec.ev, rec.nev, rec.trunc = keep, n, true
    rec.dropped = (rec.dropped or 0) + DROP
  end
  rec.nev = rec.nev + 1; rec.ev[rec.nev] = ev
end

local function AddPos(p)
  if rec.npos >= MAX_POS then
    local keep, n = {}, 0
    for i = DROP + 1, rec.npos do n = n + 1; keep[n] = rec.pos[i] end
    rec.pos, rec.npos, rec.trunc = keep, n, true
  end
  rec.npos = rec.npos + 1; rec.pos[rec.npos] = p
end

local function SampleUnit(unit, gt)
  if not (UnitExists and UnitExists(unit)) then return end
  if (unit == "target" or unit == "focus") and not (UnitIsPlayer and UnitIsPlayer(unit)) then return end
  local g = UnitGUID and UnitGUID(unit)
  if type(g) ~= "string" then return end
  local y, x, _, map = UnitPosition(unit)
  if type(x) ~= "number" or type(y) ~= "number" then return end
  x, y = math.floor(x + .5), math.floor(y + .5)
  local l = rec.last[g]
  if l and l[1] == x and l[2] == y then return end
  rec.last[g] = { x, y }
  rec.map = rec.map or map
  AddPos({ gt = gt, g = g, n = UnitName and UnitName(unit) or "?", x = x, y = y })
end

local function Sample(gt)
  if not UnitPosition then return end
  local list = { "player", "target", "focus" }
  if IsInRaid and IsInRaid() then
    for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do list[#list + 1] = "raid" .. i end
  elseif IsInGroup and IsInGroup() then
    for i = 1, 4 do list[#list + 1] = "party" .. i end
  end
  if rec.kind == "arena" then for i = 1, 5 do list[#list + 1] = "arena" .. i end end
  for _, u in ipairs(list) do SampleUnit(u, gt) end
end

local function OnUpdate(_, dt)
  if not rec then return end
  rec.acc = rec.acc + (dt or 0)
  if rec.acc < SAMPLE then return end
  rec.acc = 0
  local gt = GetTime()
  pcall(Sample, gt)
  if rec.kind == "world" then
    local idle = gt - rec.lastPvp
    local fighting = UnitAffectingCombat and UnitAffectingCombat("player")
    if idle > OPEN_HARD or (idle > OPEN_END and not fighting) then Finish("fight over") end
  end
end

local function Start(kind, zone)
  if rec then return end
  local gt = GetTime()
  rec = { kind = kind, zone = zone or ZoneName(), g0 = gt, ev = {}, nev = 0, pos = {}, npos = 0,
          last = {}, part = {}, lastPvp = gt, acc = 0, startedAt = time and time() or 0 }
  if kind == "world" then
    local first
    for i = bh, bt do
      local e = buf[i]
      if e then rec.nev = rec.nev + 1; rec.ev[rec.nev] = e; first = first or e.gt end
    end
    if first then rec.g0 = first end
  end
  ClearBuf()
  frame:SetScript("OnUpdate", OnUpdate)
  Say("recording " .. LABEL[kind] .. " in " .. rec.zone)
end

-- turn the live recording into the compact saved form
local function Compact(r, reason, endGt)
  local units, idx = {}, {}
  local function U(g, n, f)
    if type(g) ~= "string" or g == "" then return 0 end
    local i = idx[g]
    if not i then
      i = #units + 1; idx[g] = i
      local u = { g, n or "?", f or 0 }
      if g:sub(1, 7) == "Player-" and GetPlayerInfoByGUID then
        local ok, _, cls = pcall(GetPlayerInfoByGUID, g)
        if ok and cls then u[4] = cls end
      end
      units[i] = u
    end
    return i
  end
  local me = U(UnitGUID and UnitGUID("player"), UnitName and UnitName("player"), F_MINE + F_PLAYER)
  local ev = {}
  for i = 1, r.nev do
    local e = r.ev[i]
    ev[i] = {
      math.floor((e.gt - r.g0) * 1000 + .5), CODE[e.e],
      U(e.sg, e.sn, e.sf), U(e.dg, e.dn, e.df),
      type(e.id) == "number" and e.id or 0,
      type(e.amt) == "number" and math.floor(e.amt) or 0,
      type(e.x) == "number" and e.x or 0,
    }
  end
  local pos = {}
  for i = 1, r.npos do
    local p = r.pos[i]
    pos[i] = { math.floor((p.gt - r.g0) * 1000 + .5), U(p.g, p.n, 0), p.x, p.y }
  end
  local dur = endGt - r.g0
  if r.kind == "world" and r.nev > 0 then dur = r.ev[r.nev].gt - r.g0 end
  if dur < 0 then dur = 0 end
  cfg.nextId = cfg.nextId or 1
  local id = cfg.nextId
  cfg.nextId = id + 1
  return {
    id = id, ver = 1, kind = r.kind, zone = r.zone, when = r.startedAt,
    dur = math.floor(dur * 10 + .5) / 10, me = me, units = units, ev = ev, pos = pos,
    nEv = r.nev, trunc = r.trunc or false, dropped = r.dropped or 0,
    winner = r.winner, map = r.map, reason = reason,
  }
end

function Finish(reason, winner)
  if not rec then return end
  local r = rec
  rec = nil
  frame:SetScript("OnUpdate", nil)
  ClearBuf()
  r.winner = winner
  if r.kind == "world" and r.nev < MIN_WORLD then
    Say("fight too short to keep (" .. r.nev .. " events)")
    return
  end
  local saved = Compact(r, reason, GetTime())
  table.insert(cfg.recs, 1, saved)
  while #cfg.recs > (cfg.keep or KEEP_DEFAULT) do table.remove(cfg.recs) end
  Say(string.format("saved #%d, %s in %s, %s, %d events%s. Keeping %d of %d.",
    saved.id, LABEL[saved.kind], saved.zone, Mmss(saved.dur), saved.nEv,
    saved.trunc and " (the earliest part was dropped to fit)" or "", #cfg.recs, cfg.keep or KEEP_DEFAULT))
end
RP.Finish = Finish

-- ------------------------------------------------------------ the combat log
local function PvPHit(sub, sf, df)
  if not TRIGGER[sub] then return false end
  return (Has(sf, F_PLAYER) and Has(sf, F_HOSTILE) and Mine(df))
      or (Has(df, F_PLAYER) and Has(df, F_HOSTILE) and Mine(sf))
end

-- a hit between two other players, one hostile to you and one not (someone nearby joining in)
local function CrossPvP(sub, sf, df)
  return TRIGGER[sub] and Has(sf, F_PLAYER) and Has(df, F_PLAYER) and (Has(sf, F_HOSTILE) ~= Has(df, F_HOSTILE))
end

-- remember who is taking part, so their heals, buffs and casts are kept too
local function Mark(ev)
  if not rec then return end
  if type(ev.sg) == "string" then rec.part[ev.sg] = true end
  if type(ev.dg) == "string" then rec.part[ev.dg] = true end
end

local function OnCombat()
  if not (cfg and cfg.on) then return end
  if instMode == "bg" then return end   -- battlegrounds are not recorded
  local _, sub, _, sg, sn, sf, _, dg, dn, df, _, a12, a13, a14, a15 = CombatLogGetCurrentEventInfo()
  local kind = KINDOF[sub]
  if not kind then return end
  if type(sf) ~= "number" and type(df) ~= "number" then return end
  -- keep what involves you or your group and a player, plus any player death
  local third = false
  if sub == "UNIT_DIED" then
    if not Has(df, F_PLAYER) then return end
  elseif not ((Mine(sf) or Mine(df)) and (Has(sf, F_PLAYER) or Has(df, F_PLAYER))) then
    -- not about you or your group: during an open-world fight keep other players who are part of it
    local keep = false
    if rec and rec.kind == "world" then
      if CrossPvP(sub, sf, df) then keep, third = true, true
      elseif (rec.part[sg] or rec.part[dg]) and (Has(sf, F_PLAYER) or Has(df, F_PLAYER)) then keep = true end
    end
    if not keep then return end
  end
  local ev = { gt = GetTime(), e = sub, sg = sg, sn = sn, sf = sf, dg = dg, dn = dn, df = df }
  if kind == "dmg" then
    if sub == "SWING_DAMAGE" then ev.amt = a12 else ev.id = a12; ev.amt = a15 end
  elseif kind == "heal" then ev.id = a12; ev.amt = a15
  elseif kind == "aura" then ev.id = a12; ev.x = (a15 == "BUFF") and 1 or 2
  elseif kind == "int" then ev.id = a12; ev.x = (type(a15) == "number") and a15 or 0
  elseif kind == "cast" then ev.id = a12 end
  if rec then
    Add(ev)
    if rec.kind == "world" and (third or PvPHit(sub, sf, df)) then rec.lastPvp = ev.gt; Mark(ev) end
  else
    Push(ev)
    if PvPHit(sub, sf, df) then Start("world"); Mark(ev) end
  end
end

-- ------------------------------------------------------------ matches (battleground / arena)
local function InstanceMode()
  if not IsInInstance then return nil end
  local ok, inst, typ = pcall(IsInInstance)
  if ok and inst then
    if typ == "pvp" then return "bg" end
    if typ == "arena" then return "arena" end
  end
end

local function Evaluate()
  instMode = InstanceMode()
  if not (cfg and cfg.on) then return end
  local m = instMode
  if m then
    if rec and rec.kind == "world" then Finish("entered a match") end
    -- battlegrounds are skipped on purpose; arenas still record
    if m ~= "bg" and not rec and not finishedInst then Start(m, ZoneName()) end
  else
    finishedInst = false
    if rec and (rec.kind == "bg" or rec.kind == "arena") then Finish("left the match") end
  end
end
RP.Evaluate = Evaluate

local function CheckOver(winner)
  if not rec or rec.kind == "world" or rec.kind == "manual" then return end
  if winner == nil and GetBattlefieldWinner then winner = GetBattlefieldWinner() end
  if winner ~= nil then
    finishedInst = true
    Finish("match over", winner)
  end
end

-- ------------------------------------------------------------ events
local function Reg(f, e) return (pcall(f.RegisterEvent, f, e)) end

local function Login()
  local R = ns.DB
  R.replay = R.replay or {}
  cfg = R.replay
  if cfg.on == nil then cfg.on = true end
  cfg.keep = cfg.keep or KEEP_DEFAULT
  cfg.recs = cfg.recs or {}
  cfg.nextId = cfg.nextId or 1
  if not CombatLogGetCurrentEventInfo then
    apiNote = "this client has no combat log function"
  elseif not Reg(frame, "COMBAT_LOG_EVENT_UNFILTERED") then
    apiNote = "the game refused the combat log event"
  end
  if apiNote then
    Print("recording is off, " .. apiNote .. ".")
    return
  end
  Evaluate()
end

frame:RegisterEvent("PLAYER_LOGIN")
Reg(frame, "PLAYER_ENTERING_WORLD")
Reg(frame, "ZONE_CHANGED_NEW_AREA")
Reg(frame, "UPDATE_BATTLEFIELD_STATUS")
Reg(frame, "PVP_MATCH_COMPLETE")
frame:SetScript("OnEvent", function(_, event, a1)
  if event == "COMBAT_LOG_EVENT_UNFILTERED" then return OnCombat() end
  if event == "PLAYER_LOGIN" then Login()
  elseif not cfg then return
  elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then Evaluate()
  elseif event == "UPDATE_BATTLEFIELD_STATUS" then CheckOver(nil)
  elseif event == "PVP_MATCH_COMPLETE" then CheckOver(a1 == nil and -1 or a1)
  end
end)

-- ------------------------------------------------------------ chat commands
local function Top(map, units, n)
  local list = {}
  for i, v in pairs(map) do if i > 0 and units[i] then list[#list + 1] = { i, v } end end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  local out = {}
  for k = 1, math.min(n, #list) do out[#out + 1] = units[list[k][1]][2] .. " " .. Short(list[k][2]) end
  return #out > 0 and table.concat(out, ", ") or "none"
end

local function Info(n)
  local r = cfg.recs[n]
  if not r then Print("no recording number " .. n .. ". /realm replay lists them."); return end
  Print(string.format("#%d %s in %s, %s, %s. %d events, %d position samples%s.",
    r.id, LABEL[r.kind] or r.kind, r.zone, Mmss(r.dur), Ago(r.when), r.nEv, #r.pos,
    r.trunc and ", earliest part dropped" or ""))
  local dmg, heal, died = {}, {}, {}
  for _, e in ipairs(r.ev) do
    local c = e[2]
    if c and c <= 4 then dmg[e[3]] = (dmg[e[3]] or 0) + e[6]
    elseif c and c <= 6 then heal[e[3]] = (heal[e[3]] or 0) + e[6]
    elseif c == 12 and r.units[e[4]] then died[#died + 1] = r.units[e[4]][2] .. " " .. Mmss(e[1] / 1000) end
  end
  Print("damage: " .. Top(dmg, r.units, 5))
  Print("healing: " .. Top(heal, r.units, 3))
  Print("deaths: " .. (#died > 0 and table.concat(died, ", ") or "none"))
end

function RP.Command(arg)
  if not cfg then Print("not ready yet, try again after the game finishes loading."); return end
  arg = (arg or ""):lower()
  local cmd, rest = arg:match("^%s*(%S*)%s*(.-)%s*$")
  if cmd == "" or cmd == "list" then
    if #cfg.recs == 0 then Print("no recordings yet. They are made on their own when a PvP fight starts.")
    else
      for i, r in ipairs(cfg.recs) do
        Print(string.format("%d. #%d %s, %s, %s, %d events, %s", i, r.id, LABEL[r.kind] or r.kind, r.zone, Mmss(r.dur), r.nEv, Ago(r.when)))
      end
      Print("/realm replay play <number> to watch one, info <number> for the damage, healing and deaths, demo for the practice match")
    end
  elseif cmd == "info" then Info(tonumber(rest) or 1)
  elseif cmd == "play" or cmd == "window" or cmd == "show" or cmd == "watch" then
    if ns.ReplayView then ns.ReplayView.Open(false, tonumber(rest)) end
  elseif cmd == "demo" or cmd == "what" or cmd == "preview" then
    if ns.ReplayView then ns.ReplayView.Open(true) end
  elseif cmd == "on" or cmd == "off" then
    cfg.on = (cmd == "on")
    if not cfg.on and rec then Finish("turned off") end
    if cfg.on then Evaluate() end
    Print("recording " .. (cfg.on and "on" or "off"))
  elseif cmd == "start" then
    if apiNote then Print("recording is off, " .. apiNote .. ".")
    elseif rec then Print("already recording")
    else Start("manual", ZoneName()) end
  elseif cmd == "stop" or cmd == "save" then
    if rec then Finish("stopped by you") else Print("nothing is recording") end
  elseif cmd == "keep" then
    local n = tonumber(rest)
    if not n then Print("keeping " .. cfg.keep .. " recordings. /realm replay keep <1-" .. KEEP_MAX .. ">")
    else
      cfg.keep = math.max(1, math.min(KEEP_MAX, math.floor(n)))
      while #cfg.recs > cfg.keep do table.remove(cfg.recs) end
      Print("keeping the last " .. cfg.keep .. " recordings")
    end
  elseif cmd == "quiet" then
    cfg.quiet = not cfg.quiet
    Print("chat messages " .. (cfg.quiet and "off" or "on"))
  elseif cmd == "clear" then
    if rest == "confirm" then cfg.recs = {}; Print("all recordings deleted")
    else Print("this deletes every saved recording. Type /realm replay clear confirm to do it.") end
  elseif cmd == "status" then
    local ev = 0
    for _, r in ipairs(cfg.recs) do ev = ev + (r.nEv or 0) end
    Print("recording is " .. (cfg.on and "on" or "off") .. (apiNote and (" but unavailable, " .. apiNote) or "")
      .. ". " .. #cfg.recs .. " saved (" .. ev .. " events), keeping " .. cfg.keep .. ".")
    if rec then Print("now recording " .. LABEL[rec.kind] .. " in " .. rec.zone .. ", " .. Mmss(GetTime() - rec.g0) .. ", " .. rec.nev .. " events, " .. rec.npos .. " positions") end
  else
    Print("/realm replay (list) | play <n> | demo | info <n> | status | start | stop | on | off | keep <n> | quiet | clear")
  end
end

function RP.Recording() return rec end
function RP.Saved() return cfg and cfg.recs end
