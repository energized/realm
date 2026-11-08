-- TheBoys: gear upgrade engine. Scores bag items against what you wear, per spec.
local ADDON, ns = ...
local TB = ns.TB
local Gear = {}
TB.Gear = Gear

Gear.upgrades = {}
Gear.queue = {}
local announced = {}
local firstScan = true
local pending = false
local lastCount = 0

-- equipLoc -> candidate inventory slots (some depend on what the class can do)
local FIXED = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
  INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
  INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
  INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
  INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16 },
}
local function SlotsFor(loc, g)
  local s = FIXED[loc]
  if s then return s end
  if loc == "INVTYPE_WEAPON" then return g.dualWield and { 16, 17 } or { 16 } end
  if loc == "INVTYPE_WEAPONOFFHAND" then return g.dualWield and { 17 } or nil end
  if loc == "INVTYPE_SHIELD" then return g.shield and { 17 } or nil end
  if loc == "INVTYPE_HOLDABLE" then return g.holdable and { 17 } or nil end
  if loc == "INVTYPE_RANGEDRIGHT" then return { 18 } end                    -- wands, crossbows
  if loc == "INVTYPE_RANGED" then return g.ranged and { 18 } or nil end     -- bows, guns
  if loc == "INVTYPE_THROWN" then return g.thrown and { 18 } or nil end
  if loc == "INVTYPE_RELIC" then return g.relicSubclass and { 18 } or nil end
end
local SLOT_NAMES = {
  [1] = "Head", [2] = "Neck", [3] = "Shoulders", [5] = "Chest", [6] = "Waist", [7] = "Legs",
  [8] = "Feet", [9] = "Wrists", [10] = "Hands", [11] = "Ring 1", [12] = "Ring 2",
  [13] = "Trinket 1", [14] = "Trinket 2", [15] = "Back", [16] = "Main Hand",
  [17] = "Off Hand", [18] = "Wand",
}
Gear.SLOT_NAMES = SLOT_NAMES
Gear.SLOT_ORDER = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }

-- ------------------------------------------------------------ api wrappers
local function InstantInfo(link)
  local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not f then return end
  local ok, id, _, _, loc, icon, cid, scid = pcall(f, link)
  if ok and id then return id, loc, icon, cid, scid end
end

local function FullInfo(link)
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not f then return end
  local ok, name, _, quality, ilvl, minLevel, _, _, _, _, icon, _, _, _, bindType = pcall(f, link)
  if ok and name then return name, quality, ilvl, minLevel, icon, bindType end
end

local function ItemLevel(link)
  local f = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
  if f then
    local ok, ilvl = pcall(f, link)
    if ok and type(ilvl) == "number" and ilvl > 0 then return ilvl end
  end
  local _, _, ilvl = FullInfo(link)
  return ilvl or 0
end

local function RawStats(link)
  local f = (C_Item and C_Item.GetItemStats) or GetItemStats
  if not f then return nil end
  local ok, t = pcall(f, link)
  if ok and type(t) == "table" then return t end
end

-- Classic items put a lot of their value in "Equip:" text. Read it for the stats the
-- item table does not already give us. Each rule: pattern, key, stat keys that mean "already counted".
local COUNTED_SP = { "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE" }
local TIP_RULES = {
  { "damage and healing done by magical spells and effects by up to (%d+)", "ITEM_MOD_SPELL_POWER_SHORT", COUNTED_SP },
  { "Increases healing done by spells and effects by up to (%d+)", "ITEM_MOD_SPELL_HEALING_DONE", { "ITEM_MOD_SPELL_HEALING_DONE" } },
  { "Increases damage done by (%a+) spells and effects by up to (%d+)", "SCHOOL", {} },
  { "chance to get a critical strike with spells by (%d+)", "TIP_SPELL_CRIT", { "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_CRIT_SPELL_RATING_SHORT" } },
  { "chance to hit with spells by (%d+)", "TIP_SPELL_HIT", { "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_HIT_SPELL_RATING_SHORT" } },
  { "Improves your chance to get a critical strike by (%d+)", "TIP_CRIT", { "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_CRIT_MELEE_RATING_SHORT" } },
  { "Improves your chance to hit by (%d+)", "TIP_HIT", { "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_HIT_MELEE_RATING_SHORT" } },
  { "Restores (%d+) mana per 5 sec", "ITEM_MOD_MANA_REGENERATION_SHORT", { "ITEM_MOD_MANA_REGENERATION_SHORT" } },
  { "Increases attack power by (%d+)", "ITEM_MOD_ATTACK_POWER_SHORT", { "ITEM_MOD_ATTACK_POWER_SHORT" } },
  { "Increases ranged attack power by (%d+)", "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", { "ITEM_MOD_RANGED_ATTACK_POWER_SHORT" } },
  { "Increases your effective defense by (%d+)", "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", { "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT" } },
  { "chance to dodge an attack by (%d+)", "TIP_DODGE", { "ITEM_MOD_DODGE_RATING_SHORT" } },
  { "chance to parry an attack by (%d+)", "TIP_PARRY", { "ITEM_MOD_PARRY_RATING_SHORT" } },
}
local tipFrame
local function TooltipLines(link)
  if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
    local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
    if ok and type(data) == "table" and data.lines then
      local out = {}
      for _, ln in ipairs(data.lines) do
        if ln.leftText then out[#out + 1] = ln.leftText end
      end
      return out
    end
  end
  if not tipFrame then
    tipFrame = CreateFrame("GameTooltip", "TheBoysScanTip", nil, "GameTooltipTemplate")
    tipFrame:SetOwner(UIParent, "ANCHOR_NONE")
  end
  tipFrame:ClearLines()
  tipFrame:SetHyperlink(link)
  local out = {}
  for i = 1, tipFrame:NumLines() or 0 do
    local fs = _G["TheBoysScanTipTextLeft" .. i]
    if fs and fs.GetText and fs:GetText() then out[#out + 1] = fs:GetText() end
  end
  return out
end

local tipCache = {}
local function TooltipStats(link, stats)
  local c = tipCache[link]
  if c == nil then
    c = {}
    local ok, lines = pcall(TooltipLines, link)
    if ok and lines then
      for _, text in ipairs(lines) do
        for _, rule in ipairs(TIP_RULES) do
          local a, b = text:match(rule[1])
          if a then
            local key, val = rule[2], tonumber(a)
            if key == "SCHOOL" then key = "TIP_SCHOOL_" .. a:upper(); val = tonumber(b) end
            if val then
              local counted = false
              for _, k in ipairs(rule[3]) do if stats[k] then counted = true end end
              if not counted then c[key] = (c[key] or 0) + val end
            end
            break
          end
        end
      end
    end
    tipCache[link] = c
  end
  return c
end

-- ------------------------------------------------------------ scoring
-- returns score, hasData. Every item gets a little credit for armor and item level, so plain white
-- gear from the first levels still compares sensibly against what you wear.
local ARMOR_KEY = "RESISTANCE0_NAME"
function Gear.Score(link, spec)
  local stats = RawStats(link)
  if not stats then return 0, false end
  local w = spec.weights
  local total, hasData = 0, false
  for k, v in pairs(stats) do
    local wt = w[k]
    if k == ARMOR_KEY and wt == nil then wt = .05 end
    if wt and type(v) == "number" then
      total = total + v * wt
      if wt > 0 and k ~= ARMOR_KEY then hasData = true end
    end
  end
  for k, v in pairs(TooltipStats(link, stats)) do
    local wt = w[k]
    if wt then total = total + v * wt; if wt > 0 then hasData = true end end
  end
  total = total + ItemLevel(link) * .3
  return total, hasData
end

-- ------------------------------------------------------------ eligibility
local function Eligible(link, class, slack)
  local id, loc, _, cid, scid = InstantInfo(link)
  if not id or not loc or loc == "" then return nil end
  local g = class.gear
  local slots = SlotsFor(loc, g)
  if not slots then return nil end
  local level = (UnitLevel and UnitLevel("player")) or 1
  if cid == 4 then
    if loc == "INVTYPE_RELIC" then
      if g.relicSubclass ~= scid then return nil end
    elseif scid == 0 or scid == 6 then
      if not g.armorSubclasses[scid] then return nil end
    elseif loc ~= "INVTYPE_CLOAK" then
      -- any armor type up to the heaviest this class can wear at this level (cloth < leather < mail < plate)
      local top = 1
      for t = 1, 4 do if g.armorSubclasses[t] then top = math.max(top, t) end end
      if g.lowArmor and level < g.lowArmor[2] then top = math.min(top, g.lowArmor[1]) end
      if not scid or scid < 1 or scid > top then return nil end
    end
  elseif cid == 2 then
    if not g.weaponSubclasses[scid] then return nil end
  else
    return nil
  end
  local _, quality, _, minLevel = FullInfo(link)
  if quality == 0 then return nil end             -- grey items are junk, Realm sells them
  if minLevel and minLevel > level + (slack or 0) then return nil end
  return loc, slots, (loc == "INVTYPE_2HWEAPON")
end

-- ------------------------------------------------------------ bag walk
local function BagSlots(bag)
  local f = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  return f and f(bag) or 0
end
local function BagLink(bag, slot)
  if C_Container and C_Container.GetContainerItemLink then return C_Container.GetContainerItemLink(bag, slot) end
  if GetContainerItemLink then return GetContainerItemLink(bag, slot) end
end
local function IsBound(bag, slot)
  if C_Item and C_Item.IsBound and ItemLocation and ItemLocation.CreateFromBagAndSlot then
    local ok, r = pcall(function() return C_Item.IsBound(ItemLocation:CreateFromBagAndSlot(bag, slot)) end)
    if ok then return r end
  end
  return true -- unknown: assume bound (no BoE warning)
end

local function Bags()
  local out = {}
  local last = (NUM_BAG_SLOTS or 4) + 1
  for bag = 0, last do
    for slot = 1, BagSlots(bag) do
      local link = BagLink(bag, slot)
      if link then out[#out + 1] = { link = link, bag = bag, slot = slot } end
    end
  end
  return out
end

local function Equipped(slot)
  local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
  return link
end

-- ------------------------------------------------------------ main scan
function Gear.Scan(quiet)
  local class = TB.Class()
  local spec = TB.Spec()
  if not class or not spec then Gear.upgrades = {}; return end

  -- what you wear right now
  local worn, wornScore = {}, {}
  for slot = 1, 19 do
    local link = Equipped(slot)
    if link then
      worn[slot] = link
      wornScore[slot] = Gear.Score(link, spec)
    else
      wornScore[slot] = 0
    end
  end
  Gear.worn, Gear.wornScore = worn, wornScore
  local twoHand = false
  if worn[16] then
    local _, loc = InstantInfo(worn[16])
    twoHand = (loc == "INVTYPE_2HWEAPON")
  end

  local cands = {}
  local bestOffhand = wornScore[17] or 0
  for _, it in ipairs(Bags()) do
    local loc, slots, is2h = Eligible(it.link, class)
    if loc then
      local score, has = Gear.Score(it.link, spec)
      local name, quality, ilvl, _, icon, bindType = FullInfo(it.link)
      if not name then
        pending = true       -- data not cached yet; GET_ITEM_INFO_RECEIVED will rescan
      else
        it.loc, it.slots, it.is2h, it.score, it.has = loc, slots, is2h, score, has
        it.ilvl, it.icon, it.quality = ilvl, icon, quality
        it.boe = (bindType == 2) and not IsBound(it.bag, it.slot)
        if (loc == "INVTYPE_HOLDABLE" or loc == "INVTYPE_SHIELD" or loc == "INVTYPE_WEAPONOFFHAND") and score > bestOffhand then bestOffhand = score end
        cands[#cands + 1] = it
      end
    end
  end

  local ups = {}
  for _, it in ipairs(cands) do
    -- choose the slot where this item replaces the weakest thing
    local target, base = it.slots[1], math.huge
    for _, s in ipairs(it.slots) do
      local v = wornScore[s] or 0
      if v < base then target, base = s, v end
    end
    local effective, combo = it.score, false
    if it.is2h and (worn[17] or wornScore[17] > 0) then
      base = (wornScore[16] or 0) + (wornScore[17] or 0); combo = true
    elseif twoHand and not it.is2h and it.slots[1] == 16 then
      target, base = 16, wornScore[16] or 0
      effective = it.score + bestOffhand; combo = true
    elseif twoHand and not it.is2h and (target == 17) then
      effective = -1 -- an off-hand cannot go with a two-hander
    end
    if worn[target] ~= it.link and effective > 0 then
      local pct
      if base <= 0 then pct = 100 else pct = (effective - base) / base * 100 end
      local ignoredKey = it.link
      if pct >= (TB.DB.minUpgrade or 3) and not TB.DB.ignored[ignoredKey] then
        ups[#ups + 1] = {
          link = it.link, slot = target, slotName = SLOT_NAMES[target] or "Slot",
          pct = pct, score = effective, curLink = worn[target], curScore = base,
          boe = it.boe, combo = combo, icon = it.icon, ilvl = it.ilvl, bag = it.bag, bagSlot = it.slot,
          empty = (base <= 0),
        }
      end
    end
  end
  table.sort(ups, function(a, b) return a.pct > b.pct end)

  -- keep the best per slot group (two for rings/trinkets)
  local kept, seen = {}, {}
  for _, u in ipairs(ups) do
    local group = (u.slot == 11 or u.slot == 12) and "ring" or ((u.slot == 13 or u.slot == 14) and "trinket" or u.slot)
    local limit = (group == "ring" or group == "trinket") and 2 or 1
    seen[group] = (seen[group] or 0) + 1
    if seen[group] <= limit then kept[#kept + 1] = u end
  end
  Gear.upgrades = kept

  -- drop queued popups that are no longer upgrades
  local still = {}
  for _, u in ipairs(kept) do still[u.link] = u end
  local q = {}
  for _, u in ipairs(Gear.queue) do if still[u.link] then q[#q + 1] = still[u.link] end end
  Gear.queue = q
  if Gear.popupCurrent and not still[Gear.popupCurrent.link] then Gear.RefreshPopup(true) end

  -- queue anything new for the popup
  firstScan = false
  if TB.DB.suggest and not quiet then
    for _, u in ipairs(kept) do
      if not announced[u.link] then
        announced[u.link] = true
        Gear.Enqueue(u)
      end
    end
  end
  lastCount = #kept
  TB.Fire("GEAR_UPDATED")
end

-- how much of an upgrade an arbitrary item link would be, in percent (nil if you cannot use it). Used for quest reward picks.
function Gear.EvaluateLink(link)
  local class, spec = TB.Class(), TB.Spec()
  if not class or not spec then return nil end
  local loc, slots, is2h = Eligible(link, class, 3)
  if not loc then return nil end
  local score = Gear.Score(link, spec)
  local base, wornMain, wornOff = math.huge, 0, 0
  for _, s in ipairs(slots) do
    local w = Equipped(s)
    local v = w and Gear.Score(w, spec) or 0
    if v < base then base = v end
  end
  if is2h then
    local m, o = Equipped(16), Equipped(17)
    base = (m and Gear.Score(m, spec) or 0) + (o and Gear.Score(o, spec) or 0)
  end
  if base == math.huge then base = 0 end
  if base <= 0 then return 100 end
  return (score - base) / base * 100
end

-- ------------------------------------------------------------ equip
function Gear.Equip(u)
  if InCombatLockdown and InCombatLockdown() then
    TB.Print("You are in combat. Equip it after the fight.")
    return false
  end
  local f = (C_Item and C_Item.EquipItemByName) or EquipItemByName
  if not f then TB.Print("This client has no equip function."); return false end
  local ok, err = pcall(f, u.link, u.slot)
  if not ok then TB.Print("Could not equip: " .. tostring(err)); return false end
  if u.boe then TB.Print("This item binds when equipped. Confirm the game prompt if it appears.") end
  return true
end

function Gear.Ignore(u)
  TB.DB.ignored[u.link] = true
  Gear.Scan(true)
end

-- ------------------------------------------------------------ comparison popup
local popup
local MAXROWS, ROWH = 9, 15

local PSEUDO = {
  TIP_SPELL_CRIT = "Spell Crit %", TIP_SPELL_HIT = "Spell Hit %", TIP_CRIT = "Crit %", TIP_HIT = "Hit %",
  TIP_DODGE = "Dodge %", TIP_PARRY = "Parry %",
}
local function StatLabel(k)
  if PSEUDO[k] then return PSEUDO[k] end
  local school = k:match("^TIP_SCHOOL_(%a+)")
  if school then return school:sub(1, 1):upper() .. school:sub(2):lower() .. " Damage" end
  if _G[k] and type(_G[k]) == "string" then return _G[k] end
  local t = k:gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""):gsub("_", " "):lower()
  return t:sub(1, 1):upper() .. t:sub(2)
end

local function AllStats(link)
  local raw, out = RawStats(link) or {}, {}
  for k, v in pairs(raw) do if type(v) == "number" then out[k] = v end end
  for k, v in pairs(TooltipStats(link, raw)) do out[k] = (out[k] or 0) + v end
  return out
end

-- list of { label, cur, new, weighted } for every stat that differs, biggest effect first
function Gear.Compare(newLink, curLink, spec)
  local a, b = AllStats(newLink), curLink and AllStats(curLink) or {}
  local w = spec and spec.weights or {}
  local rows = {}
  local keys = {}
  for k in pairs(a) do keys[k] = true end
  for k in pairs(b) do keys[k] = true end
  for k in pairs(keys) do
    local n, c = a[k] or 0, b[k] or 0
    if n ~= c then
      local wt = w[k] or (k == ARMOR_KEY and .05) or 0
      rows[#rows + 1] = { label = StatLabel(k), cur = c, new = n, weighted = wt ~= 0, mag = math.abs((n - c) * wt) }
    end
  end
  table.sort(rows, function(x, y)
    if x.weighted ~= y.weighted then return x.weighted end
    if x.mag ~= y.mag then return x.mag > y.mag end
    return x.label < y.label
  end)
  return rows
end

local function InCombat() return InCombatLockdown and InCombatLockdown() end

-- the bind / vendor / auction lines under one item column (blank when the item is not cached yet)
local function Extras(x, link, bound)
  local II = ns.ItemInfo
  local b, v, a
  if II and link then b, v, a = II.Brief(link, bound) end
  x.bind:SetText(b or ""); x.vendor:SetText(v or ""); x.ah:SetText(a or "")
end

local function Fill(f, u)
  local spec = TB.Spec()
  local pct = u.empty and "empty slot" or ("+" .. math.floor(u.pct + .5) .. "%")
  f.title:SetText("|cff4dff9aUPGRADE|r  " .. u.slotName)
  f.pct:SetText("|cffffd24a" .. pct .. "|r")
  f.newIcon:SetTexture(u.icon or 134400)
  f.newName:SetText(u.link)
  f.newInfo:SetText("Item level " .. (u.ilvl or "?"))
  Extras(f.newX, u.link, not u.boe)
  if u.curLink then
    local _, _, _, _, cicon = FullInfo(u.curLink)
    f.curIcon:SetTexture(cicon or 134400)
    f.curName:SetText(u.curLink)
    f.curInfo:SetText("Item level " .. ItemLevel(u.curLink))
  else
    f.curIcon:SetTexture(134400)
    f.curName:SetText("|cff888888Nothing equipped|r")
    f.curInfo:SetText("")
  end
  Extras(f.curX, u.curLink, true)
  local rows = Gear.Compare(u.link, u.curLink, spec)
  local n = math.min(#rows, MAXROWS)
  for i = 1, MAXROWS do
    local r, d = f.rows[i], rows[i]
    if d and i <= n then
      local diff = d.new - d.cur
      local col = diff > 0 and "|cff33ff66" or "|cffff5050"
      local fmt = function(v) return (v == math.floor(v)) and tostring(v) or string.format("%.1f", v) end
      r.label:SetText((d.weighted and "|cffffffff" or "|cff888888") .. d.label .. "|r")
      r.cur:SetText(d.cur ~= 0 and fmt(d.cur) or "|cff666666-|r")
      r.new:SetText((d.new ~= 0 and fmt(d.new) or "-") .. "  " .. col .. "(" .. (diff > 0 and "+" or "") .. fmt(diff) .. ")|r")
      r.label:Show(); r.cur:Show(); r.new:Show()
    else
      r.label:Hide(); r.cur:Hide(); r.new:Hide()
    end
  end
  f.noStats:SetShown(n == 0)
  local note = u.combo and "weapon swap: this changes your main hand and off hand" or ""
  f.note:SetText(note)
  local h = 136 + math.max(n, 1) * ROWH + (note ~= "" and 14 or 0) + 44
  f:SetHeight(h)
end

local function ShowNext()
  if not popup then return end
  local u
  repeat
    u = table.remove(Gear.queue, 1)
    -- skip anything that has left the bags in the meantime
    if u and u.bag and u.bagSlot and BagLink(u.bag, u.bagSlot) ~= u.link then u = false end
  until u ~= false
  Gear.popupCurrent = u
  if not u then popup:Hide() return end
  Fill(popup, u)
  local more = #Gear.queue
  popup.more:SetText(more > 0 and ("+" .. more .. " more") or "")
  popup:Show()
end

function Gear.RefreshPopup(force)
  if not popup then return end
  if InCombat() then return end
  if force or not Gear.popupCurrent then ShowNext() end
end

local function BuildPopup()
  local f = TB.NewFrame("Frame", "TheBoysUpgradePopup", UIParent)
  f:SetSize(430, 220)
  f:SetPoint("TOP", UIParent, "TOP", 0, -150)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  TB.Skin(f, .045, .04, .07, .97, .2, .6, .4)

  f.top = f:CreateTexture(nil, "ARTWORK")
  f.top:SetPoint("TOPLEFT", 1, -1); f.top:SetPoint("TOPRIGHT", -1, -1); f.top:SetHeight(3)
  f.top:SetColorTexture(.3, 1, .6, 1)

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOPLEFT", 14, -12)
  f.pct = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.pct:SetPoint("TOPRIGHT", -14, -10)

  local function Column(x, head)
    local h = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    h:SetPoint("TOPLEFT", x, -34); h:SetText(head)
    local bg = f:CreateTexture(nil, "ARTWORK")
    bg:SetSize(36, 36); bg:SetPoint("TOPLEFT", x, -48); bg:SetColorTexture(0, 0, 0, 1)
    local ic = f:CreateTexture(nil, "OVERLAY")
    ic:SetSize(33, 33); ic:SetPoint("CENTER", bg, "CENTER"); ic:SetTexCoord(.07, .93, .07, .93)
    local name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("TOPLEFT", bg, "TOPRIGHT", 8, -2); name:SetWidth(168); name:SetJustifyH("LEFT")
    if name.SetWordWrap then name:SetWordWrap(false) end
    local info = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    info:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3); info:SetWidth(168); info:SetJustifyH("LEFT")
    if info.SetWordWrap then info:SetWordWrap(false) end
    local hit = CreateFrame("Frame", nil, f)
    hit:SetAllPoints(bg); hit:EnableMouse(true)
    -- bind (BoP / BoE), vendor price, auction price: three short lines under the icon
    local ex = {}
    for i, key in ipairs({ "bind", "vendor", "ah" }) do
      ex[key] = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      ex[key]:SetPoint("TOPLEFT", x, -88 - (i - 1) * 13); ex[key]:SetWidth(200); ex[key]:SetJustifyH("LEFT")
      if ex[key].SetWordWrap then ex[key]:SetWordWrap(false) end
    end
    return ic, name, info, hit, ex
  end
  f.curIcon, f.curName, f.curInfo, f.curHit, f.curX = Column(14, "EQUIPPED")
  f.newIcon, f.newName, f.newInfo, f.newHit, f.newX = Column(222, "NEW")
  local function Tip(hit, which)
    hit:SetScript("OnEnter", function(self)
      local u = Gear.popupCurrent
      local link = u and (which == "new" and u.link or u.curLink)
      if link and GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(link); GameTooltip:Show() end
    end)
    hit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  end
  Tip(f.curHit, "cur"); Tip(f.newHit, "new")

  local line = f:CreateTexture(nil, "ARTWORK")
  line:SetPoint("TOPLEFT", 12, -132); line:SetPoint("TOPRIGHT", -12, -132); line:SetHeight(1); line:SetColorTexture(.173, .231, .302, 1)

  f.rows = {}
  for i = 1, MAXROWS do
    local y = -138 - (i - 1) * ROWH
    local r = {}
    r.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.label:SetPoint("TOPLEFT", 16, y); r.label:SetWidth(150); r.label:SetJustifyH("LEFT")
    r.cur = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.cur:SetPoint("TOPLEFT", 168, y); r.cur:SetWidth(42); r.cur:SetJustifyH("RIGHT")
    r.new = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.new:SetPoint("TOPLEFT", 224, y); r.new:SetWidth(190); r.new:SetJustifyH("LEFT")
    f.rows[i] = r
  end
  f.noStats = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.noStats:SetPoint("TOPLEFT", 16, -140); f.noStats:SetText("No stat differences to show. Hover the icons for full tooltips.")
  f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.note:SetPoint("BOTTOMLEFT", 16, 42)
  f.more = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.more:SetPoint("BOTTOMRIGHT", -14, 14)

  local equip = TB.FlatButton(f, "Equip", 96, 24, function()
    local u = Gear.popupCurrent
    if u and Gear.Equip(u) then ShowNext() end
  end)
  equip:SetPoint("BOTTOMLEFT", 14, 10); equip:SetTone(.10, .42, .27)
  local ignore = TB.FlatButton(f, "Ignore", 96, 24, function()
    local u = Gear.popupCurrent
    if u then TB.DB.ignored[u.link] = true end
    ShowNext()
    Gear.Scan(true)
  end)
  ignore:SetPoint("LEFT", equip, "RIGHT", 8, 0); ignore:SetTone(.38, .12, .14)
  f:Hide()
  return f
end

function Gear.Enqueue(u)
  if not popup then popup = BuildPopup() end
  if Gear.popupCurrent and Gear.popupCurrent.link == u.link then return end
  for _, q in ipairs(Gear.queue) do if q.link == u.link then return end end
  table.insert(Gear.queue, u)
  if not Gear.popupCurrent and not InCombat() then ShowNext()
  elseif popup:IsShown() then popup.more:SetText("+" .. #Gear.queue .. " more") end
end

-- ------------------------------------------------------------ triggers
local timerPending = false
local function Soon()
  if timerPending then return end
  timerPending = true
  C_Timer.After(0.6, function()
    timerPending = false
    local ok, err = pcall(Gear.Scan)
    if not ok then TB.Print("gear scan error: " .. tostring(err)) end
  end)
end
Gear.Soon = Soon

TB.OnLogin(function()
  popup = popup or BuildPopup()
  local f = CreateFrame("Frame")
  f:RegisterEvent("BAG_UPDATE_DELAYED")
  f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
  f:RegisterEvent("PLAYER_LEVEL_UP")
  f:RegisterEvent("PLAYER_REGEN_ENABLED")
  f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then Gear.RefreshPopup() end
    if event == "GET_ITEM_INFO_RECEIVED" and not pending then return end
    if event == "GET_ITEM_INFO_RECEIVED" then pending = false end
    Soon()
  end)
  TB.Listen("SPEC_CHANGED", function() firstScan = true; announced = {}; Soon() end)
  C_Timer.After(3, Soon)
end)
