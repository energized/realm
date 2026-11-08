-- TheBoys: heal bar. One cell for you and one for each party member, each showing health.
-- Click a cell to heal that person. Right click casts your fast heal, Alt + left click your heal over time.
-- What each click casts can be changed: right click the green strip, or /boys heals set <click> <spell>.
-- Every cell is armed once, out of combat, and never re-aimed, because the game blocks changing these
-- buttons in combat. In combat only colors and text change, so the bar keeps working mid-fight.
local ADDON, ns = ...
local TB = ns.TB
local HL = {}
TB.Heals = HL

local SIZE, GAP, GRIP = 40, 4, 10
local URGENT = 35 -- below this percent the cell turns red

-- heal  the main heal, first one you know wins
-- fast  quicker, costlier heal for emergencies (right click)
-- hot   heal over time (Alt + left click)
-- Classes with no entry (warrior, rogue, mage, warlock, hunter) have no heal bar.
local DATA = {
  PALADIN = { heal = { "Holy Light" }, fast = { "Flash of Light" },
              extra = { "Lay on Hands", "Cleanse", "Purify", "Blessing of Protection", "Blessing of Freedom", "Redemption" } },
  PRIEST  = { heal = { "Heal", "Lesser Heal" }, fast = { "Flash Heal" }, hot = { "Renew" },
              extra = { "Power Word: Shield", "Cure Disease", "Abolish Disease", "Dispel Magic", "Resurrection" } },
  DRUID   = { heal = { "Healing Touch" }, fast = { "Regrowth" }, hot = { "Rejuvenation" },
              extra = { "Mark of the Wild", "Thorns", "Remove Curse", "Cure Poison", "Abolish Poison", "Rebirth", "Innervate" } },
  SHAMAN  = { heal = { "Healing Wave" }, fast = { "Lesser Healing Wave" },
              extra = { "Cure Poison", "Cure Disease", "Ancestral Spirit" } },
}
HL.DATA = DATA

-- the five click slots, in the order the settings panel shows them
-- key is stored in TB.DB.healClicks; prefix and btn build the secure attribute names
local SLOTS = {
  { key = "click", label = "Click",       prefix = "",       btn = 1 },
  { key = "right", label = "Right click", prefix = "",       btn = 2 },
  { key = "shift", label = "Shift click", prefix = "shift-", btn = 1 },
  { key = "ctrl",  label = "Ctrl click",  prefix = "ctrl-",  btn = 1 },
  { key = "alt",   label = "Alt click",   prefix = "alt-",   btn = 1 },
}
HL.SLOTS = SLOTS

local UNITS = { "player", "party1", "party2", "party3", "party4" }
local bar, grip, cells = nil, nil, {}
local armedSig, dirty = nil, true

local function Now() return (GetTime and GetTime()) or os.clock() end

local function First(list)
  for _, n in ipairs(list or {}) do
    if TB.Known(n) then return n end
  end
end

-- the three spells this character can use right now
function HL.Spells()
  local set = DATA[TB.ClassToken() or ""]
  if not set then return nil end
  local heal = First(set.heal)
  if not heal then return nil end
  return { heal = heal, fast = First(set.fast), hot = First(set.hot) }
end

-- what each slot does when the player has not chosen anything
local function Default(sp, key)
  if key == "click" then return sp.heal end
  if key == "right" then return sp.fast or sp.heal end
  if key == "alt" then return sp.hot end
  return nil -- shift and ctrl fall back to a plain click
end

-- what each slot will really do: a spell name, false for "do nothing", or nil for "left alone"
function HL.Effective(sp)
  local eff = {}
  local pick = TB.DB.healClicks or {}
  for _, s in ipairs(SLOTS) do
    local v = pick[s.key]
    if v == "none" then
      eff[s.key] = false
    elseif v and v ~= "auto" and TB.Known(v) then
      eff[s.key] = v
    else
      eff[s.key] = Default(sp, s.key)
    end
  end
  return eff
end

-- spells the player can pick for a click: the heals plus a few useful utility spells they know
function HL.Choices()
  local set = DATA[TB.ClassToken() or ""]
  local out, seen = { "auto" }, {}
  if set then
    for _, group in ipairs({ set.heal, set.fast, set.hot or {}, set.extra or {} }) do
      for _, n in ipairs(group) do
        if not seen[n] and TB.Known(n) then seen[n] = true; out[#out + 1] = n end
      end
    end
  end
  out[#out + 1] = "none"
  return out
end

local function Pct(unit)
  local ok, v = pcall(function()
    local h, m = UnitHealth(unit), UnitHealthMax(unit)
    if type(h) ~= "number" or type(m) ~= "number" or m <= 0 then return nil end
    return math.floor(h / m * 100 + 0.5)
  end)
  if ok then return v end
end

-- the client hides some unit answers (a "secret" value) from addon code; a secret cannot be tested, so it never excludes a unit
local function Plain(v) return not (issecretvalue and issecretvalue(v)) end

local function Eligible(unit)
  if not UnitExists or not UnitExists(unit) then return false end
  if UnitIsConnected then
    local c = UnitIsConnected(unit)
    if Plain(c) and c == false then return false end
  end
  if UnitIsDeadOrGhost then
    local d = UnitIsDeadOrGhost(unit)
    if Plain(d) and d then return false end
  end
  if UnitInRange then
    local ok, inRange, checked = pcall(UnitInRange, unit)
    if ok and Plain(inRange) and Plain(checked) and checked and not inRange then return false end
  end
  return true
end

local function Quiet()
  if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return true end
  if IsMounted and IsMounted() then return true end
  if UnitOnTaxi and UnitOnTaxi("player") then return true end
  if UnitInVehicle and UnitInVehicle("player") then return true end
  return false
end

-- one row per person who can be healed right now, keyed by cell number
function HL.Scan()
  local rows = {}
  local below = TB.DB.healBelow or 70
  local raid = IsInRaid and IsInRaid()
  for i, u in ipairs(UNITS) do
    if i == 1 or (not raid and Eligible(u)) then
      local pct = Pct(u)
      if pct or i == 1 then
        local name = (i == 1) and "You" or ((UnitName and UnitName(u)) or u)
        rows[i] = { unit = u, name = name, pct = pct, hurt = pct and pct < below or false, urgent = pct and pct < URGENT or false }
      end
    end
  end
  return rows
end

-- ---------------------------------------------------------------- cells
local function Arm(c, sp)
  local eff = HL.Effective(sp)
  for _, s in ipairs(SLOTS) do
    local p, b, v = s.prefix, s.btn, eff[s.key]
    if v then
      c:SetAttribute(p .. "type" .. b, "spell"); c:SetAttribute(p .. "spell" .. b, v)
      c:SetAttribute(p .. "unit" .. b, c.unit); c:SetAttribute(p .. "macrotext" .. b, nil)
    elseif v == false then
      -- "none": an empty macro, so the click does nothing instead of falling back to another slot
      c:SetAttribute(p .. "type" .. b, "macro"); c:SetAttribute(p .. "macrotext" .. b, "")
      c:SetAttribute(p .. "spell" .. b, nil); c:SetAttribute(p .. "unit" .. b, nil)
    else
      c:SetAttribute(p .. "type" .. b, nil); c:SetAttribute(p .. "spell" .. b, nil)
      c:SetAttribute(p .. "unit" .. b, nil); c:SetAttribute(p .. "macrotext" .. b, nil)
    end
  end
end

local function Tip(self)
  if not GameTooltip then return end
  local sp = HL.spells
  if not sp then return end
  local row = HL.rows and HL.rows[self.index]
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:AddLine(row and row.name or "Heal", 1, 1, 1)
  if row then GameTooltip:AddLine((row.pct and (row.pct .. "% health") or "health unknown"), .8, .8, .8) end
  local eff = HL.eff or HL.Effective(sp)
  for _, s in ipairs(SLOTS) do
    local v = eff[s.key]
    if v then
      GameTooltip:AddLine(s.label .. ": " .. v, .6, 1, .6)
    elseif v == false then
      GameTooltip:AddLine(s.label .. ": nothing", .6, .6, .6)
    end
  end
  GameTooltip:Show()
end

local function MakeCell(i)
  local c = CreateFrame("Button", nil, bar, "SecureActionButtonTemplate")
  c.index, c.unit = i, UNITS[i]
  c:SetSize(SIZE, SIZE)
  c.bg = c:CreateTexture(nil, "BACKGROUND")
  c.bg:SetAllPoints(); c.bg:SetColorTexture(0, 0, 0, .6)
  c.icon = c:CreateTexture(nil, "ARTWORK")
  c.icon:SetAllPoints(); c.icon:SetTexCoord(.07, .93, .07, .93)
  c.glow = c:CreateTexture(nil, "OVERLAY")
  c.glow:SetPoint("TOPLEFT", -3, 3); c.glow:SetPoint("BOTTOMRIGHT", 3, -3)
  c.glow:SetDrawLayer("BACKGROUND")
  c.name = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  c.name:SetPoint("TOP", 0, -2)
  c.pct = c:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  c.pct:SetPoint("BOTTOM", 0, 2)
  if not pcall(c.RegisterForClicks, c, "AnyUp", "AnyDown") then c:RegisterForClicks("AnyUp") end
  c:SetScript("OnEnter", Tip)
  c:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return c
end

-- colors and text only: allowed in combat
local function Paint(c, row)
  if not row then
    c.name:SetText(""); c.pct:SetText("--")
    c:SetAlpha(.2); c.glow:SetColorTexture(0, 0, 0, 0)
    c.state = nil
    return
  end
  c.name:SetText(string.sub(row.name or "", 1, 7))
  c.pct:SetText(row.pct and (row.pct .. "%") or "?")
  if row.urgent then
    c.glow:SetColorTexture(1, .15, .1, .7); c.pct:SetTextColor(1, .3, .25); c:SetAlpha(1); c.state = "urgent"
  elseif row.hurt then
    c.glow:SetColorTexture(1, .65, .1, .6); c.pct:SetTextColor(1, .85, .3); c:SetAlpha(1); c.state = "hurt"
  else
    c.glow:SetColorTexture(0, 0, 0, 0); c.pct:SetTextColor(.5, 1, .55); c:SetAlpha(.85); c.state = "ok"
  end
end

function HL.Refresh()
  if not bar then return end
  local combat = InCombatLockdown()
  local on = TB.DB.healBar ~= false and not Quiet()
  local rows = HL.Scan()
  HL.rows = rows
  local sp = HL.Spells()

  if not combat then
    HL.spells = sp
    if sp then
      local eff = HL.Effective(sp)
      HL.eff = eff
      local parts = {}
      for _, s in ipairs(SLOTS) do
        local v = eff[s.key]
        parts[#parts + 1] = (v == false) and "!" or (v or "-")
      end
      local sig = table.concat(parts, "|")
      if sig ~= armedSig then
        armedSig = sig
        for _, c in ipairs(cells) do Arm(c, sp) end
        for _, c in ipairs(cells) do c.icon:SetTexture(TB.Icon(eff.click or sp.heal)) end
      end
    end
    -- lay out one cell per person who can be healed
    local n = 0
    for i, c in ipairs(cells) do
      if rows[i] and sp then
        n = n + 1
        c:ClearAllPoints()
        c:SetPoint("LEFT", bar, "LEFT", GRIP + 4 + (n - 1) * (SIZE + GAP), 0)
        c:Show()
      else
        c:Hide()
      end
    end
    bar:SetSize(GRIP + 4 + math.max(n, 1) * (SIZE + GAP), SIZE)
    bar:SetAlpha(1)
    if on and sp then bar:Show() else bar:Hide() end
  else
    -- combat: nothing may be shown, hidden or moved, so only the alpha of the whole bar changes
    bar:SetAlpha((on and HL.spells) and 1 or 0)
  end

  for i, c in ipairs(cells) do Paint(c, rows[i]) end
end

local function Build()
  bar = TB.NewFrame("Frame", "TheBoysHealBar", UIParent)
  bar:SetSize(GRIP + 4 + SIZE + GAP, SIZE)
  bar:SetMovable(true); bar:SetClampedToScreen(true)
  local pos = TB.DB.healPos
  if pos then bar:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else bar:SetPoint("CENTER", UIParent, "CENTER", 0, -190) end

  grip = CreateFrame("Button", nil, bar)
  grip:SetSize(GRIP, SIZE)
  grip:SetPoint("LEFT", bar, "LEFT", 0, 0)
  bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  bar.label:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 2)
  bar.label:SetText("Heal bar")
  grip.bg = grip:CreateTexture(nil, "BACKGROUND")
  grip.bg:SetAllPoints(); grip.bg:SetColorTexture(.2, .7, .35, .6)
  grip:RegisterForDrag("LeftButton")
  grip:RegisterForClicks("RightButtonUp")
  grip:SetScript("OnClick", function(_, button)
    if button == "RightButton" then HL.TogglePanel() end
  end)
  grip:SetScript("OnDragStart", function()
    if not TB.DB.healLocked and not InCombatLockdown() then bar:StartMoving() end
  end)
  grip:SetScript("OnDragStop", function()
    bar:StopMovingOrSizing()
    local p, _, rp, x, y = bar:GetPoint()
    TB.DB.healPos = { p, rp, x, y }
  end)
  grip:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Heal bar", 1, 1, 1)
    GameTooltip:AddLine("Drag to move. /boys heals lock to pin it.", .7, .7, .7, true)
    GameTooltip:AddLine("Right click: choose what each click casts.", .6, 1, .6, true)
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  for i = 1, #UNITS do cells[i] = MakeCell(i) end

  local acc = 0
  bar:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc >= 0.25 then acc = 0; dirty = false; HL.Refresh() end
    local a = .5 + .3 * math.sin(Now() * 5)
    for _, c in ipairs(cells) do
      if c.state == "urgent" or c.state == "hurt" then c.glow:SetAlpha(a) end
    end
  end)
  bar:Hide()
end

-- ---------------------------------------------------------------- click settings panel
local panel, rowsUI = nil, {}

local function ChoiceText(sp, s)
  local v = (TB.DB.healClicks or {})[s.key]
  if v == "none" then return "Nothing" end
  if v and v ~= "auto" and TB.Known(v) then return v end
  local d = Default(sp, s.key)
  return "Default (" .. (d or "same as Click") .. ")"
end

local function PanelRefresh()
  if not panel then return end
  local sp = HL.Spells()
  if not sp then return end
  for i, s in ipairs(SLOTS) do
    rowsUI[i].btn:SetText(ChoiceText(sp, s))
  end
end

-- step one slot to the next (or previous) choice
function HL.Cycle(key, step)
  local list = HL.Choices()
  local pick = TB.DB.healClicks or {}
  TB.DB.healClicks = pick
  local cur, idx = pick[key] or "auto", 1
  for i, n in ipairs(list) do if n == cur then idx = i end end
  idx = ((idx - 1 + (step or 1)) % #list) + 1
  pick[key] = list[idx]
  if pick[key] == "auto" then pick[key] = nil end
  HL.Refresh(); PanelRefresh()
end

local function BuildPanel()
  panel = TB.NewFrame("Frame", "TheBoysHealClicks", UIParent)
  panel:SetSize(290, 40 + #SLOTS * 28 + 56)
  panel:SetFrameStrata("DIALOG")
  panel:SetClampedToScreen(true)
  panel:SetPoint("BOTTOM", bar, "TOP", 0, 26)
  TB.Skin(panel)
  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -10)
  title:SetText("Heal bar clicks")
  for i, s in ipairs(SLOTS) do
    local y = -34 - (i - 1) * 28
    local lab = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lab:SetPoint("TOPLEFT", 12, y - 5)
    lab:SetText(s.label)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(176, 22)
    b:SetPoint("TOPRIGHT", -10, y)
    pcall(b.RegisterForClicks, b, "LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(_, button) HL.Cycle(s.key, button == "RightButton" and -1 or 1) end)
    rowsUI[i] = { label = lab, btn = b }
  end
  local note = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  note:SetPoint("BOTTOM", 0, 38)
  note:SetWidth(270)
  note:SetText("Left click a button for the next spell, right click for the previous. Changes apply out of combat.")
  local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  reset:SetSize(110, 22); reset:SetPoint("BOTTOMLEFT", 10, 10); reset:SetText("Defaults")
  reset:SetScript("OnClick", function() HL.ResetClicks() end)
  local close = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  close:SetSize(110, 22); close:SetPoint("BOTTOMRIGHT", -10, 10); close:SetText("Close")
  close:SetScript("OnClick", function() panel:Hide() end)
  panel:Hide()
end

function HL.ResetClicks()
  TB.DB.healClicks = nil
  HL.Refresh(); PanelRefresh()
end

function HL.TogglePanel()
  if not HL.Spells() then
    TB.Print("no heal bar for this character (no heal spell known)")
    return
  end
  if not panel then BuildPanel() end
  if panel:IsShown() then panel:Hide() else PanelRefresh(); panel:Show() end
end

-- ---------------------------------------------------------------- commands
function HL.Command(rest)
  rest = rest or ""
  local DB = TB.DB
  local word, arg = rest:match("^(%S*)%s*(.-)$")
  if word == "" then
    DB.healBar = not (DB.healBar ~= false)
    HL.Refresh()
    TB.Print("heal bar " .. (DB.healBar ~= false and "on" or "off"))
  elseif word == "below" then
    local n = tonumber(arg)
    if not n or n < 10 or n > 95 then
      TB.Print("usage: /boys heals below <10-95>   (now " .. (DB.healBelow or 70) .. ")")
    else
      DB.healBelow = math.floor(n)
      HL.Refresh()
      TB.Print("cells light up below " .. DB.healBelow .. "% health")
    end
  elseif word == "lock" then
    DB.healLocked = not DB.healLocked
    TB.Print("heal bar " .. (DB.healLocked and "locked" or "unlocked: drag the green strip"))
  elseif word == "reset" then
    DB.healPos = nil
    if bar and not InCombatLockdown() then bar:ClearAllPoints(); bar:SetPoint("CENTER", UIParent, "CENTER", 0, -190) end
    TB.Print("heal bar moved back to the default spot")
  elseif word == "clicks" then
    HL.TogglePanel()
  elseif word == "set" then
    local slotWord, spell = arg:match("^(%S+)%s*(.-)$")
    local slot
    for _, s in ipairs(SLOTS) do if s.key == (slotWord or ""):lower() then slot = s end end
    if not slot or spell == "" then
      TB.Print("usage: /boys heals set <click|right|shift|ctrl|alt> <spell name|auto|none>")
      return
    end
    DB.healClicks = DB.healClicks or {}
    local low = spell:lower()
    if low == "auto" or low == "default" then
      DB.healClicks[slot.key] = nil
      TB.Print(slot.label .. " is back to its default")
    elseif low == "none" then
      DB.healClicks[slot.key] = "none"
      TB.Print(slot.label .. " now does nothing")
    else
      local n = TB.Spell(spell)
      if not n or not TB.Known(n) then
        TB.Print("you do not know a spell called \"" .. spell .. "\"")
        return
      end
      DB.healClicks[slot.key] = n
      TB.Print(slot.label .. " now casts " .. n .. (InCombatLockdown() and " (after combat)" or ""))
    end
    HL.Refresh(); PanelRefresh()
  elseif word == "status" then
    local sp = HL.Spells()
    if not sp then TB.Print("no heal bar for this character (no heal spell known)") return end
    local eff = HL.Effective(sp)
    local bits = {}
    for _, s in ipairs(SLOTS) do
      local v = eff[s.key]
      if v then bits[#bits + 1] = s.label:lower() .. ": " .. v
      elseif v == false then bits[#bits + 1] = s.label:lower() .. ": nothing" end
    end
    TB.Print("heal: " .. sp.heal .. ", " .. table.concat(bits, ", "))
    for i, row in pairs(HL.Scan()) do
      TB.Print(row.name .. ": " .. (row.pct and (row.pct .. "%") or "?") .. (row.hurt and " (hurt)" or ""))
    end
  else
    TB.Print("usage: /boys heals [below <n>|lock|reset|clicks|set <click> <spell>|status]")
  end
end

TB.OnLogin(function()
  Build()
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "GROUP_ROSTER_CHANGED", "SPELLS_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_DEAD", "PLAYER_ALIVE",
                       "PLAYER_UNGHOST", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD",
                       "PLAYER_MOUNT_DISPLAY_CHANGED" }) do
    pcall(f.RegisterEvent, f, e)
  end
  f:SetScript("OnEvent", function() HL.Refresh() end)
  TB.Listen("SPEC_CHANGED", function() HL.Refresh() end)
  HL.Refresh()
end)
