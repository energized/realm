-- TheBoys / Realm macros: builds the five main-bar page macro sets for the player's class and spec.
--   Main bar page 1 solo / leveling, page 2 party, page 3 battlegrounds, page 4 small dungeon, page 5 raid.
-- Real macros only (CreateMacro / EditMacro). Nothing runs in combat: work is queued until it ends.
-- Macros the player edited are never overwritten (a saved hash tells us), and occupied slots are never taken
-- unless the player agreed to it in the setup question (opts.take) or ran /realm macros force.
-- Commands: /realm macros   (also /boys macros)
local ADDON, ns = ...
local TB = ns.TB
local M = {}
TB.Macros = M

local BODY_MAX, ICON = 255, 134400
-- at most 7 macros per page. Identical macros on several pages are created once and placed on each page,
-- so a full set stays inside the 30 character macro slots.
local PER_BAR = 7
local function MaxChar() return type(MAX_CHARACTER_MACROS) == "number" and MAX_CHARACTER_MACROS or 30 end

-- Action slots. Everything lives on the MAIN bar and its pages (scroll the main bar, or use the page arrows):
--   page 1 = slots 1-12   solo / leveling
--   page 2 = slots 13-24  party
--   page 3 = slots 25-36  battlegrounds
--   page 4 = slots 37-48  small dungeon groups
--   page 5 = slots 49-60  raids
-- Pages 3-5 share their slots with the Right / Right 2 / Bottom Right bars, so keep those side bars switched off
-- in Game Menu > Options > Action Bars or you will see the same buttons twice.
local PAGES = 5
local BAR_FIRST = { 1, 13, 25, 37, 49 }
M.BAR_FIRST = BAR_FIRST
M.PAGES = PAGES
local BAR_TITLE = { "Main bar page 1 (solo)", "Page 2 (party)", "Page 3 (battlegrounds)", "Page 4 (small dungeon)", "Page 5 (raid)" }

local LABEL = {
  st = "Single", fin = "Finisher", dot = "DoTs", aoe = "AoE", burst = "Burst", def = "Defense", int = "Interrupt",
  cc = "CC", taunt = "Taunt", heal = "Self Heal", heal1 = "Fast Heal", heal2 = "Big Heal", hot = "HoT",
  aoeheal = "Group Heal", dispel = "Dispel", buff = "Buffs", mob = "Mobility", open = "Opener", util = "Utility",
}
M.LABEL = LABEL

-- per page, in rotation order: the macros read left to right in the order you press them
local TEMPLATE = {
  DPS = {
    { "st", "fin", "dot", "aoe", "def", "buff", "heal", "open", "mob" },
    { "st", "fin", "dot", "aoe", "burst", "int", "def", "cc" },
    { "st", "fin", "dot", "burst", "int", "def", "cc", "mob" },
    { "aoe", "st", "dot", "fin", "burst", "int", "def", "cc" },
    { "st", "fin", "dot", "aoe", "burst", "int", "def", "util" },
  },
  HEALER = {
    { "st", "aoe", "def", "heal", "buff", "mob", "open" },
    { "heal1", "heal2", "hot", "aoeheal", "dispel", "burst", "def" },
    { "heal1", "heal2", "hot", "dispel", "cc", "def", "mob" },
    { "heal1", "heal2", "hot", "aoeheal", "dispel", "cc", "def" },
    { "heal1", "heal2", "hot", "aoeheal", "dispel", "burst", "def" },
  },
  TANK = {
    { "st", "aoe", "def", "heal", "buff", "mob", "open" },
    { "st", "aoe", "taunt", "int", "cc", "def", "burst" },
    { "st", "aoe", "int", "cc", "def", "mob", "burst" },
    { "aoe", "taunt", "st", "int", "cc", "def", "burst" },
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

-- other useful spells for the spare slots of every page
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

-- plan.list  = the distinct macros to create (a macro that is identical on two pages is listed once)
-- plan.place = where each one goes: { bar = page, pos = position on the page, m = macro }
-- plan.used[bar] = how many positions the macros take on that page
function M.Plan(token, key)
  token = token or TB.ClassToken()
  local cls = token and TB.classes[token]
  if not cls then return nil, "no guide for your class" end
  if not key then local _; _, key = TB.Spec() end
  local spec = cls.specs[key]
  local d = TB.MacroData and TB.MacroData[token] and TB.MacroData[token][key]
  if not (spec and d) then return nil, "no macro data for " .. tostring(token) .. " " .. tostring(key) end
  local role = Role(spec.role)
  local plan = { class = token, spec = key, role = role, list = {}, place = {}, used = {} }
  local seen = {}
  for bar = 1, PAGES do
    local pos = 0
    for _, kind in ipairs(TEMPLATE[role][bar]) do
      local body = d[kind] and Build(kind, d[kind], d, bar)
      if body and pos < PER_BAR then
        pos = pos + 1
        local sig = kind .. "\0" .. body
        local m = seen[sig]
        if not m then
          m = { bar = bar, pos = pos, kind = kind, name = ("R%d %s"):format(bar, LABEL[kind]), body = body }
          seen[sig] = m
          plan.list[#plan.list + 1] = m
        end
        plan.place[#plan.place + 1] = { bar = bar, pos = pos, m = m }
      end
    end
    plan.used[bar] = pos
  end
  plan.main = MainList(cls, spec, d)
  return plan
end

-- ------------------------------------------------------------ saved state (per character)
local function Store()
  local r = TB.Char()
  r.macros = r.macros or {}
  r.macros.hashes = r.macros.hashes or {}
  r.macros.fill = r.macros.fill or {}
  return r.macros
end
M.Store = Store

-- how many main-bar pages get macros: default 2 (page 1 solo, page 2 party); the other pages stay empty for you.
-- Macros for every page are still created, so you can drag battleground, dungeon and raid ones from /macro.
local function PlacePages()
  local n = tonumber(Store().pages) or 2
  return math.max(1, math.min(PAGES, math.floor(n)))
end
M.PlacePages = PlacePages

function M.AutoOn() return Store().auto ~= false end      -- default ON
function M.SetAuto(v) Store().auto = v and true or false end

-- ------------------------------------------------------------ install
local function SpellId(name)
  local _, _, id = TB.Spell(name)
  return id
end

local function PickupSpellByName(name)
  local id = SpellId(name)
  if C_Spell and C_Spell.PickupSpell and id then pcall(C_Spell.PickupSpell, id) return true end
  if PickupSpell and (id or name) then pcall(PickupSpell, id or name) return true end
end

-- is this spell already on one of the 12 buttons of a page?
local function PageHas(first, id)
  if not id then return false end
  for s = first, first + 11 do
    local t, a = GetActionInfo(s)
    if t == "spell" and a == id then return true end
  end
  return false
end

local function OurMacro(slot)
  local t, id = GetActionInfo(slot)
  if t ~= "macro" then return false end
  local nm = GetMacroInfo(id)
  return (nm and nm:match("^R[1-5] ")) and true or false
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
  local r = { created = 0, updated = 0, same = 0, edited = 0, full = 0, placed = 0, kept = 0, main = 0, cleared = 0 }
  local nPages = PlacePages()

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

  local take = opts.take or opts.force
  if PlaceAction and PickupMacro and GetActionInfo then
    -- 1) the macros, in rotation order, left to right on each page
    for _, p in ipairs(plan.place) do
      local m = p.m
      local idx = (p.bar <= nPages and not m.skip) and GetMacroIndexByName(m.name) or 0
      if idx > 0 then
        local slot = BAR_FIRST[p.bar] + p.pos - 1
        local t, id = GetActionInfo(slot)
        local ours = OurMacro(slot) or (t == "spell" and st.fill[slot] and st.fill[slot] == id)
        if t == "macro" and id == idx then
          -- already there
        elseif (not t) or ours or take then
          PickupMacro(idx); PlaceAction(slot); if ClearCursor then ClearCursor() end
          st.fill[slot] = nil
          r.placed = r.placed + 1
        else
          r.kept = r.kept + 1
        end
      end
    end
    -- 2) take back what an earlier version put where you did not ask for it: spare-button spells (unless
    --    /realm macros fill on) and our own macros on pages beyond the ones in use. Your own buttons are never touched.
    if PickupAction then
      for slot = 1, PAGES * 12 do
        local page = math.floor((slot - 1) / 12) + 1
        local t, id = GetActionInfo(slot)
        if t then
          local filler = t == "spell" and st.fill[slot] and st.fill[slot] == id and ((not st.useFill) or page > nPages)
          local stray = t == "macro" and page > nPages and OurMacro(slot)
          if filler or stray then
            PickupAction(slot); if ClearCursor then ClearCursor() end
            st.fill[slot] = nil; r.cleared = r.cleared + 1
          end
        end
      end
    end
    -- 3) optional (/realm macros fill on): other useful spells in the spare buttons of the pages in use
    for bar = 1, (st.useFill and nPages or 0) do
      local first = BAR_FIRST[bar]
      local s = first + (plan.used[bar] or 0)
      for _, name in ipairs(plan.main) do
        local id = SpellId(name)
        if not PageHas(first, id) then
          while s <= first + 11 and GetActionInfo(s) do s = s + 1 end
          if s > first + 11 then break end
          if PickupSpellByName(name) then
            PlaceAction(s); if ClearCursor then ClearCursor() end
            if GetActionInfo(s) then st.fill[s] = id; r.main = r.main + 1 end
          end
        end
      end
    end
  end

  st.installed, st.spec, st.dataVersion = true, plan.spec, TB.MacroDataVersion
  local changed = r.created + r.updated + r.placed + r.main
  if not (opts.quiet and changed == 0) then
    local msg = ("%s %s: %d created, %d updated, %d unchanged, %d placed on main bar page%s 1-%d (the rest of each page is left for you)."):format(
      (TB.classes[token] and TB.classes[token].specs[plan.spec] and TB.classes[token].specs[plan.spec].name) or plan.spec,
      plan.role:lower(), r.created, r.updated, r.same, r.placed, nPages > 1 and "s" or "", nPages)
    Say(msg)
    if r.main > 0 then Say(r.main .. " spare-button spells added (fill is on).") end
    if r.cleared > 0 then Say(r.cleared .. " button(s) I filled earlier were cleared so the spare spaces are yours.") end
    if r.edited > 0 then Say(r.edited .. " macro(s) were changed by you, so I left them alone. /realm macros force replaces them.") end
    if r.full > 0 then Say(r.full .. " macro(s) not made: your character macro slots are full (30 max). Delete some and run /realm macros again.") end
    if r.kept > 0 then Say(r.kept .. " button(s) already hold something of yours, so I skipped them. /realm macros take puts the macros there anyway.") end
  end
  return true, r, plan
end

function M.Remove()
  if InCombatLockdown and InCombatLockdown() then Say("not in combat.") return end
  local st = Store()
  local gone, kept = 0, 0
  for bar = 1, PAGES do
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
  for _, p in ipairs(plan.place) do
    if p.bar ~= bar then bar = p.bar; print("  " .. BAR_TITLE[bar]) end
    print(("    %d. %s  (%s)"):format(p.pos, p.m.name, (p.m.body:gsub("\n", " | "))))
  end
  print("  Spare buttons: " .. (#plan.main > 0 and table.concat(plan.main, ", ", 1, math.min(#plan.main, 12)) or "none known yet"))
end

local function Help()
  Say("/realm macros            build or refresh your macros on the main bar pages for your current spec")
  print("  Default: page 1 = solo, page 2 = party. Only the rotation macros are placed; empty buttons stay yours.")
  print("  /realm macros pages 3|4|5 also places battlegrounds, small dungeon, raid.  /realm macros fill on adds spare spells.")
  print("  /realm macros status | show [spec] | spec <name> | force | take | remove")
  print("  /realm macros autoupdate on|off   (rebuild when you learn spells or change talents; default ON)")
  print("  /realm macros take      put the macros in the first buttons of each page even if something is there")
end

function M.Command(arg)
  arg = (arg or ""):lower():match("^%s*(.-)%s*$")
  local sub, rest = arg:match("^(%S*)%s*(.-)$")
  if sub == "" or sub == "install" or sub == "update" then M.Install({})
  elseif sub == "force" then M.Install({ force = true })
  elseif sub == "take" then M.Install({ take = true })
  elseif sub == "status" then M.Status()
  elseif sub == "show" or sub == "list" then M.Show(rest)
  elseif sub == "remove" or sub == "uninstall" then M.Remove()
  elseif sub == "pages" then
    local n = tonumber(rest)
    if not n or n < 1 or n > PAGES then Say("pages is " .. PlacePages() .. ". Use /realm macros pages 1-5 (1 solo, 2 party, 3 battlegrounds, 4 small dungeon, 5 raid).") return end
    Store().pages = math.floor(n)
    Say("macros go on main bar pages 1-" .. PlacePages() .. ".")
    M.Install({})
  elseif sub == "fill" then
    if rest == "on" then Store().useFill = true
    elseif rest == "off" then Store().useFill = false
    else Say("fill is " .. (Store().useFill and "ON" or "off") .. ". Use /realm macros fill on|off (spare spells in empty buttons).") return end
    Say("fill " .. (Store().useFill and "ON: spare buttons get other useful spells." or "off: spare buttons are left for you."))
    M.Install({})
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
