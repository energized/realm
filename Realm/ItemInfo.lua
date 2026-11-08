-- Realm item info: BoP / BoE, vendor price, auction price from the Exchange scan, and the disenchant value
-- for characters who know Disenchant. Used by the item tooltips and by the gear compare popup in The Boys.
--
-- Disenchant odds: Warcraft Wiki, "Disenchanting tables" (https://warcraft.wiki.gg/wiki/Disenchanting_tables), the
-- Classic ranges up to item level 65. The epic row for item level 61-88 is rough: the page text I read was cut off
-- before its quantity, so it counts one Nexus Crystal and is shown with "rough".
-- Material item IDs were typed from memory of the Classic game, not read from a database. Every ID is checked
-- against the name the game reports for it, and a material whose name does not match is left out of the value.
local ADDON, ns = ...
local II = {}
ns.ItemInfo = II

local DE_SPELL = 13262

local MAT = {
  [10940] = "Strange Dust", [11083] = "Soul Dust", [11137] = "Vision Dust", [11176] = "Dream Dust",
  [16204] = "Illusion Dust",
  [10938] = "Lesser Magic Essence", [10939] = "Greater Magic Essence", [10998] = "Lesser Astral Essence",
  [11082] = "Greater Astral Essence", [11134] = "Lesser Mystic Essence", [11135] = "Greater Mystic Essence",
  [11174] = "Lesser Nether Essence", [11175] = "Greater Nether Essence", [16202] = "Lesser Eternal Essence",
  [16203] = "Greater Eternal Essence",
  [10978] = "Small Glimmering Shard", [11084] = "Large Glimmering Shard", [11138] = "Small Glowing Shard",
  [11139] = "Large Glowing Shard", [11177] = "Small Radiant Shard", [11178] = "Large Radiant Shard",
  [14343] = "Small Brilliant Shard", [14344] = "Large Brilliant Shard", [20725] = "Nexus Crystal",
}
II.Materials = MAT

-- rows: { item level from, to, { material id, chance, quantity from, quantity to }, ... }
local ARMOR = {
  { 5, 15,  { 10940, .80, 1, 2 }, { 10938, .20, 1, 2 } },
  { 16, 20, { 10940, .75, 2, 3 }, { 10939, .20, 1, 2 }, { 10978, .05, 1, 1 } },
  { 21, 25, { 10940, .75, 4, 6 }, { 10998, .15, 1, 2 }, { 10978, .10, 1, 1 } },
  { 26, 30, { 11083, .75, 1, 2 }, { 11082, .20, 1, 2 }, { 11084, .05, 1, 1 } },
  { 31, 35, { 11083, .75, 2, 5 }, { 11134, .20, 1, 2 }, { 11138, .05, 1, 1 } },
  { 36, 40, { 11137, .75, 1, 2 }, { 11135, .20, 1, 2 }, { 11139, .05, 1, 1 } },
  { 41, 45, { 11137, .75, 2, 5 }, { 11174, .20, 1, 2 }, { 11177, .05, 1, 1 } },
  { 46, 50, { 11176, .75, 1, 2 }, { 11175, .20, 1, 2 }, { 11178, .05, 1, 1 } },
  { 51, 55, { 11176, .75, 2, 5 }, { 16202, .20, 1, 2 }, { 14343, .05, 1, 1 } },
  { 56, 60, { 16204, .75, 1, 2 }, { 16203, .20, 1, 2 }, { 14344, .05, 1, 1 } },
  { 61, 65, { 16204, .75, 2, 5 }, { 16203, .20, 2, 3 }, { 14344, .05, 1, 1 } },
}
local WEAPON = {
  { 6, 15,  { 10940, .20, 1, 2 }, { 10938, .80, 1, 2 } },
  { 16, 20, { 10940, .20, 2, 3 }, { 10939, .75, 1, 2 }, { 10978, .05, 1, 1 } },
  { 21, 25, { 10940, .15, 4, 6 }, { 10998, .75, 1, 2 }, { 10978, .10, 1, 1 } },
  { 26, 30, { 11083, .20, 1, 2 }, { 11082, .75, 1, 2 }, { 11084, .05, 1, 1 } },
  { 31, 35, { 11083, .20, 2, 5 }, { 11134, .75, 1, 2 }, { 11138, .05, 1, 1 } },
  { 36, 40, { 11137, .20, 1, 2 }, { 11135, .75, 1, 2 }, { 11139, .05, 1, 1 } },
  { 41, 45, { 11137, .20, 2, 5 }, { 11174, .75, 1, 2 }, { 11177, .05, 1, 1 } },
  { 46, 50, { 11176, .20, 1, 2 }, { 11175, .75, 1, 2 }, { 11178, .05, 1, 1 } },
  { 51, 55, { 11176, .22, 2, 5 }, { 16202, .75, 1, 2 }, { 14343, .03, 1, 1 } },
  { 56, 60, { 16204, .22, 1, 2 }, { 16203, .75, 1, 2 }, { 14344, .03, 1, 1 } },
  { 61, 65, { 16204, .22, 2, 5 }, { 16203, .75, 2, 3 }, { 14344, .03, 1, 1 } },
}
local RARE = {
  { 1, 25,  { 10978, 1, 1, 1 } },
  { 26, 30, { 11084, 1, 1, 1 } },
  { 31, 35, { 11138, 1, 1, 1 } },
  { 36, 40, { 11139, 1, 1, 1 } },
  { 41, 45, { 11177, 1, 1, 1 } },
  { 46, 50, { 11178, 1, 1, 1 } },
  { 51, 55, { 14343, 1, 1, 1 } },
  { 56, 65, { 14344, .995, 1, 1 }, { 20725, .005, 1, 1 } },
}
local EPIC = {
  { 40, 45, { 11177, 1, 2, 4 } },
  { 46, 50, { 11178, 1, 2, 4 } },
  { 51, 55, { 14343, 1, 2, 4 } },
  { 56, 60, { 20725, 1, 1, 1 } },
  { 61, 88, { 20725, 1, 1, 1 }, approx = true },
}

-- ---------------------------------------------------------------- game data helpers
local function Info(link)
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not (f and link) then return end
  local ok, name, _, quality, ilvl, _, _, _, _, equipLoc, _, sell, classID, _, bind = pcall(f, link)
  if ok and name then
    return { name = name, quality = quality, ilvl = ilvl, equipLoc = equipLoc, sell = sell, class = classID, bind = bind }
  end
end
II.Info = Info

local function ItemID(link)
  return link and tonumber(tostring(link):match("item:(%d+)"))
end

local function ILvl(link, base)
  local f = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
  if f then
    local ok, v = pcall(f, link)
    if ok and tonumber(v) and v > 0 then return v end
  end
  return base
end

function II.Enabled()
  local D = ns.DB
  return not (D and D.itemTips == false)
end

function II.Money(c)
  c = math.floor(c or 0)
  if GetCoinTextureString then return GetCoinTextureString(c) end
  local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "g" end
  if s > 0 or g > 0 then out[#out + 1] = s .. "s" end
  out[#out + 1] = k .. "c"
  return table.concat(out, " ")
end

local function Ago(t)
  local s = math.max(0, (time and time() or 0) - (t or 0))
  if s < 3600 then return math.max(1, math.floor(s / 60)) .. " min ago" end
  if s < 86400 then return math.floor(s / 3600) .. " h ago" end
  return math.floor(s / 86400) .. " d ago"
end

-- the Exchange scan price for an item: current price, median, number of scans, time of the last scan
function II.AH(id)
  local ex = ns.Exchange
  if not (id and ex and ex.Price) then return end
  return ex.Price(id)
end

-- ---------------------------------------------------------------- bind text
local RED, ORANGE, GRAY = "|cffff4040", "|cffff8040", "|cff9d9d9d"
-- bind = the game's bindType (0 none, 1 on pickup, 2 on equip, 3 on use, 4 quest); bound = the item is soulbound now
function II.BindText(bind, bound)
  if bind == 1 then
    return RED .. (bound and "BoP: soulbound" or "BoP: binds when picked up") .. "|r"
  elseif bind == 2 then
    return ORANGE .. (bound and "BoE: soulbound" or "BoE: binds when equipped") .. "|r"
  elseif bind == 3 then
    return GRAY .. "BoU: binds when used" .. "|r"
  elseif bind == 4 then
    return GRAY .. "Quest item" .. "|r"
  end
  return GRAY .. "No bind: tradable" .. "|r"
end

-- three short lines for the compare popup: bind, vendor, auction
function II.Brief(link, bound)
  local info = Info(link)
  if not info then return end
  local b = II.BindText(info.bind, bound)
  local v
  if info.sell and info.sell > 0 then v = "Vendor: " .. II.Money(info.sell) else v = GRAY .. "Vendor: no value|r" end
  local a
  if info.bind == 1 or info.bind == 4 or bound then
    a = GRAY .. "Auction: can't be sold (soulbound)|r"
  else
    local cur, med, n = II.AH(ItemID(link))
    if cur then
      a = ("Auction: ~%s (%s, %d scans)"):format(II.Money(n >= 3 and med or cur), n >= 3 and "median" or "last", n)
    else
      a = GRAY .. "Auction: no scan data yet|r"
    end
  end
  return b, v, a
end

-- ---------------------------------------------------------------- disenchant
function II.KnowsDisenchant()
  -- not ipairs over a table with holes: a missing function would end the loop early
  local fns = {}
  if IsPlayerSpell then fns[#fns + 1] = IsPlayerSpell end
  if IsSpellKnown then fns[#fns + 1] = IsSpellKnown end
  if C_SpellBook and C_SpellBook.IsSpellKnown then fns[#fns + 1] = C_SpellBook.IsSpellKnown end
  for _, f in ipairs(fns) do
    local ok, r = pcall(f, DE_SPELL)
    if ok and r then return true end
  end
  return false
end

local function Row(class, quality, ilvl)
  local t
  if quality == 2 then t = (class == 2 and WEAPON) or (class == 4 and ARMOR)
  elseif quality == 3 then t = RARE
  elseif quality == 4 then t = EPIC end
  if not t or not ilvl then return end
  for _, row in ipairs(t) do
    if ilvl >= row[1] and ilvl <= row[2] then return row end
  end
end
II.DisenchantRow = Row

-- price of a material from the Exchange scan; nil when unscanned or when the game's name for the ID does not match
local function MatPrice(id)
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local name = f and f(id)
  if not name then
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return nil
  end
  if name ~= MAT[id] then return nil end
  local cur, med, n = II.AH(id)
  if not cur then return nil end
  return (n or 0) >= 3 and med or cur
end

-- expected disenchant value in copper, from the AH scan prices of the materials
function II.Disenchant(link)
  local info = Info(link)
  if not info or not info.ilvl then return nil end
  local loc = info.equipLoc
  if not loc or loc == "" or loc == "INVTYPE_BODY" or loc == "INVTYPE_TABARD" then return nil end
  local row = Row(info.class, info.quality, ILvl(link, info.ilvl))
  if not row then return nil end
  local value, priced, total = 0, 0, 0
  for i = 3, #row do          -- row = { low, high, material, material... }
    local o = row[i]
    total = total + 1
    local p = MatPrice(o[1])
    if p then
      priced = priced + 1
      value = value + o[2] * (o[3] + o[4]) / 2 * p
    end
  end
  return { value = value, priced = priced, total = total, approx = row.approx }
end

function II.DisenchantText(d)
  if d.priced == 0 then return GRAY .. "no material prices yet: scan the Exchange|r" end
  local s = "~" .. II.Money(d.value)
  if d.priced < d.total then s = s .. (" (%d of %d materials priced)"):format(d.priced, d.total) end
  if d.approx then s = s .. " (rough)" end
  return s
end

-- ---------------------------------------------------------------- tooltip
-- { left, right } pairs to add under an item tooltip
function II.Lines(link, tip)
  local out = {}
  local info = Info(link)
  if not info then return out end
  local tradable = info.bind ~= 1 and info.bind ~= 4
  if info.sell and info.sell > 0 and not (tip and (tonumber(tip.shownMoneyFrames) or 0) > 0) then
    out[#out + 1] = { "Vendor", II.Money(info.sell) }
  end
  if tradable then
    local cur, med, n, t = II.AH(ItemID(link))
    if cur then
      out[#out + 1] = { "Realm AH", ("now %s   median %s   (%d scans, %s)"):format(II.Money(cur), II.Money(med), n, Ago(t)) }
    end
  end
  if II.KnowsDisenchant() then
    local d = II.Disenchant(link)
    if d then out[#out + 1] = { "Disenchant", II.DisenchantText(d) } end
  end
  return out
end

local function Add(tip, link)
  if not link or not II.Enabled() then return end
  if tip.realmItemInfo == link then return end
  tip.realmItemInfo = link
  local lines = II.Lines(link, tip)
  if #lines == 0 then return end
  for _, l in ipairs(lines) do
    tip:AddDoubleLine(l[1], l[2], .91, .67, .21, 1, 1, 1)
  end
  if tip.Show then tip:Show() end
end
II.AddToTooltip = Add

function II.Hook()
  local names = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }
  for _, n in ipairs(names) do
    local t = _G[n]
    if t and t.HookScript then
      pcall(t.HookScript, t, "OnTooltipCleared", function(self) self.realmItemInfo = nil end)
    end
  end
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip)
      if not (tip and tip.GetItem) then return end
      local ok, _, link = pcall(tip.GetItem, tip)
      if ok and link then pcall(Add, tip, link) end
    end)
  else
    for _, n in ipairs(names) do
      local t = _G[n]
      if t and t.HookScript then
        pcall(t.HookScript, t, "OnTooltipSetItem", function(self)
          local ok, _, link = pcall(self.GetItem, self)
          if ok and link then pcall(Add, self, link) end
        end)
      end
    end
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function() II.Hook() end)

function II.Command(arg)
  local D = ns.DB
  if not D then return end
  if arg == "on" then D.itemTips = true elseif arg == "off" then D.itemTips = false
  else D.itemTips = not II.Enabled() end
  ns.Print("item tooltips (auction data, vendor price, disenchant): " .. (II.Enabled() and "|cff00ff00on|r" or "|cffff4040off|r"))
end
