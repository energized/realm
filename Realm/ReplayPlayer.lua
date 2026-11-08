-- Replay player: the engine behind the Replay window. It walks a saved recording event by event:
-- play, pause, step back, step forward, jump between key moments, seek and speed. It also builds the
-- scripted bot match used by the "What this is" preview. No UI in here, so it can be tested on its own.
local ADDON, ns = ...
local P = {}
P.__index = P
ns.ReplayPlayer = P

local SPEEDS = { 0.25, 0.5, 1, 2, 4 }
P.SPEEDS = SPEEDS
local KEY = { [10] = true, [11] = true, [12] = true }   -- interrupt, dispel, death

function P.Clock(ms)
  local s = math.floor((ms or 0) / 1000)
  return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

-- last index i in list with list[i][1] <= ms (0 when none)
local function Upto(list, ms)
  local lo, hi = 0, #list
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if list[mid][1] <= ms then lo = mid else hi = mid - 1 end
  end
  return lo
end

-- ------------------------------------------------------------ names
function P.UnitName(rec, i)
  local u = rec.units and rec.units[i]
  if i == 0 or not u then return "environment" end
  return u[2]
end

function P.SpellName(rec, id)
  if not id or id == 0 then return "melee" end
  if rec.spellNames and rec.spellNames[id] then return rec.spellNames[id] end
  local fn = (C_Spell and C_Spell.GetSpellInfo) or GetSpellInfo
  if fn then
    local ok, a = pcall(fn, id)
    if ok then
      if type(a) == "table" and a.name then return tostring(a.name) end
      if type(a) == "string" then return a end
    end
  end
  return "spell " .. tostring(id)
end

function P.Describe(rec, e)
  local c = e[2] or 0
  local s, d = P.UnitName(rec, e[3]), P.UnitName(rec, e[4])
  local sp, amt, extra = P.SpellName(rec, e[5]), e[6] or 0, e[7] or 0
  local txt
  if c == 1 then txt = ("%s hits %s (melee %d)"):format(s, d, amt)
  elseif c >= 2 and c <= 4 then txt = ("%s hits %s (%s %d)"):format(s, d, sp, amt)
  elseif c == 5 or c == 6 then txt = ("%s heals %s (%s %d)"):format(s, d, sp, amt)
  elseif c == 7 then txt = ("%s puts %s on %s"):format(s, sp, d)
  elseif c == 8 then txt = ("%s fades from %s"):format(sp, d)
  elseif c == 9 then txt = ("%s casts %s"):format(s, sp)
  elseif c == 10 then txt = ("%s interrupts %s%s"):format(s, d, extra > 0 and (" (" .. P.SpellName(rec, extra) .. ")") or "")
  elseif c == 11 then txt = ("%s dispels %s from %s"):format(s, extra > 0 and P.SpellName(rec, extra) or sp, d)
  elseif c == 12 then txt = ("%s dies"):format(d)
  else txt = "?" end
  return P.Clock(e[1]) .. "  " .. txt
end

-- ------------------------------------------------------------ player
function P.New(rec)
  local self = setmetatable({ rec = rec, ev = rec.ev or {}, idx = 0, t = 0, playing = false, speed = 1, si = 3,
                              st = { u = {} }, sidx = 0, by = {} }, P)
  self.n = #self.ev
  local last = self.n > 0 and self.ev[self.n][1] or 0
  self.tEnd = math.max(last, math.floor((rec.dur or 0) * 1000))
  local minx, maxx, miny, maxy
  for _, p in ipairs(rec.pos or {}) do
    local l = self.by[p[2]]
    if not l then l = {}; self.by[p[2]] = l end
    l[#l + 1] = p
    minx = (not minx or p[3] < minx) and p[3] or minx
    maxx = (not maxx or p[3] > maxx) and p[3] or maxx
    miny = (not miny or p[4] < miny) and p[4] or miny
    maxy = (not maxy or p[4] > maxy) and p[4] or maxy
  end
  self.bounds = minx and { minx, maxx, miny, maxy } or nil
  return self
end

function P:Seek(ms)
  ms = math.max(0, math.min(self.tEnd, ms or 0))
  self.t = ms
  self.idx = Upto(self.ev, ms)
end

function P:Step(d)
  self.playing = false
  self.idx = math.max(0, math.min(self.n, self.idx + d))
  self.t = self.idx > 0 and self.ev[self.idx][1] or 0
end

-- jump to the next (d = 1) or previous (d = -1) interrupt, dispel or death
function P:Key(d)
  self.playing = false
  local i = self.idx + d
  while i >= 1 and i <= self.n do
    if KEY[self.ev[i][2]] then
      self.idx, self.t = i, self.ev[i][1]
      return true
    end
    i = i + d
  end
  if d > 0 then self.idx, self.t = self.n, self.tEnd else self.idx, self.t = 0, 0 end
  return false
end

function P:Play()
  if self.t >= self.tEnd and self.idx >= self.n then self.idx, self.t = 0, 0 end
  self.playing = true
end
function P:Pause() self.playing = false end
function P:Toggle() if self.playing then self:Pause() else self:Play() end end
function P:Restart() self.playing = false; self.idx, self.t = 0, 0 end
function P:ToEnd() self.playing = false; self.idx, self.t = self.n, self.tEnd end

function P:SetSpeed(s)
  for i, v in ipairs(SPEEDS) do if v == s then self.si = i; self.speed = v; return end end
end
function P:CycleSpeed()
  self.si = self.si % #SPEEDS + 1
  self.speed = SPEEDS[self.si]
  return self.speed
end

function P:Tick(dt)
  if not self.playing then return end
  self.t = self.t + (dt or 0) * 1000 * self.speed
  if self.t >= self.tEnd then self.t = self.tEnd; self.playing = false end
  while self.idx < self.n and self.ev[self.idx + 1][1] <= self.t do self.idx = self.idx + 1 end
end

-- ------------------------------------------------------------ what has happened so far
local function Stat(st, i)
  local s = st.u[i]
  if not s then
    s = { dealt = 0, taken = 0, heal = 0, healed = 0, kicks = 0, dead = false, auras = {} }
    st.u[i] = s
  end
  return s
end

local function Apply(st, e)
  local c, a, b, amt = e[2], e[3], e[4], e[6] or 0
  if not c then return end
  if c <= 4 then
    if a > 0 then Stat(st, a).dealt = Stat(st, a).dealt + amt end
    if b > 0 then Stat(st, b).taken = Stat(st, b).taken + amt end
  elseif c <= 6 then
    if a > 0 then Stat(st, a).heal = Stat(st, a).heal + amt end
    if b > 0 then Stat(st, b).healed = Stat(st, b).healed + amt end
  elseif c == 7 then
    if b > 0 then Stat(st, b).auras[e[5]] = true end
  elseif c == 8 then
    if b > 0 then Stat(st, b).auras[e[5]] = nil end
  elseif c == 10 then
    if a > 0 then Stat(st, a).kicks = Stat(st, a).kicks + 1 end
  elseif c == 11 then
    if b > 0 then Stat(st, b).auras[e[7]] = nil end
  elseif c == 12 then
    if b > 0 then local s = Stat(st, b); s.dead = true; s.auras = {} end
  end
end

function P:State()
  if self.sidx > self.idx then self.st = { u = {} }; self.sidx = 0 end
  for i = self.sidx + 1, self.idx do Apply(self.st, self.ev[i]) end
  self.sidx = self.idx
  return self.st
end

-- where each unit stood at the current time: [unitIndex] = { x, y }
function P:Positions()
  local out = {}
  for u, list in pairs(self.by) do
    local p = list[Upto(list, self.t)] or list[1]
    if p then out[u] = { p[3], p[4] } end
  end
  return out
end

-- the last n events up to the current one, oldest first
function P:Recent(n)
  local out = {}
  for i = math.max(1, self.idx - n + 1), self.idx do out[#out + 1] = self.ev[i] end
  return out
end

-- ------------------------------------------------------------ scripted bot match for the preview
function P.Demo()
  local ME, ALLY, FOE = 0x511, 0x512, 0x548
  local units = {
    { "Player-Demo-1", "You",         ME,   "MAGE" },
    { "Player-Demo-2", "Priest Bot",  ALLY, "PRIEST" },
    { "Player-Demo-3", "Rogue Bot",   ALLY, "ROGUE" },
    { "Player-Demo-4", "Warrior Bot", FOE,  "WARRIOR" },
    { "Player-Demo-5", "Hunter Bot",  FOE,  "HUNTER" },
    { "Player-Demo-6", "Druid Bot",   FOE,  "DRUID" },
  }
  local ev, seq = {}, 0
  local function E(sec, code, s, d, id, amt, x)
    seq = seq + 1
    ev[#ev + 1] = { math.floor(sec * 1000 + .5), code, s, d, id or 0, amt or 0, x or 0, seq }
  end
  -- a repeating action: src does something to dst every `period` seconds from `from` to `to`
  local function Rot(src, dst, code, id, base, period, from, to, skipA, skipB)
    local k = 0
    local t = from
    while t <= to do
      if not (skipA and t >= skipA and t <= skipB) then E(t, code, src, dst, id, base + (k * 37) % 61) end
      k = k + 1
      t = from + k * period
    end
  end
  Rot(1, 4, 3, 116,   420, 2.0,  1, 51, 14, 16)       -- You: Frostbolt on the Warrior (silenced for two seconds)
  Rot(2, 1, 5, 2061,  520, 3.0,  2, 73)               -- Priest: Flash Heal on You
  Rot(2, 2, 5, 2061,  560, 2.5, 53, 82)               -- Priest heals herself after You are down
  Rot(3, 5, 3, 1752,  310, 1.5,  3, 43)               -- Rogue: Sinister Strike on the Hunter
  Rot(3, 6, 3, 1752,  330, 1.5, 45, 60)               -- ...then the Druid
  Rot(3, 4, 3, 1752,  340, 1.5, 62, 81)               -- ...then the Warrior
  Rot(4, 1, 3, 12294, 650, 2.5,  4, 51)               -- Warrior: Mortal Strike on You
  Rot(4, 2, 3, 12294, 500, 2.5, 53, 81)               -- ...then the Priest
  Rot(5, 2, 3, 2643,  280, 2.0,  2, 43, 10, 14.1)     -- Hunter: Multi-Shot on the Priest (not while polymorphed)
  Rot(6, 2, 3, 8921,  240, 3.0,  5, 60)               -- Druid: Moonfire on the Priest
  Rot(6, 5, 5, 8936,  400, 4.0,  6, 42)               -- Druid: Regrowth on the Hunter
  E(10.0, 7, 1, 5, 118, 0, 2)                         -- You polymorph the Hunter
  E(14.1, 8, 1, 5, 118, 0, 2)                         -- ...and it breaks
  E(14.0, 10, 4, 1, 6552, 0, 116)                     -- Warrior interrupts your Frostbolt with Pummel
  E(36.0, 7, 6, 3, 339, 0, 2)                         -- Druid roots the Rogue
  E(37.5, 11, 2, 3, 527, 0, 339)                      -- Priest dispels it
  E(37.5, 8, 6, 3, 339, 0, 2)
  E(44.0, 12, 0, 5)                                   -- Hunter dies
  E(52.0, 12, 0, 1)                                   -- You die
  E(61.0, 12, 0, 6)                                   -- Druid dies
  E(82.0, 12, 0, 4)                                   -- Warrior dies
  table.sort(ev, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return a[8] < b[8] end)
  for _, e in ipairs(ev) do e[8] = nil end

  local pos, last = {}, {}
  local deathAt = { [5] = 44, [1] = 52, [6] = 61, [4] = 82 }
  for s = 0, 83 do
    for i = 1, 6 do
      local ts = (deathAt[i] and s > deathAt[i]) and deathAt[i] or s
      local cx = (i <= 3) and -25 or 25
      local ang = ts * (0.12 + i * 0.02) + i
      local r = 5 + i * 1.5
      local x = math.floor(cx + r * math.cos(ang) + .5)
      local y = math.floor(r * math.sin(ang) * 1.2 + .5)
      local l = last[i]
      if not l or l[1] ~= x or l[2] ~= y then
        last[i] = { x, y }
        pos[#pos + 1] = { s * 1000, i, x, y }
      end
    end
  end
  return {
    id = 0, ver = 1, demo = true, kind = "arena", zone = "Practice match (scripted bots)",
    when = time and time() or 0, dur = 83, me = 1, units = units, ev = ev, pos = pos, nEv = #ev,
    trunc = false, dropped = 0,
    spellNames = { [116] = "Frostbolt", [2061] = "Flash Heal", [1752] = "Sinister Strike", [12294] = "Mortal Strike",
      [2643] = "Multi-Shot", [8921] = "Moonfire", [8936] = "Regrowth", [118] = "Polymorph", [6552] = "Pummel",
      [339] = "Entangling Roots", [527] = "Dispel Magic" },
  }
end
