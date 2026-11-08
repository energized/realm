-- TheBoys: leveling buff alerts. A small bar shows the buffs your class should have up and does not.
-- Left click casts it on you. Right click, or Alt + left click, casts it on a party member who is missing it.
-- Only spells you actually know are tracked, so a new character sees nothing until it learns them.
local ADDON, ns = ...
local TB = ns.TB
local BF = {}
TB.Buffs = BF

local SIZE, GAP, GRIP = 40, 6, 10

-- id          short key
-- spells      what to cast, first one you know wins (prefer[SPEC] jumps the queue)
-- auras       names that count as "already buffed" (defaults to spells)
-- group       true when it can be cast on a party member too
-- greater     group version of the spell; offered when two or more people are missing the buff
-- area        true for self casts that reach nearby party members (shouts, auras): the party is checked, the click casts on you
-- weapon      true for weapon enchants (checked on the main hand)
-- only        spec keys that need it (leave out for every spec)
local DATA = {
  WARRIOR = {
    { id = "shout", spells = { "Battle Shout" }, area = true, note = "Attack power for you and your party." },
  },
  PALADIN = {
    { id = "kings", spells = { "Blessing of Kings" }, auras = { "Blessing of Kings", "Greater Blessing of Kings" },
      group = true, note = "Raises all stats." },
    { id = "might", spells = { "Blessing of Might", "Blessing of Wisdom" }, prefer = { HOLY = "Blessing of Wisdom" },
      auras = { "Blessing of Might", "Greater Blessing of Might", "Blessing of Wisdom", "Greater Blessing of Wisdom" },
      group = true, note = "Attack power, or mana regeneration for healers." },
    { id = "aura", spells = { "Devotion Aura", "Retribution Aura", "Concentration Aura" },
      prefer = { RETRIBUTION = "Retribution Aura", HOLY = "Concentration Aura" },
      auras = { "Devotion Aura", "Retribution Aura", "Concentration Aura", "Sanctity Aura", "Crusader Aura",
                "Fire Resistance Aura", "Frost Resistance Aura", "Shadow Resistance Aura" },
      area = true, note = "Keep one aura on. It reaches your party." },
    { id = "fury", spells = { "Righteous Fury" }, only = { PROTECTION = true }, note = "Threat while tanking." },
  },
  HUNTER = {
    { id = "aspect", spells = { "Aspect of the Hawk", "Aspect of the Monkey" },
      auras = { "Aspect of the Hawk", "Aspect of the Monkey", "Aspect of the Cheetah", "Aspect of the Viper",
                "Aspect of the Beast", "Aspect of the Wild", "Aspect of the Pack", "Aspect of the Dragonhawk" },
      note = "Keep an aspect on. Travel aspects count, so you are not nagged while running." },
    { id = "trueshot", spells = { "Trueshot Aura" }, area = true, note = "Attack power for your party." },
  },
  ROGUE = {},
  PRIEST = {
    { id = "fort", spells = { "Power Word: Fortitude" }, auras = { "Power Word: Fortitude", "Prayer of Fortitude" },
      group = true, greater = { "Prayer of Fortitude" }, note = "Stamina." },
    { id = "spirit", spells = { "Divine Spirit" }, auras = { "Divine Spirit", "Prayer of Spirit" },
      group = true, greater = { "Prayer of Spirit" }, note = "Spirit." },
    { id = "fire", spells = { "Inner Fire" }, note = "Armor and spell power." },
    { id = "form", spells = { "Shadowform" }, note = "Shadow damage form." },
  },
  SHAMAN = {
    { id = "shield", spells = { "Lightning Shield", "Water Shield" }, prefer = { RESTORATION = "Water Shield" },
      note = "Your shield." },
    { id = "weapon", spells = { "Windfury Weapon", "Flametongue Weapon", "Frostbrand Weapon", "Rockbiter Weapon" },
      prefer = { ELEMENTAL = "Flametongue Weapon", RESTORATION = "Flametongue Weapon" },
      weapon = true, note = "Main hand weapon enchant." },
  },
  MAGE = {
    { id = "int", spells = { "Arcane Intellect" }, auras = { "Arcane Intellect", "Arcane Brilliance" },
      group = true, greater = { "Arcane Brilliance" }, note = "Intellect." },
    { id = "armor", spells = { "Mage Armor", "Molten Armor", "Ice Armor", "Frost Armor" },
      prefer = { FIRE = "Molten Armor", FROST = "Ice Armor" },
      auras = { "Mage Armor", "Molten Armor", "Ice Armor", "Frost Armor" }, note = "Keep an armor on." },
  },
  WARLOCK = {
    { id = "armor", spells = { "Fel Armor", "Demon Armor", "Demon Skin" },
      auras = { "Fel Armor", "Demon Armor", "Demon Skin" }, note = "Keep an armor on." },
  },
  DRUID = {
    { id = "motw", spells = { "Mark of the Wild" }, auras = { "Mark of the Wild", "Gift of the Wild" },
      group = true, greater = { "Gift of the Wild" }, note = "Armor and stats." },
    { id = "thorns", spells = { "Thorns" }, group = true, note = "Damage to attackers." },
    { id = "omen", spells = { "Omen of Clarity" }, note = "Free casts now and then." },
  },
}
BF.DATA = DATA

local bar, grip, buttons = nil, nil, {}
local alerted, pending, dirty, quietUntil = {}, false, true, 0

local function Now() return (GetTime and GetTime()) or os.clock() end

-- ---------------------------------------------------------------- checks
-- true / false, or nil when this client gives no way to tell
local function HasAura(unit, names)
  local known = false
  if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
    known = true
    for _, n in ipairs(names) do
      local ok, d = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, n, "HELPFUL")
      if ok and d then return true end
    end
  elseif AuraUtil and AuraUtil.FindAuraByName then
    known = true
    for _, n in ipairs(names) do
      local ok, r = pcall(AuraUtil.FindAuraByName, n, unit, "HELPFUL")
      if ok and r then return true end
    end
  elseif UnitBuff then
    known = true
    for i = 1, 40 do
      local ok, name = pcall(UnitBuff, unit, i)
      if not ok or not name then break end
      for _, n in ipairs(names) do if name == n then return true end end
    end
  end
  if known then
    -- the name lookup can miss when this client words the buff differently from the spell (Thorns on a druid).
    -- Look through the buffs themselves and match the spell id or its icon as well.
    local ids, icons = {}, {}
    for _, n in ipairs(names) do
      local sn, icon, id = TB.Spell(n)
      if sn then
        if id then ids[id] = true end
        if icon then icons[icon] = true end
      end
    end
    if next(ids) or next(icons) then
      for i = 1, 40 do
        local d
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
          local ok, r = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
          if not ok or not r then break end
          d = r
        elseif UnitBuff then
          local ok, name, icon, _, _, _, _, _, _, _, id = pcall(UnitBuff, unit, i)
          if not ok or not name then break end
          d = { icon = icon, spellId = id }
        else
          break
        end
        local ok, hit = pcall(function()
          return (d.spellId and ids[d.spellId]) or (d.icon and icons[d.icon]) or false
        end)
        if ok and hit then return true end
      end
    end
    return false
  end
  return nil
end
BF.HasAura = HasAura

local function HasWeaponEnchant()
  if not GetWeaponEnchantInfo then return nil end
  if GetInventoryItemID and not GetInventoryItemID("player", 16) then return nil end
  local ok, has = pcall(GetWeaponEnchantInfo)
  if not ok then return nil end
  return has and true or false
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

local function Members()
  local list = {}
  if IsInRaid and IsInRaid() then return list end
  local n = (GetNumSubgroupMembers and GetNumSubgroupMembers()) or 0
  for i = 1, math.min(n, 4) do
    local u = "party" .. i
    if Eligible(u) then list[#list + 1] = u end
  end
  return list
end

-- no alerts while dead, mounted, on a taxi, in a vehicle, or in a druid form
local function Quiet()
  if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return true end
  if IsMounted and IsMounted() then return true end
  if UnitOnTaxi and UnitOnTaxi("player") then return true end
  if UnitInVehicle and UnitInVehicle("player") then return true end
  if TB.ClassToken() == "DRUID" and GetShapeshiftForm and (GetShapeshiftForm() or 0) > 0 then return true end
  return false
end

-- area casts (shouts, auras) only reach so far; skip friends clearly outside it when the client can tell
local function Near(unit)
  if not CheckInteractDistance then return true end
  local ok, near = pcall(CheckInteractDistance, unit, 4)
  if ok and near == false then return false end
  return true
end

local function PickSpell(e, specKey)
  local p = specKey and e.prefer and e.prefer[specKey]
  if p and TB.Known(p) then return p end
  for _, n in ipairs(e.spells) do
    if TB.Known(n) then return n end
  end
end

-- the list of buffs missing right now: { id, spell, entry, self = bool, members = { unit }, names = { name } }
function BF.Need()
  local out = {}
  local set = DATA[TB.ClassToken() or ""]
  if not set then return out end
  local _, specKey = TB.Spec()
  local roster
  for _, e in ipairs(set) do
    if not e.only or (specKey and e.only[specKey]) then
      local spell = PickSpell(e, specKey)
      if spell then
        local item = { id = e.id, spell = spell, entry = e, members = {}, names = {} }
        if e.weapon then
          if HasWeaponEnchant() == false then item.self = true end
        else
          local auras = e.auras or e.spells
          if HasAura("player", auras) == false then item.self = true end
          if e.group or e.area then
            roster = roster or Members()
            for _, u in ipairs(roster) do
              if (not e.area or Near(u)) and HasAura(u, auras) == false then
                item.members[#item.members + 1] = u
                item.names[#item.names + 1] = (UnitName and UnitName(u)) or u
              end
            end
          end
        end
        item.area = e.area and true or nil
        -- two or more people missing it and you know the group version: one click covers the party
        if e.greater and ((item.self and 1 or 0) + #item.members) >= 2 then
          for _, g in ipairs(e.greater) do
            if TB.Known(g) then item.single, item.spell, item.greater = item.spell, g, true; break end
          end
        end
        if item.self or #item.members > 0 then out[#out + 1] = item end
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------- buttons
local function Arm(b, item)
  local member = item.members[1]
  if item.area then
    -- the cast is on you and reaches the party, so every click does the same thing
    b:SetAttribute("type1", "spell"); b:SetAttribute("spell1", item.spell); b:SetAttribute("unit1", "player")
    b:SetAttribute("type2", "spell"); b:SetAttribute("spell2", item.spell); b:SetAttribute("unit2", "player")
    b:SetAttribute("alt-type1", nil); b:SetAttribute("alt-spell1", nil); b:SetAttribute("alt-unit1", nil)
    return
  end
  if item.greater then
    -- left click: the group spell on you covers everyone. right click or Alt click: the single spell on one person.
    local one = member or "player"
    b:SetAttribute("type1", "spell"); b:SetAttribute("spell1", item.spell); b:SetAttribute("unit1", "player")
    b:SetAttribute("type2", "spell"); b:SetAttribute("spell2", item.single); b:SetAttribute("unit2", one)
    b:SetAttribute("alt-type1", "spell"); b:SetAttribute("alt-spell1", item.single); b:SetAttribute("alt-unit1", one)
    return
  end
  b:SetAttribute("type1", "spell"); b:SetAttribute("spell1", item.spell)
  b:SetAttribute("unit1", item.self and "player" or member)
  if member then
    b:SetAttribute("type2", "spell"); b:SetAttribute("spell2", item.spell); b:SetAttribute("unit2", member)
    b:SetAttribute("alt-type1", "spell"); b:SetAttribute("alt-spell1", item.spell); b:SetAttribute("alt-unit1", member)
  else
    b:SetAttribute("type2", nil); b:SetAttribute("spell2", nil); b:SetAttribute("unit2", nil)
    b:SetAttribute("alt-type1", nil); b:SetAttribute("alt-spell1", nil); b:SetAttribute("alt-unit1", nil)
  end
end

local function Tip(self)
  local item = self.item
  if not GameTooltip or not item then return end
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:AddLine(item.spell, 1, 1, 1)
  GameTooltip:AddLine(item.entry.note or "", .8, .8, .8, true)
  if item.self then GameTooltip:AddLine("Missing on you", 1, .5, .4) end
  if #item.names > 0 then GameTooltip:AddLine("Missing on: " .. table.concat(item.names, ", "), .5, .8, 1, true) end
  if item.area then
    GameTooltip:AddLine("Click: cast it. It reaches your party.", .6, 1, .6)
  elseif item.greater then
    GameTooltip:AddLine("Click: " .. item.spell .. " for the whole party (uses a reagent)", .6, 1, .6)
    GameTooltip:AddLine("Right click or Alt click: " .. item.single .. " on " .. (item.names[1] or "you"), .6, 1, .6)
  elseif item.self then
    GameTooltip:AddLine("Click: cast on you", .6, 1, .6)
  elseif item.members[1] then
    GameTooltip:AddLine("Click: cast on " .. item.names[1], .6, 1, .6)
  end
  if item.members[1] and not item.area and not item.greater then
    GameTooltip:AddLine("Right click or Alt click: cast on " .. item.names[1], .6, 1, .6)
  end
  GameTooltip:Show()
end

local function MakeButton()
  local b = CreateFrame("Button", nil, bar, "SecureActionButtonTemplate")
  b:SetSize(SIZE, SIZE)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints(); b.icon:SetTexCoord(.07, .93, .07, .93)
  b.glow = b:CreateTexture(nil, "OVERLAY")
  b.glow:SetPoint("TOPLEFT", -3, 3); b.glow:SetPoint("BOTTOMRIGHT", 3, -3)
  b.glow:SetDrawLayer("BACKGROUND")
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.count:SetPoint("BOTTOMRIGHT", -2, 2)
  if not pcall(b.RegisterForClicks, b, "AnyUp", "AnyDown") then b:RegisterForClicks("AnyUp") end
  b:SetScript("OnEnter", Tip)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return b
end

local function Layout(list)
  for i = 1, math.max(#list, #buttons) do
    local item, b = list[i], buttons[i]
    if item then
      if not b then b = MakeButton(); buttons[i] = b end
      b.item = item
      b.icon:SetTexture(TB.Icon(item.spell))
      -- green: missing on you. blue: only a party member is missing it.
      if item.self then b.glow:SetColorTexture(.2, 1, .4, .55) else b.glow:SetColorTexture(.3, .6, 1, .55) end
      b.count:SetText(#item.members > 0 and tostring(#item.members) or "")
      Arm(b, item)
      b:ClearAllPoints()
      b:SetPoint("LEFT", bar, "LEFT", GRIP + 4 + (i - 1) * (SIZE + GAP), 0)
      b:Show()
    elseif b then
      b.item = nil
      b:Hide()
    end
  end
  bar:SetSize(GRIP + 4 + math.max(#list, 1) * (SIZE + GAP), SIZE)
end

local function Announce(list)
  local now = {}
  for _, item in ipairs(list) do
    now[item.id] = true
    if not alerted[item.id] and TB.DB.buffAlert ~= false and Now() >= quietUntil then
      local who = {}
      if item.self then who[1] = "you" end
      for _, n in ipairs(item.names) do who[#who + 1] = n end
      TB.Say("Buff needed: " .. item.spell .. " (" .. table.concat(who, ", ") .. ")")
    end
  end
  alerted = now
end

function BF.Refresh()
  if not bar then return end
  if InCombatLockdown() then
    pending = true
    bar:SetAlpha(.35)
    return
  end
  pending = false
  bar:SetAlpha(1)
  local list = {}
  if TB.DB.buffBar ~= false and not Quiet() then list = BF.Need() end
  BF.list = list
  Layout(list)
  Announce(list)
  if #list == 0 then bar:Hide() else bar:Show() end
end

local function Build()
  bar = TB.NewFrame("Frame", "TheBoysBuffBar", UIParent)
  bar:SetSize(GRIP + 4 + SIZE + GAP, SIZE)
  bar:SetMovable(true); bar:SetClampedToScreen(true)
  local pos = TB.DB.buffPos
  if pos then bar:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else bar:SetPoint("CENTER", UIParent, "CENTER", 0, -130) end

  grip = CreateFrame("Button", nil, bar)
  grip:SetSize(GRIP, SIZE)
  grip:SetPoint("LEFT", bar, "LEFT", 0, 0)
  grip.bg = grip:CreateTexture(nil, "BACKGROUND")
  grip.bg:SetAllPoints(); grip.bg:SetColorTexture(.77, .13, .106, .6)
  grip:RegisterForDrag("LeftButton")
  grip:SetScript("OnDragStart", function()
    if not TB.DB.buffLocked and not InCombatLockdown() then bar:StartMoving() end
  end)
  grip:SetScript("OnDragStop", function()
    bar:StopMovingOrSizing()
    local p, _, rp, x, y = bar:GetPoint()
    TB.DB.buffPos = { p, rp, x, y }
  end)
  grip:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Buff alerts", 1, 1, 1)
    GameTooltip:AddLine("Drag to move. /boys buffs lock to pin it.", .7, .7, .7, true)
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  local acc, t = 0, 0
  bar:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    t = t + dt
    if acc >= 0.5 then
      acc = 0
      if dirty or t >= 2 then dirty = false; t = 0; BF.Refresh() end
    end
    local a = .45 + .3 * math.sin((Now()) * 4)
    for _, b in ipairs(buttons) do if b:IsShown() then b.glow:SetAlpha(a) end end
  end)
  bar:Hide()
end

-- ---------------------------------------------------------------- commands
function BF.Command(rest)
  rest = rest or ""
  local DB = TB.DB
  if rest == "" then
    DB.buffBar = not (DB.buffBar ~= false)
    BF.Refresh()
    TB.Print("buff alerts " .. (DB.buffBar ~= false and "on" or "off"))
  elseif rest == "alert" then
    DB.buffAlert = not (DB.buffAlert ~= false)
    TB.Print("buff chat message " .. (DB.buffAlert ~= false and "on" or "off"))
  elseif rest == "lock" then
    DB.buffLocked = not DB.buffLocked
    TB.Print("buff bar " .. (DB.buffLocked and "locked" or "unlocked: drag the red strip"))
  elseif rest == "reset" then
    DB.buffPos = nil
    if bar then bar:ClearAllPoints(); bar:SetPoint("CENTER", UIParent, "CENTER", 0, -130) end
    TB.Print("buff bar moved back to the default spot")
  elseif rest == "status" then
    local list = BF.Need()
    if #list == 0 then TB.Print("nothing is missing right now")
    else
      for _, item in ipairs(list) do
        local who = {}
        if item.self then who[1] = "you" end
        for _, n in ipairs(item.names) do who[#who + 1] = n end
        TB.Print(item.spell .. ": " .. table.concat(who, ", "))
      end
    end
  else
    TB.Print("usage: /boys buffs [alert|lock|reset|status]")
  end
end

TB.OnLogin(function()
  Build()
  quietUntil = Now() + 4
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "UNIT_AURA", "GROUP_ROSTER_CHANGED", "SPELLS_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_DEAD",
                       "PLAYER_ALIVE", "PLAYER_UNGHOST", "UNIT_INVENTORY_CHANGED", "PLAYER_REGEN_ENABLED",
                       "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD", "PLAYER_MOUNT_DISPLAY_CHANGED",
                       "UPDATE_SHAPESHIFT_FORM" }) do
    pcall(f.RegisterEvent, f, e)
  end
  f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then quietUntil = Now() + 4 end
    if event == "PLAYER_REGEN_DISABLED" then BF.Refresh() return end
    if event == "PLAYER_REGEN_ENABLED" then dirty = true; BF.Refresh() return end
    dirty = true
  end)
  TB.Listen("SPEC_CHANGED", function() dirty = true end)
  BF.Refresh()
end)
