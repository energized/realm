-- Quest mob targeting. Keeps a macro named "RealmTarget" up to date with the mob for your current step
-- (lowest level first). Drag it from /macro to an action bar, or /path key <KEY> to bind a key.
-- Also shows a small TAKEN tag when your target is already tagged by someone else.
local ADDON, ns = ...
local Path = ns.Path
local UI = ns.UI

local MACRO = "RealmTarget"
local ICON = "INV_Misc_QuestionMark"
local macroText

local function Names()
  local s = Path.RealStep and Path.RealStep()
  if not s or s.t ~= "D" then return nil end
  local list = {}
  if s.kind == "kill" and s.npc then list[1] = s.npc
  elseif s.kind == "item" and s.mobs then for _, n in ipairs(s.mobs) do list[#list + 1] = n end end
  if #list == 0 then return nil end
  return list
end
Path.TargetNames = Names

local function Body()
  local list = Names()
  if not list then return "/script print('Realm: no mob to target on this step')" end
  local lines = {}
  for i, n in ipairs(list) do
    if i == 1 then lines[#lines + 1] = "/target " .. n
    else lines[#lines + 1] = "/target [noharm][dead] " .. n end
  end
  return table.concat(lines, "\n")
end

local function Sync()
  if InCombatLockdown and InCombatLockdown() then return end
  if not (GetMacroIndexByName and CreateMacro and EditMacro) then return end
  local body = Body()
  if body == macroText then return end
  local idx = GetMacroIndexByName(MACRO)
  local ok
  if idx and idx > 0 then ok = pcall(EditMacro, idx, MACRO, nil, body)
  else ok = pcall(CreateMacro, MACRO, ICON, body, false) end
  if ok then macroText = body end
end

local owner = CreateFrame("Frame")
local function ApplyKey()
  if InCombatLockdown and InCombatLockdown() then return end
  if ClearOverrideBindings then ClearOverrideBindings(owner) end
  local k = Path.Opts() and Path.Opts().targetKey
  if k and k ~= "" and SetOverrideBindingMacro then SetOverrideBindingMacro(owner, false, k, MACRO) end
end

-- ---------------------------------------------------------------- the TAKEN tag
local warn
local function Taken()
  if not (UnitExists and UnitExists("target")) then return false end
  if UnitIsDead and UnitIsDead("target") then return false end
  if not (UnitCanAttack and UnitCanAttack("player", "target")) then return false end
  if UnitIsTapDenied and UnitIsTapDenied("target") then return true end
  if UnitAffectingCombat and UnitAffectingCombat("target") and UnitExists("targettarget")
     and UnitIsPlayer("targettarget") and not UnitIsUnit("targettarget", "player")
     and not (UnitInParty and UnitInParty("targettarget")) then return true end
  return false
end

local function Warn()
  if warn then return warn end
  warn = CreateFrame("Frame", nil, UIParent)
  warn:SetSize(120, 20); warn:SetFrameStrata("HIGH")
  warn.bg = warn:CreateTexture(nil, "BACKGROUND"); warn.bg:SetAllPoints()
  warn.bg:SetColorTexture(UI.C.red[1], UI.C.red[2], UI.C.red[3], .85)
  warn.t = warn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  warn.t:SetPoint("CENTER"); warn.t:SetTextColor(1, 1, 1)
  if warn.t.SetFont then warn.t:SetFont(UI.FONT, 14, "OUTLINE") end
  warn.t:SetText("TAKEN")
  warn:SetPoint("TOP", UIParent, "TOP", 0, -190)
  warn:Hide()
  return warn
end

local function Place()
  if InCombatLockdown and InCombatLockdown() then return end
  local pn = _G.RealmCompassPanel
  local b = pn and pn.GetBottom and pn:GetBottom()
  local top = UIParent:GetTop()
  if b and top then warn:ClearAllPoints(); warn:SetPoint("TOP", UIParent, "TOP", 0, -(top - b + 4)) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN"); f:RegisterEvent("PLAYER_REGEN_ENABLED"); f:RegisterEvent("PLAYER_TARGET_CHANGED")
for _, e in ipairs({ "UNIT_FLAGS", "UNIT_DYNAMIC_FLAGS", "UNIT_TARGET" }) do pcall(f.RegisterEvent, f, e) end
f:SetScript("OnEvent", function(_, ev)
  local O = Path.Opts()
  if not O then return end
  if ev == "PLAYER_LOGIN" then Warn(); ApplyKey(); Sync(); return end
  if ev == "PLAYER_REGEN_ENABLED" then ApplyKey(); Sync(); return end
  if O.tapWarn == false then return end
  Warn(); Place()
  warn:SetShown(Taken())
end)

-- keep the macro in step with the route (never in combat)
Path.OnChange(function() Sync() end)
local acc = 0
f:SetScript("OnUpdate", function(_, dt)
  acc = acc + dt
  if acc >= 0.5 then acc = 0; if Path.Opts() then Sync() end end
end)

function Path.SetTargetKey(k)
  local O = Path.Opts()
  if not O then return end
  O.targetKey = k
  ApplyKey()
end

local old = Path.SlashExtra
function Path.SlashExtra(cmd, rest)
  if cmd == "key" then
    if rest == "" or rest == "off" then Path.SetTargetKey(nil); Path.Print("target key cleared")
    else Path.SetTargetKey(rest:upper()); Path.Print("quest mob target key = " .. rest:upper()) end
    return true
  elseif cmd == "target" then
    local l = Names()
    Path.Print(l and ("targeting: " .. table.concat(l, ", ")) or "this step has no mob to target")
    Path.Print("macro: " .. MACRO .. " (see /macro). Bind a key: /path key <KEY>")
    return true
  end
  if old then return old(cmd, rest) end
end
