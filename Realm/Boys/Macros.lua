-- TheBoys / Realm macros: builds the five hotbar macro sets for the player's class and spec.
--   Hotbar 1 solo / leveling, Hotbar 2 party, Hotbar 3 battlegrounds, Hotbar 4 raid, main bar = other useful spells.
-- Real macros only (CreateMacro / EditMacro). Nothing runs in combat: work is queued until it ends.
-- Macros the player edited are never overwritten (a saved hash tells us), and occupied slots are never taken.
-- Commands: /realm macros   (also /boys macros)
local ADDON, ns = ...
local TB = ns.TB
local M = {}
TB.Macros = M

local BODY_MAX, ICON = 255, 134400
-- at most 7 macros per hotbar, so a full set is 28 and always fits the 30 character macro slots
local PER_BAR = 7
local function MaxChar() return type(MAX_CHARACTER_MACROS) == "number" and MAX_CHARACTER_MACROS or 30 end
-- action slots. Main bar is 1-12; the four extra bars are the "Bottom Left / Bottom Right / Right / Right 2" bars
-- (turn them on in Game Menu > Options > Action Bars).
local BAR_FIRST = { 61, 49, 25, 37 }
M.BAR_FIRST = BAR_FIRST
local BAR_TITLE = { "Hotbar 1 (solo)", "Hotbar 2 (party)", "Hotbar 3 (battlegrounds)", "Hotbar 4 (raid)" }

local LABEL = {
  st = "Single", fin = "Finisher", dot = "DoTs", aoe = "AoE", burst = "Burst", def = "Defense", int = "Interrupt",
  cc = "CC", taunt = "Taunt", heal = "Self Heal", heal1 = "Fast Heal", heal2 = "Big Heal", hot = "HoT",
  aoeheal = "Group Heal", dispel = "Dispel", buff = "Buffs", mob = "Mobility", open = "Opener", util = "Utility",
}
M.LABEL = LABEL

local TEMPLATE = {
  DPS = {
    { "st", "fin", "dot", "aoe", "def", "buff", "heal", "open", "mob" },
    { "st", "fin", "dot", "aoe", "burst", "int", "def", "cc" },
    { "st", "fin", "dot", "burst", "int", "def", "cc", "mob" },
    { "st", "fin", "dot", "aoe", "burst", "int", "def", "util" },
  },
  HEALER = {
    { "st", "aoe", "def", "heal", "buff", "mob", "open" },
    { "heal1", "heal2", "hot", "aoeheal", "dispel", "burst", "def" },
    { "heal1", "heal2", "hot", "dispel", "cc", "def", "mob" },
    { "heal1", "heal2", "hot", "aoeheal", "dispel", "burst", "def" },
  },
  TANK = {
    { "st", "aoe", "def", "heal", "buff", "mob", "open" },
    { "st", "aoe", "taunt", "int", "cc", "def", "burst" },
    { "st", "aoe", "int", "cc", "def", "mob", "burst" },
    { "st", "aoe", "taunt", "int", "def", "burst", "util" },
  },
}
M.TEMPLATE = TEMPLATE

local function Say(msg) if TB.Print then TB.Print("macros: " .. tostring(msg)) end end

local function Hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
  return h
end
M.Hash = Hash

local function Role(r)
  r = (r or ""):lower()
  if r:find("heal", 1, true) then return "HEALER" end
  if r:find("tank", 1, true) and not r:find("dps", 1, true) then return "TANK" end
  return "DPS"
end

-- "A;B|C;D" -> the spells this character knows right now, newest alternate first: { "A", "B", "D" }
local function Resolve(str)
  local out = {}
  for entry in (str or ""):gmatch("[^;]+") do
    for alt in entry:gmatch("[^|]+") do
      alt = alt:match("^%s*(.-)%s*$")
      if alt ~= "" and TB.Known(alt) then out[#out + 1] = alt; break end
    end
  end
  return out
end

local SMART = "[@mouseover,help,nodead][help,nodead][@player] "
local HEALKIND = { heal = 1, heal1 = 1, heal2 = 1, hot = 1, aoeheal = 1, dispel = 1 }

local function Hostile(bar)
  if bar == 3 then return "[@mouseover,harm,nodead][@focus,harm,nodead][] " end
  return "[@focus,harm,nodead][] "
end

local function Lines(list, cond)
  local t = {}
  for _, n in ipairs(list) do t[#t + 1] = "/cast " .. (cond or "") .. n end
  return t
end

local function ModLine(list)
  local parts = {}
  if list[2] then parts[#parts + 1] = "[mod:shift] " .. list[2] end
  if list[3] then parts[#parts + 1] = "[mod:ctrl] " .. list[3] end
  parts[#parts + 1] = list[1]
  return "/cast " .. table.concat(parts, "; ")
end

local function Compose(kind, list, d, bar)
  local out = { "#showtooltip" }
  local function add(s) out[#out + 1] = s end
  if kind == "st" then
    if d.atk == "m" then add("/startattack")
    elseif d.atk == "r" and TB.Known("Auto Shot") then add("/cast !Auto Shot") end
    if d.pet then add("/petattack") end
  end
  if kind == "dot" then
    add("/castsequence reset=target/combat " .. table.concat(list, ", "))
  elseif kind == "buff" then
    add("/castsequence reset=combat/30 " .. table.concat(list, ", "))
  elseif HEALKIND[kind] then
    for _, l in ipairs(Lines(list, SMART)) do add(l) end
  elseif kind == "int" or kind == "cc" then
    for _, l in ipairs(Lines(list, Hostile(bar))) do add(l) end
  elseif kind == "taunt" then
    for _, l in ipairs(Lines(list, "[@mouseover,harm,nodead][] ")) do add(l) end
  elseif kind == "burst" then
    for _, l in ipairs(Lines(list)) do add(l) end
    add("/use 13"); add("/use 14")
  elseif (kind == "st" or kind == "aoe" or kind == "def" or kind == "fin") and d.style == "mod" then
    add(ModLine(list))
  else
    for _, l in ipairs(Lines(list)) do add(l) end
  end
  return table.concat(out, "\n")
end

-- build one macro body, dropping the last spell until it fits 255 characters; nil when nothing is known
local function Build(kind, str, d, bar)
  local list = Resolve(str)
  while #list > 0 do
    local body = Compose(kind, list, d, bar)
    if #body <= BODY_MAX then return body end
    table.remove(list)
  end
end

-- other useful spells for the main bar
local function MainList(cls, spec, d)
  local seen, out = {}, {}
  local function add(n)
    if n and not seen[n] and TB.Known(n) then seen[n] = true; out[#out + 1] = n end
  end
  for _, n in ipairs(Resolve(d and d.main)) do add(n) end
  for _, e in ipairs(spec.priority or {}) do add(TB.Pick(e)) end
  for _, e in ipairs(spec.cooldowns or {}) do add(e[1]) end
  for _, e in ipairs(spec.aoe or {}) do add(e[1]) end
  for _, e in ipairs(cls.utility or {}) do add(e[1]) end
  return out
end

function M.Plan(token, key)
  token = token or TB.ClassToken()
  local cls = token and TB.classes[token]
  if not cls then return nil, "no guide for your class" end
  if not key then local _; _, key = TB.Spec() end
  local spec = cls.specs[key]
  local d = TB.MacroData and TB.MacroData[token] and TB.MacroData[token][key]
  if not (spec and d) then return nil, "no macro data for " .. tostring(token) .. " " .. tostring(key) end
  local role = Role(spec.role)
  local plan = { class = token, spec = key, role = role, list = {} }
  for bar = 1, 4 do
    local pos = 0
    for _, kind in ipairs(TEMPLATE[role][bar]) do
      local body = d[kind] and Build(kind, d[kind], d, bar)
      if body and pos < PER_BAR then
        pos = pos + 1
        plan.list[#plan.list + 1] = { bar = bar, pos = pos, kind = kind, name = ("R%d %s"):format(bar, LABEL[kind]), body = body }
      end
    end
  end
  plan.main = MainList(cls, spec, d)
  return plan
end

-- ------------------------------------------------------------ saved state (per character)
local function Store()
  local r = TB.Char()
  r.macros = r.macros or {}
  r.macros.hashes = r.macros.hashes or {}
  return r.macros
end

function M.AutoOn() return Store().auto ~= false end      -- default ON
function M.SetAuto(v) Store().auto = v and true or false end

-- ------------------------------------------------------------ install
local function PickupSpellByName(name)
  local _, _, id = TB.Spell(name)
  if C_Spell and C_Spell.PickupSpell and id then pcall(C_Spell.PickupSpell, id) return true end
  if PickupSpell and (id or name) then pcall(PickupSpell, id or name) return true end
end

local function OnBar(name)
  local _, _, id = TB.Spell(name)
  if id and C_ActionBar and C_ActionBar.IsOnBarOrSpecialBar then
    local ok, r = pcall(C_ActionBar.IsOnBarOrSpecialBar, id)
    if ok and r then return true end
  end
  return false
end

function M.Install(opts)
  opts = opts or {}
  if InCombatLockdown and InCombatLockdown() then
    M.queue, M.queued = opts, true
    if not opts.quiet then Say("in combat: I'll update the macros when combat ends.") end
    return false, "queued"
  end
  if not (CreateMacro and EditMacro and GetMacroIndexByName and GetMacroInfo) then
    Say("this client has no macro functions I can use."); return false, "noapi"
  end
  local token = TB.ClassToken()
  local _, curKey = TB.Spec()
  local plan, err = M.Plan(token, opts.spec or curKey)
  if not plan then Say(err); return false, err end

  local st = Store()
  local _, cN = 0, 0
  if GetNumMacros then _, cN = GetNumMacros() end
  local free = MaxChar() - (cN or 0)
  local r = { created = 0, updated = 0, same = 0, edited = 0, full = 0, placed = 0, kept = 0, main = 0 }

  for _, m in ipairs(plan.list) do
    local idx = GetMacroIndexByName(m.name)
    if idx and idx > 0 then
      local _, _, cur = GetMacroInfo(idx)
      cur = cur or ""
      if cur == m.body then
        r.same = r.same + 1; st.hashes[m.name] = Hash(m.body)
      elseif opts.force or (st.hashes[m.name] and st.hashes[m.name] == Hash(cur)) then
        pcall(EditMacro, idx, m.name, ICON, m.body)
        st.hashes[m.name] = Hash(m.body); r.updated = r.updated + 1
      else
        r.edited = r.edited + 1; m.skip = true       -- the player changed it, or it is not ours
      end
    elseif free > 0 then
      pcall(CreateMacro, m.name, ICON, m.body, true)
      free = free - 1
      if GetMacroIndexByName(m.name) > 0 then
        st.hashes[m.name] = Hash(m.body); r.created = r.created + 1
      else m.skip = true end
    else
      r.full = r.full + 1; m.skip = true
    end
  end

  -- place on the bars, only into empty slots or slots that already hold one of our macros
  if PlaceAction and PickupMacro and GetActionInfo then
    for _, m in ipairs(plan.list) do
      local idx = not m.skip and GetMacroIndexByName(m.name) or 0
      if idx > 0 then
        local slot = BAR_FIRST[m.bar] + m.pos - 1
        local t, id = GetActionInfo(slot)
        local ours = false
        if t == "macro" then local nm = GetMacroInfo(id); ours = nm and nm:match("^R[1-4] ") and true or false end
        if t == "macro" and id == idx then
          -- already there
        elseif (not t) or ours then
          PickupMacro(idx); PlaceAction(slot); if ClearCursor then ClearCursor() end
          r.placed = r.placed + 1
        else
          r.kept = r.kept + 1
        end
      end
    end
    -- main bar: other useful spells, empty slots only
    local p = 1
    for _, name in ipairs(plan.main) do
      while p <= 12 and GetActionInfo(p) do p = p + 1 end
      if p > 12 then break end
      if not OnBar(name) and PickupSpellByName(name) then
        PlaceAction(p); if ClearCursor then ClearCursor() end
        if GetActionInfo(p) then r.main = r.main + 1 end
      end
    end
  end

  st.installed, st.spec, st.dataVersion = true, plan.spec, TB.MacroDataVersion
  local changed = r.created + r.updated + r.placed + r.main
  if not (opts.quiet and changed == 0) then
    local msg = ("%s %s: %d created, %d updated, %d unchanged, %d placed on bars, %d spells on the main bar."):format(
      (TB.classes[token] and TB.classes[token].specs[plan.spec] and TB.classes[token].specs[plan.spec].name) or plan.spec,
      plan.role:lower(), r.created, r.updated, r.same, r.placed, r.main)
    Say(msg)
    if r.edited > 0 then Say(r.edited .. " macro(s) were changed by you, so I left them alone. /realm macros force replaces them.") end
    if r.full > 0 then Say(r.full .. " macro(s) not made: your character macro slots are full (30 max). Delete some and run /realm macros again.") end
    if r.kept > 0 then Say(r.kept .. " bar slot(s) already hold something of yours, so I skipped them.") end
  end
  return true, r, plan
end

function M.Remove()
  if InCombatLockdown and InCombatLockdown() then Say("not in combat.") return end
  local st = Store()
  local gone, kept = 0, 0
  for bar = 1, 4 do
    for _, kind in pairs(LABEL) do
      local name = ("R%d %s"):format(bar, kind)
      local idx = GetMacroIndexByName(name)
      if idx and idx > 0 then
        local _, _, cur = GetMacroInfo(idx)
        if st.hashes[name] and st.hashes[name] == Hash(cur or "") then
          DeleteMacro(idx); st.hashes[name] = nil; gone = gone + 1
        else kept = kept + 1 end
      end
    end
  end
  st.installed = false
  Say(("removed %d macro(s); kept %d you changed."):format(gone, kept))
end

function M.Status()
  local st = Store()
  local _, cN = 0, 0
  if GetNumMacros then _, cN = GetNumMacros() end
  Say(("installed: %s%s. Autoupdate: %s. Character macro slots used: %d of %d."):format(
    st.installed and "yes" or "no", st.spec and (" (" .. st.spec .. ")") or "",
    M.AutoOn() and "ON" or "off", cN or 0, MaxChar()))
end

function M.Show(specArg)
  local token = TB.ClassToken()
  local cls = token and TB.classes[token]
  if not cls then Say("no guide for your class") return end
  local key
  if specArg and specArg ~= "" then
    for k, s in pairs(cls.specs) do if k:lower():find(specArg, 1, true) or s.name:lower():find(specArg, 1, true) then key = k end end
  end
  local plan, err = M.Plan(token, key)
  if not plan then Say(err) return end
  Say(("%s, %s set:"):format(plan.spec, plan.role:lower()))
  local bar = 0
  for _, m in ipairs(plan.list) do
    if m.bar ~= bar then bar = m.bar; print("  " .. BAR_TITLE[bar]) end
    print(("    %s  (%s)"):format(m.name, (m.body:gsub("\n", " | "))))
  end
  print("  Main bar: " .. (#plan.main > 0 and table.concat(plan.main, ", ", 1, math.min(#plan.main, 12)) or "none known yet"))
end

local function Help()
  Say("/realm macros            build or refresh your macros and bars for your current spec")
  print("  /realm macros status | show [spec] | spec <name> | force | remove")
  print("  /realm macros autoupdate on|off   (rebuild when you learn spells or change talents; default ON)")
end

function M.Command(arg)
  arg = (arg or ""):lower():match("^%s*(.-)%s*$")
  local sub, rest = arg:match("^(%S*)%s*(.-)$")
  if sub == "" or sub == "install" or sub == "update" then M.Install({})
  elseif sub == "force" then M.Install({ force = true })
  elseif sub == "status" then M.Status()
  elseif sub == "show" or sub == "list" then M.Show(rest)
  elseif sub == "remove" or sub == "uninstall" then M.Remove()
  elseif sub == "autoupdate" or sub == "auto" then
    if rest == "on" then M.SetAuto(true)
    elseif rest == "off" then M.SetAuto(false)
    else Say("autoupdate is " .. (M.AutoOn() and "ON" or "off") .. ". Use /realm macros autoupdate on|off.") return end
    Say("autoupdate " .. (M.AutoOn() and "ON: macros follow your newest spells after you learn them or change talents." or "off: macros stay as they are until you run /realm macros."))
    if M.SetAutoHook then M.SetAutoHook() end
  elseif sub == "spec" then
    local cls = TB.Class()
    local key
    if cls then for k, s in pairs(cls.specs) do if k:lower():find(rest, 1, true) or s.name:lower():find(rest, 1, true) then key = k end end end
    if not key or rest == "" then Say("unknown spec '" .. rest .. "'") return end
    M.Install({ spec = key })
  else Help() end
end

-- ------------------------------------------------------------ autoupdate
-- New spell, new rank, talent change, spec change or level up: rebuild after combat. Does nothing when the toggle is off
-- or nothing was ever installed.
local pending
function M.AutoRefresh()
  if not (TB.DB and TB.Char and TB.Class()) then return end
  local st = Store()
  if not st.installed or not M.AutoOn() then return end
  M.Install({ quiet = true, auto = true })
end

local function Schedule()
  if pending then return end
  pending = true
  C_Timer.After(2, function() pending = false; M.AutoRefresh() end)
end
M.Schedule = Schedule

local ev = CreateFrame("Frame")
for _, e in ipairs({ "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, e)
  if e == "PLAYER_REGEN_ENABLED" then
    if M.queued then
      local o = M.queue
      M.queued, M.queue = false, nil
      if o and (not o.auto or M.AutoOn()) then M.Install(o) end
    end
    return
  end
  Schedule()
end)
TB.Listen("SPEC_CHANGED", Schedule)
