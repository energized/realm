-- Realm Bags: one combined bag window with sorting, search, and a tab for every character you have played.
-- Each character's bags (and bank, after you open the bank once) are saved to RealmDB when the bags change and
-- when you log out, so any alt can be browsed from any other character. The window is optional: it replaces the
-- default bag keys only when "One bag" is turned on (/realm bags on, or the setup window).
local ADDON, ns = ...
local Bags = {}
ns.Bags = Bags

local COLS, CELL, GAP = 10, 38, 4           -- GAP is the little space between slots
local HDR, SGAP = 20, 8                     -- category header height, space after a category
local DB
local frame, buttons = nil, {}
local viewKey, viewBank, sortMode, filterText = nil, false, "bag", ""
local bankOpen = false
local UpdatePouch                       -- minimized-bag icon (defined below)
local DRAWER_W = 112
local drawer = { open = false, w = 0, t = 0 }   -- alt-character drawer on the bag's left edge

local CC = C_Container
local NumSlots = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
-- gold / silver / copper with the coin icons (shared formatter in Realm.lua)
local function Money(c, h) return ns.Coin(c, h) end
local function Print(m) if ns.Print then ns.Print(m) end end

-- ------------------------------------------------------------ pure helpers (unit tested)
local SORTS = { category = "categories", separate = "separate bags", bag = "bag order", type = "type", quality = "quality", name = "name", value = "value" }
local SORT_ORDER = { "category", "separate", "bag", "type", "quality", "name", "value" }
Bags.SORTS = SORTS

local function ItemName(link)
  return (link and link:match("%[(.-)%]")) or "?"
end

-- raw slot data -> one stored item
function Bags.MakeItem(bag, slot, link, count, quality, icon, classID, price, id, ilvl)
  if not link then return nil end
  return {
    bag = bag, slot = slot, link = link, count = count or 1, q = quality or 1, icon = icon,
    cls = classID or 99, price = price or 0, name = ItemName(link),
    id = id or tonumber(link:match("item:(%d+)")), ilvl = ilvl,
  }
end

local function Cmp(mode)
  if mode == "type" then
    return function(a, b)
      if a.cls ~= b.cls then return a.cls < b.cls end
      if a.q ~= b.q then return a.q > b.q end
      return a.name < b.name
    end
  elseif mode == "quality" then
    return function(a, b)
      if a.q ~= b.q then return a.q > b.q end
      return a.name < b.name
    end
  elseif mode == "name" then
    return function(a, b)
      if a.name ~= b.name then return a.name < b.name end
      return a.count > b.count
    end
  elseif mode == "value" then
    return function(a, b)
      local va, vb = a.price * a.count, b.price * b.count
      if va ~= vb then return va > vb end
      return a.name < b.name
    end
  end
  return function(a, b)
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
  end
end

-- returns a new list, filtered by text and ordered by mode
function Bags.Arrange(items, mode, text)
  local out = {}
  text = (text or ""):lower()
  for _, it in ipairs(items or {}) do
    if text == "" or it.name:lower():find(text, 1, true) then out[#out + 1] = it end
  end
  table.sort(out, Cmp(mode or "bag"))
  return out
end

-- the item to drop when a loot will not fit: the lowest total vendor value. Only poor (grey) and common (white) items
-- are ever picked. Never picked: uncommon or better, quest items, items with no vendor price (0 means "cannot be sold",
-- not "cheap"), profession items (profession bag items, trade goods, reagents, gems, recipes, enhancements), and
-- consumables (food, potions) since those sell on the auction house. A common item must be plain armor or a weapon.
function Bags.CheapestDroppable(items)
  local best, bestVal
  for _, it in ipairs(items or {}) do
    local price = it.price or 0
    local q, c = it.q or 1, it.cls
    local profession = (it.fam and it.fam ~= 0) or c == 3 or c == 5 or c == 7 or c == 8 or c == 9
    local ok = q == 0 or (q == 1 and (c == 2 or c == 4))
    if price > 0 and c ~= 12 and ok and not profession then
      local val = price * (it.count or 1)
      if not best or val < bestVal or (val == bestVal and (it.q or 1) < (best.q or 1)) then best, bestVal = it, val end
    end
  end
  return best, bestVal
end

-- ------------------------------------------------------------ categories
local CAT_GEAR, CAT_USE, CAT_CRAFT, CAT_QUEST, CAT_BAGS, CAT_JUNK, CAT_GENERAL =
  "Armor & Weapons", "Consumables", "Crafting & Professions", "Quest", "Bags", "Junk", "General"
local CAT_ORDER = { CAT_GEAR, CAT_USE, CAT_CRAFT, CAT_QUEST, CAT_BAGS, CAT_JUNK, CAT_GENERAL }
Bags.CATEGORIES = CAT_ORDER

-- which section an item belongs to. Anything that does not fit stays in General.
function Bags.Category(it)
  if not it then return CAT_GENERAL end
  if it.q == 0 then return CAT_JUNK end
  if it.fam and it.fam ~= 0 then return CAT_CRAFT end      -- sits in a profession bag (herb, mining, enchanting...)
  local c = it.cls
  if c == 2 or c == 4 then return CAT_GEAR end
  if c == 0 then return CAT_USE end
  if c == 3 or c == 5 or c == 7 or c == 9 then return CAT_CRAFT end   -- gems, reagents, trade goods, recipes
  if c == 12 then return CAT_QUEST end
  if c == 1 then return CAT_BAGS end
  return CAT_GENERAL
end

-- items filtered by text and grouped by category. `empties` (a list) are free slots; they all start in General
-- and leave it as items arrive. Empty sections are left out.
function Bags.Sections(items, text, empties)
  local sorted = Bags.Arrange(items, "type", text)
  local by = {}
  for _, it in ipairs(sorted) do
    local k = Bags.Category(it)
    by[k] = by[k] or {}
    by[k][#by[k] + 1] = it
  end
  local out = {}
  for _, name in ipairs(CAT_ORDER) do
    local list = by[name] or {}
    local free = (name == CAT_GENERAL) and empties or nil
    if #list > 0 or (free and #free > 0) then out[#out + 1] = { name = name, items = list, empties = free } end
  end
  return out
end

-- name of a container id when the live inventory is not available (saved views)
function Bags.BagName(bag)
  if bag == 0 then return "Backpack" end
  if bag == -1 then return "Bank" end
  return "Bag " .. tostring(bag)
end

-- one section per bag, each with its slots in slot order. `bags` (live view) is a list of { bag, name, size } and
-- gives every slot, free ones included, so a free slot can take a dropped bag. Without it (saved view, or while
-- searching) only the items found are shown, grouped by bag.
function Bags.SeparateSections(items, text, bags)
  local filtered = Bags.Arrange(items, "bag", text)
  local by = {}
  for _, it in ipairs(filtered) do
    if it.bag and it.slot then
      by[it.bag] = by[it.bag] or {}
      by[it.bag][it.slot] = it
    end
  end
  local searching = text ~= nil and text ~= ""
  local list = bags
  if not list then
    list = {}
    for bag in pairs(by) do list[#list + 1] = { bag = bag, name = Bags.BagName(bag) } end
    table.sort(list, function(a, b) return a.bag < b.bag end)
  end
  local out = {}
  for _, b in ipairs(list) do
    local slots, ordered, used = by[b.bag] or {}, {}, 0
    if b.size and not searching then
      for s = 1, b.size do
        if slots[s] then used = used + 1; ordered[#ordered + 1] = { item = slots[s] }
        else ordered[#ordered + 1] = { bag = b.bag, slot = s } end
      end
    else
      local keys = {}
      for s in pairs(slots) do keys[#keys + 1] = s end
      table.sort(keys)
      for _, s in ipairs(keys) do used = used + 1; ordered[#ordered + 1] = { item = slots[s] } end
    end
    if #ordered > 0 then
      local label = (b.size and not searching) and ("%s  %d/%d"):format(b.name, used, b.size) or ("%s  %d"):format(b.name, used)
      out[#out + 1] = { name = b.name, label = label, items = {}, ordered = ordered }
    end
  end
  return out
end

-- pixel positions for each section: returns cells, headers, total height
function Bags.Layout(sections, cols, cell, hdr, gap, rowh)
  rowh = rowh or cell                       -- row pitch: squeezing shrinks this, never the column pitch
  local cells, heads, y = {}, {}, 0
  for _, sec in ipairs(sections) do
    if sec.name then
      heads[#heads + 1] = { name = sec.name, n = #sec.items, y = y, label = sec.label }
      y = y + hdr
    end
    local idx = 0
    for _, it in ipairs(sec.items) do
      cells[#cells + 1] = { item = it, x = (idx % cols) * cell, y = y + math.floor(idx / cols) * rowh }
      idx = idx + 1
    end
    for _, e in ipairs(sec.empties or {}) do
      cells[#cells + 1] = { empty = true, bag = e.bag, slot = e.slot, x = (idx % cols) * cell, y = y + math.floor(idx / cols) * rowh }
      idx = idx + 1
    end
    for _, e in ipairs(sec.ordered or {}) do          -- one bag's slots, in slot order (items and free slots mixed)
      local c = { x = (idx % cols) * cell, y = y + math.floor(idx / cols) * rowh }
      if e.item then c.item = e.item else c.empty, c.bag, c.slot = true, e.bag, e.slot end
      cells[#cells + 1] = c
      idx = idx + 1
    end
    y = y + math.ceil(idx / cols) * rowh + (sec.name and gap or 0)
  end
  return cells, heads, y
end

-- money as 12g 34s 56c with coloured letters
function Bags.MoneyText(c)
  c = math.max(0, math.floor(tonumber(c) or 0))
  local g, s, cp = math.floor(c / 10000), math.floor(c % 10000 / 100), c % 100
  local out = {}
  if g > 0 then out[#out + 1] = ("%d|cffffd700g|r"):format(g) end
  if g > 0 or s > 0 then out[#out + 1] = ("%d|cffc0c0c0s|r"):format(s) end
  out[#out + 1] = ("%d|cffeda55fc|r"):format(cp)
  return table.concat(out, " ")
end

-- every character's items merged by item id, with a per-character breakdown
function Bags.Combine(all)
  local byId, order = {}, {}
  for charKey, rec in pairs(all or {}) do
    for _, list in ipairs({ rec.items or {}, rec.bank or {} }) do
      for _, it in ipairs(list) do
        local key = it.id or it.name
        local e = byId[key]
        if not e then
          e = { id = it.id, link = it.link, name = it.name, icon = it.icon, q = it.q, cls = it.cls, price = it.price, fam = it.fam,
                count = 0, who = {}, bag = 0, slot = 0 }
          byId[key] = e; order[#order + 1] = e
        end
        e.count = e.count + it.count
        e.who[charKey] = (e.who[charKey] or 0) + it.count
      end
    end
  end
  return order
end

-- ------------------------------------------------------------ reading the live bags
local function SlotInfo(bag, slot)
  if CC and CC.GetContainerItemInfo then
    local i = CC.GetContainerItemInfo(bag, slot)
    if i and i.hyperlink then return i.hyperlink, i.stackCount or 1, i.quality, i.iconFileID, i.itemID end
  elseif GetContainerItemInfo then
    local icon, count, _, quality, _, _, link = GetContainerItemInfo(bag, slot)
    if link then return link, count or 1, quality, icon end
  end
end

local function InfoFor(link)
  local classID, price, ilvl
  local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if inst then
    local ok, _, _, _, _, _, c = pcall(inst, link)
    if ok then classID = c end
  end
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if fn then
    local ok, a, b, c, d, e, f, g, h, i, j, p = pcall(fn, link)
    if ok then price = p; ilvl = d end
  end
  local det = C_Item and C_Item.GetDetailedItemLevelInfo
  if det then
    local ok, v = pcall(det, link)
    if ok and tonumber(v) and v > 0 then ilvl = v end
  end
  return classID, price, ilvl
end

-- the (up to three) currencies shown in the backpack, as { name, qty, icon }
local function BackpackCurrencies()
  local out = {}
  for i = 1, 3 do
    local name, qty, icon
    local api = C_CurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo
    if api then
      local ok, t = pcall(api, i)
      if ok and type(t) == "table" then name, qty, icon = t.name, t.quantity, t.iconFileID end
    elseif GetBackpackCurrencyInfo then
      local ok, a, b, c = pcall(GetBackpackCurrencyInfo, i)
      if ok then name, qty, icon = a, b, c end
    end
    if name then out[#out + 1] = { name = name, qty = qty or 0, icon = icon } end
  end
  return out
end

local function ReagentBag()
  return Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
end

local function InventoryBags()
  local list, last = {}, NUM_BAG_SLOTS or 4
  for b = 0, last do list[#list + 1] = b end
  local r = ReagentBag()
  if r then list[#list + 1] = r end
  return list
end

local function BankBags()
  local list = { -1 }
  local first = (NUM_BAG_SLOTS or 4) + 1 + (ReagentBag() and 1 or 0)
  for b = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do list[#list + 1] = b end
  return list
end

local function BagFamily(bag)
  if ReagentBag() and bag == ReagentBag() then return 1 end
  local fn = (CC and CC.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
  if fn then
    local ok, _, fam = pcall(fn, bag)
    if ok and tonumber(fam) then return fam end
  end
  return 0
end

-- the free slots of your live inventory bags, as { bag, slot }
local function LiveEmpties()
  local out = {}
  for _, bag in ipairs(InventoryBags()) do
    for slot = 1, (NumSlots and NumSlots(bag)) or 0 do
      if not SlotInfo(bag, slot) then out[#out + 1] = { bag = bag, slot = slot } end
    end
  end
  return out
end

-- your live inventory bags as { bag, name, size }, named by what sits in each bag slot. Empty bag slots are left out.
local function LiveBagList()
  local out = {}
  local inv = (C_Container and C_Container.ContainerIDToInventoryID) or ContainerIDToInventoryID
  local reagent = ReagentBag()
  for _, bag in ipairs(InventoryBags()) do
    local size = (NumSlots and NumSlots(bag)) or 0
    if size > 0 then
      local name
      if bag == 0 then name = "Backpack"
      else
        local link
        if inv and GetInventoryItemLink then
          local ok, id = pcall(inv, bag)
          if ok and id then link = GetInventoryItemLink("player", id) end
        end
        local item = link and link:match("%[(.-)%]")
        name = ((reagent and bag == reagent) and "Reagent Bag" or ("Bag " .. bag)) .. (item and (": " .. item) or "")
      end
      out[#out + 1] = { bag = bag, name = name, size = size }
    end
  end
  return out
end

local function ScanBags(list)
  local items, total, used = {}, 0, 0
  for _, bag in ipairs(list) do
    local n = (NumSlots and NumSlots(bag)) or 0
    total = total + n
    local fam = BagFamily(bag)
    for slot = 1, n do
      local link, count, quality, icon, id = SlotInfo(bag, slot)
      if link then
        used = used + 1
        local cls, price, ilvl = InfoFor(link)
        local item = Bags.MakeItem(bag, slot, link, count, quality, icon, cls, price, id, ilvl)
        item.fam = fam
        items[#items + 1] = item
      end
    end
  end
  return items, total, used
end

local function CharKey()
  return ((UnitName and UnitName("player")) or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "")
end
Bags.CharKey = CharKey

-- Every spelling of this character's name the game gives us. WoW Forever has two-part names ("Aawesome AAdeals"),
-- and which call returns the whole thing is not known, so ask them all. Mule tries the two-part ones first.
function Bags.NameForms()
  local out, seen = {}, {}
  local function add(s)
    if type(s) == "string" and s ~= "" and not seen[s:lower()] then seen[s:lower()] = true; out[#out + 1] = s end
  end
  local function try(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
  end
  add((try(UnitName, "player")))
  add((try(UnitFullName, "player")))
  add((try(GetUnitName, "player", true)))
  add((try(GetUnitName, "player", false)))
  if UnitGUID and GetPlayerInfoByGUID then
    local g = try(UnitGUID, "player")
    if g then
      local ok, _, _, _, _, _, name = pcall(GetPlayerInfoByGUID, g)
      if ok then add(name) end
    end
  end
  return out
end

-- What each name call returned, as plain lines, so a name that looks short can be traced to the call that cut it.
function Bags.NameDiag()
  local out = {}
  local function probe(label, fn, ...)
    if type(fn) ~= "function" then return end
    local ok, cnt, vals = (function(ok, ...) return ok, select("#", ...), { ... } end)(pcall(fn, ...))
    if not ok then return end
    local parts = {}
    for i = 1, math.min(cnt, 3) do parts[#parts + 1] = tostring(vals[i]) end
    out[#out + 1] = label .. " = " .. (#parts > 0 and table.concat(parts, ", ") or "nothing")
  end
  probe("UnitName", UnitName, "player")
  probe("UnitFullName", UnitFullName, "player")
  probe("GetUnitName(true)", GetUnitName, "player", true)
  probe("GetUnitName(false)", GetUnitName, "player", false)
  probe("GetRealmName", GetRealmName)
  probe("GetNormalizedRealmName", GetNormalizedRealmName)
  return out
end

-- save this character's bags (and bank when it is open) into RealmDB
function Bags.Snapshot(leaving)
  if not DB then return end
  local key = CharKey()
  local rec = DB.bags[key] or {}
  DB.bags[key] = rec
  rec.name = (UnitName and UnitName("player")) or "?"
  rec.realm = (GetRealmName and GetRealmName()) or ""
  rec.full = GetUnitName and GetUnitName("player", true) or nil
  rec.names = Bags.NameForms()
  rec.diag = Bags.NameDiag()
  rec.class = select(2, UnitClass("player"))
  rec.level = UnitLevel and UnitLevel("player")
  rec.money = GetMoney and GetMoney() or 0
  rec.time = time()
  rec.cur = BackpackCurrencies()
  local items, total, used = ScanBags(InventoryBags())
  -- The game can answer with nothing while it is not ready (login, and above all logout). An empty answer must never
  -- wipe the last good copy, or the alt's tab shows empty bags: keep the old scan then.
  local notReady = (total == 0 and (rec.total or 0) > 0) or (leaving and used == 0 and (rec.used or 0) > 0)
  if not notReady then rec.items, rec.total, rec.used = items, total, used end
  if bankOpen then
    local bank, bankTotal, bankUsed = ScanBags(BankBags())
    if not (bankTotal == 0 and (rec.bankTotal or 0) > 0) then
      rec.bank, rec.bankTotal, rec.bankUsed = bank, bankTotal, bankUsed
      rec.bankTime = time()
    end
  end
  if UpdatePouch then UpdatePouch() end
  return rec
end

-- ------------------------------------------------------------ window
local Refresh, BuildOptions

-- free slots text: red when nearly full
function Bags.FreeText(used, total)
  total, used = total or 0, used or 0
  local free = math.max(0, total - used)
  local col = free == 0 and "ff4040" or (free <= 3 and "ffaa33" or "66ff66")
  return ("|cff%s%d free|r / %d"):format(col, free, total), free
end

-- ------------------------------------------------------------ options (the gear menu)
local OPT_DEFAULT = { free = true, money = true, currency = true, ilvl = true, quality = true, delay = 6, fontSize = 11 }
local DELAYS = { 0, 3, 6, 10 }          -- seconds before the alt drawer slides back in; 0 = stays open
Bags.DELAYS = DELAYS
function Bags.Opt(k)
  local v = DB and DB.bagOpt and DB.bagOpt[k]
  if v == nil then return OPT_DEFAULT[k] end
  return v
end
function Bags.SetOpt(k, v)
  if not DB then return end
  DB.bagOpt = DB.bagOpt or {}
  DB.bagOpt[k] = v
  if Refresh then Refresh() end
end
function Bags.NextDelay()
  local cur = Bags.Opt("delay")
  local nxt = DELAYS[1]
  for i, d in ipairs(DELAYS) do if d == cur then nxt = DELAYS[i % #DELAYS + 1]; break end end
  Bags.SetOpt("delay", nxt)
  return nxt
end

-- text size of the gold and currency lines (gear menu, or /realm bags fontsize N)
local FONT_MIN, FONT_MAX, FONT_BASE = 9, 20, 11
local FONT_FILE = "Fonts\\FRIZQT__.TTF"
local MONEY_FONT = "Fonts\\ARIALN.TTF"                   -- clean, plain digits for the gold line
-- colours of the dark navy look: panel, border, divider lines
local NAVY, EDGE_RED = { .04, .06, .13, .93 }, { .50, .20, .15, 1 }
local RULE_RED = { .70, .18, .14, .85 }
function Bags.ClampFont(n)
  n = tonumber(n) or FONT_BASE
  return math.max(FONT_MIN, math.min(FONT_MAX, math.floor(n + 0.5)))
end
function Bags.FontSize() return Bags.ClampFont(Bags.Opt("fontSize")) end
function Bags.StepFont(delta) Bags.SetOpt("fontSize", Bags.ClampFont(Bags.FontSize() + delta)) end

-- header rows scale with the text size: the <-Alts button sits on the left with the gold beside it, then the currency
-- line; returns y offsets and header height
function Bags.HeaderLayout(size)
  size = Bags.ClampFont(size)
  local lh = size + 3
  local handle = 40                          -- the <-Alts button sits on the left and the gold beside it, on the same row
  local money = handle
  local cur = handle + math.max(20, lh + 6)  -- the currency row sits just under that row and drops with bigger text
  return { money = money, cur = cur, handle = handle, head = cur + lh + 6, line = lh }
end
function Bags.HeadHeight() return Bags.HeaderLayout(Bags.FontSize()).head end

-- currencies as one line: icon and amount for each (icon follows the text size)
function Bags.CurrencyText(list, size)
  local parts = {}
  local px = Bags.ClampFont(size or Bags.FontSize()) + 3
  for _, c in ipairs(list or {}) do
    local icon = c.icon and ("|T%s:%d|t "):format(tostring(c.icon), px) or ((c.name or "?") .. " ")
    parts[#parts + 1] = icon .. tostring(c.qty or 0)
  end
  return table.concat(parts, "   ")
end

-- one animation step of the alt drawer. s = { open, w, t }; w is its width, t the idle seconds.
-- It closes itself after `delay` seconds without the mouse over it (delay 0 = never).
function Bags.DrawerStep(s, dt, over, delay, width)
  if s.open then
    if over or not delay or delay <= 0 then s.t = 0
    else
      s.t = s.t + dt
      if s.t >= delay then s.open = false end
    end
  end
  local speed = width / 0.15
  if s.open then s.w = math.min(width, s.w + speed * dt) else s.w = math.max(0, s.w - speed * dt) end
  return s
end

-- the minimized bag: a small cloth pouch with the free-slot count under it
local pouch
function UpdatePouch()
  if not DB then return end
  if not DB.bagMin then if pouch then pouch:Hide() end return end
  if not pouch then
    pouch = CreateFrame("Button", "RealmBagPouch", UIParent)
    pouch:SetSize(96, 74)
    pouch:SetFrameStrata("HIGH")
    pouch:SetMovable(true); pouch:EnableMouse(true); pouch:SetClampedToScreen(true)
    pouch:RegisterForDrag("LeftButton")
    pouch:SetScript("OnDragStart", function(self) if not (DB and DB.bagLocked) then self:StartMoving() end end)
    pouch:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      local p, _, rp, x, y = self:GetPoint()
      DB.bagPouchPos = { p, rp, x, y }
    end)
    pouch.tex = pouch:CreateTexture(nil, "ARTWORK")
    pouch.tex:SetSize(44, 44); pouch.tex:SetPoint("TOP", 0, 0)
    pouch.tex:SetTexture("Interface\\AddOns\\Realm\\Path\\icons\\bag")
    pouch.tex:SetVertexColor(.78, .55, .31)
    pouch.txt = pouch:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pouch.txt:SetPoint("TOP", pouch.tex, "BOTTOM", 0, 0)
    pouch.gold = pouch:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")     -- gold, silver, copper under the free-slot count
    pouch.gold:SetPoint("TOP", pouch.txt, "BOTTOM", 0, -1)
    pouch:SetScript("OnClick", function() Bags.Show() end)
    pouch:SetScript("OnEnter", function(self)
      if not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine("Realm Bags")
      GameTooltip:AddLine("Click to open. Drag to move.", .8, .8, .8)
      GameTooltip:Show()
    end)
    pouch:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    local pos = DB.bagPouchPos
    if pos then pouch:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else pouch:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -80, 120) end
  end
  local rec = DB.bags[CharKey()]
  local text = rec and Bags.FreeText(rec.used, rec.total) or ""
  pouch.txt:SetText(text)
  pouch.gold:SetText((rec and Bags.Opt("money")) and Bags.MoneyText(rec.money) or "")   -- follows the gear menu's "Show gold"
  pouch:Show()
end

-- frame lock + scale: the padlock freezes moving and resizing; the corner grip scales the whole bag
local SCALE_MIN, SCALE_MAX = 0.6, 2.0
function Bags.ClampScale(s)
  s = tonumber(s) or 1
  return math.max(SCALE_MIN, math.min(SCALE_MAX, s))
end
function Bags.ScaleForWidth(width, baseWidth)          -- width the cursor asks for, in screen units
  if not baseWidth or baseWidth <= 0 then return 1 end
  return Bags.ClampScale(width / baseWidth)
end
function Bags.IsLocked() return DB and DB.bagLocked and true or false end
function Bags.SetLocked(v)
  if not DB then return end
  DB.bagLocked = v and true or false
  if frame and frame.lockTex then
    frame.lockTex:SetTexture(DB.bagLocked and "Interface\\Buttons\\LockButton-Locked-Up" or "Interface\\Buttons\\LockButton-Unlocked-Up")
    if frame.grip then if DB.bagLocked then frame.grip:Hide() else frame.grip:Show() end end
    if frame.squeeze then if DB.bagLocked then frame.squeeze:Hide() else frame.squeeze:Show() end end
  end
end
function Bags.SetScaleValue(s)
  if not DB then return end
  DB.bagScale = Bags.ClampScale(s)
  if frame then frame:SetScale(DB.bagScale) end
end
local function SaveFramePos(f)
  local p, _, rp, x, y = f:GetPoint()
  if p then DB.bagPos = { p, rp, x, y } end
end

function Bags.Minimize()
  if not DB then return end
  DB.bagMin = true
  drawer.open, drawer.w, drawer.t = false, 0, 0      -- the character drawer slides in with it
  if frame then
    frame.drawer:SetWidth(1); frame.drawer:Hide()
    frame:Hide()
  end
  UpdatePouch()
end

local function CharList()
  local list = {}
  for key, rec in pairs(DB.bags) do list[#list + 1] = { key = key, rec = rec } end
  table.sort(list, function(a, b)
    if a.key == CharKey() then return true end
    if b.key == CharKey() then return false end
    return a.key < b.key
  end)
  return list
end

local function Source()
  if viewKey == "ALL" then return Bags.Combine(DB.bags), nil end
  local rec = DB.bags[viewKey or CharKey()]
  if not rec then return {}, nil end
  if viewBank then return rec.bank or {}, rec end
  return rec.items or {}, rec
end

-- drag and drop: pick an item up by dragging it, drop it by releasing on any slot (swaps if the slot is taken)
local function Pick(bag, slot)
  local pick = (CC and CC.PickupContainerItem) or PickupContainerItem
  if pick and bag and slot then pick(bag, slot) end
end
local function CanAct(self) return self.live and not (InCombatLockdown and InCombatLockdown()) end
local function Target(self)
  if self.item then return self.item.bag, self.item.slot end
  return self.eBag, self.eSlot
end

-- ------------------------------------------------------------ drop toggle (footer button)
-- On: when a loot will not fit because the bags are full, the cheapest safe item is named in chat (the game blocks addons from deleting it).
local DROP_HELP = "If enabled will drop cheapest item in bag if when looting you are full and will attempt another loot."
local MAX_DROPS = 10                         -- deletions per loot window: a runaway guard (every delete still needs the player's own click)
local lootOpen, dropBusy, drops = false, false, 0
local castStamp, wantDrop = 0, nil                -- castStamp: last channel start/stop of the player (Drain Soul puts a shard in the bags with no loot window); wantDrop: a full-bag error came in combat
local lootStamp = 0                          -- GetTime() of the last loot event: auto-loot can fire the full-bag error around the window
Bags.DROP_HELP = DROP_HELP

local function Now() return (GetTime and GetTime()) or 0 end
-- /realm bags drop debug on|off: says why a drop did or did not happen
local function Dbg(m) if DB and DB.bagDropDebug then Print("|cff999999drop debug:|r " .. m) end end
local function LootActive() return lootOpen or (Now() - lootStamp) < 2.5 end
local function CastActive()
  if UnitChannelInfo and UnitChannelInfo("player") then return true end
  return (Now() - castStamp) < 2.5
end
local function HasCursor()
  if CursorHasItem then return CursorHasItem() and true or false end
  if C_Cursor and C_Cursor.GetCursorItem then return C_Cursor.GetCursorItem() ~= nil end
  return false
end
-- the "bags are full" text: the game constant when present, plus plain-text matches in case the client words it differently
local function IsFullMsg(msg)
  if type(msg) ~= "string" then return false end
  if msg == _G.ERR_INV_FULL or msg == _G.ERR_BAG_FULL then return true end
  local m = msg:lower()
  return m:find("inventory is full", 1, true) or m:find("bags are full", 1, true) or m:find("bag is full", 1, true) or false
end
Bags.IsFullMsg = IsFullMsg

-- on by default: only an explicit false (button or /realm bags drop off) turns it off
function Bags.DropOn() return DB ~= nil and DB.bagDrop ~= false end

local function PaintDrop()
  local b = frame and rawget(frame, "dropBtn")
  if b then b:SetText(Bags.DropOn() and "|cff66ff66Drop|r" or "|cffaaaaaaDrop|r") end
end

function Bags.SetDrop(v)
  if not DB then return end
  DB.bagDrop = v and true or false
  PaintDrop()
  Print("drop: " .. (DB.bagDrop and "ON. A full bag will lose its cheapest item so a loot can land." or "off."))
end

local function RetryLoot()
  dropBusy = false
  local n = (GetNumLootItems and GetNumLootItems()) or 0
  if not lootOpen or n == 0 then
    Print("drop: room made. No loot window is open, so loot or cast again if something was lost.")
    return
  end
  Dbg("retrying " .. n .. " loot slot(s)")
  for slot = n, 1, -1 do
    if LootSlot then pcall(LootSlot, slot) end
  end
  -- more than one item may need room: shortly after the retry, if loot is still waiting and bags are still full, offer the next one
  if C_Timer and C_Timer.After then C_Timer.After(0.7, function() if Bags.CheckStuck then Bags.CheckStuck() end end) end
end

-- The Delete button: one click = the hardware event the game requires for DeleteCursorItem.
local delBtn, delItem
local function LinkAt(bag, slot)
  if CC and CC.GetContainerItemLink then return CC.GetContainerItemLink(bag, slot) end
  if GetContainerItemLink then return GetContainerItemLink(bag, slot) end
  return nil
end
local function HideDelete() delItem = nil; if delBtn then delBtn:Hide() end end
Bags.HideDelete = HideDelete

-- Checks shared by both delete routes. Returns true when it is safe to pick the item up and delete it.
local function Precheck(it)
  if InCombatLockdown and InCombatLockdown() then Print("drop: not in combat."); return false end
  if HasCursor() then Print("drop: put down what is on your cursor first, then try again."); return false end
  local now = LinkAt(it.bag, it.slot)
  if now ~= nil and now ~= it.link then Print("drop: that slot changed, so nothing was deleted."); return false end
  return true
end

-- Listens for the game's ADDON_ACTION_BLOCKED so the report can say whether DeleteCursorItem was truly refused.
local function StartWatch()
  local st = { blocked = false }
  st.frame = CreateFrame("Frame")
  st.frame:RegisterEvent("ADDON_ACTION_BLOCKED")
  st.frame:SetScript("OnEvent", function(_, _, _, fn)
    if tostring(fn or ""):find("DeleteCursorItem", 1, true) then st.blocked = true end
  end)
  return st
end

-- Success is judged by the bag slot, not the cursor (the cursor can read "holding" for an instant after a delete).
local function Finish(it, st)
  if st.frame and st.frame.UnregisterAllEvents then st.frame:UnregisterAllEvents() end
  if LinkAt(it.bag, it.slot) == it.link then
    Dbg("slot still holds " .. it.link .. "; blocked event seen: " .. tostring(st.blocked))
    Print("drop: " .. it.link .. " is still in your bag, so the delete did not happen"
      .. (st.blocked and " (the game blocked DeleteCursorItem for Realm)." or " (the game gave no block message)."))
    return
  end
  Dbg("deleted " .. it.link)
  drops = drops + 1                                  -- the cap counts real deletions, not offers or repeated error lines
  Print("drop: deleted " .. it.link .. (it.count > 1 and (" x" .. it.count) or "") .. ".")
  RetryLoot()
end
local function FinishLater(it, st)
  if C_Timer and C_Timer.After then C_Timer.After(0.3, function() Finish(it, st) end) else Finish(it, st) end
end

-- The proxy button the secure macro clicks (/click RealmDelItem). Same shape as the community DeleteCursorItemFix addon:
-- a plain button whose click makes the delete call, then clears the cursor.
local function EnsureProxy()
  if _G.RealmDelItem then return end
  local p = CreateFrame("Button", "RealmDelItem")
  p:SetScript("OnClick", function()
    Dbg("proxy click reached DeleteCursorItem")
    DeleteCursorItem()
    if ClearCursor then ClearCursor() end
  end)
end

-- Direct route (a plain click handler). Kept as the fallback and for the tests; the secure macro route below is the live one.
local function DoDelete()
  local it = delItem
  HideDelete()
  if not it then return end
  if not Precheck(it) then return end
  Pick(it.bag, it.slot)
  if not HasCursor() then Print("drop: could not pick up " .. it.link .. "."); return end
  local st = StartWatch()
  DeleteCursorItem()
  if ClearCursor then ClearCursor() end
  FinishLater(it, st)
end

-- Secure route: the macro runs ClearCursor, picks the item up, then /clicks the proxy. PreClick checks and arms the macro;
-- PostClick starts the verify. (Secure attributes cannot change in combat, and Drop never offers in combat.)
local pending
local function DelPreClick(self)
  pending = nil
  local it = delItem
  if not it or (InCombatLockdown and InCombatLockdown()) then self:SetAttribute("macrotext", ""); return end
  if not Precheck(it) then self:SetAttribute("macrotext", ""); return end
  EnsureProxy()
  local pk = (CC and CC.PickupContainerItem) and "C_Container.PickupContainerItem" or "PickupContainerItem"
  self:SetAttribute("macrotext", "/run ClearCursor()\n/run " .. pk .. "(" .. it.bag .. "," .. it.slot .. ")\n/click RealmDelItem")
  pending = { it = it, st = StartWatch() }
  Dbg("macro armed for " .. it.link)
end
local function DelPostClick()
  local p = pending
  pending = nil
  if not p then return end
  HideDelete()
  FinishLater(p.it, p.st)
end

-- vendor value text: a single item shows its price only; a stack shows the price each plus the stack total
local function ValueText(it)
  local p, n = it.price or 0, it.count or 1
  if n <= 1 then return Money(p) end
  return Money(p) .. " each, " .. Money(p * n) .. " stack"
end
Bags.ValueText = ValueText

local function ShowDelete(it)
  delItem = it
  if not delBtn then
    delBtn = CreateFrame("Button", "RealmDropDeleteButton", UIParent, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    delBtn:SetSize(400, 30)
    delBtn:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
    if delBtn.SetFrameStrata then delBtn:SetFrameStrata("DIALOG") end
    delBtn:RegisterForClicks("LeftButtonUp")
    delBtn:SetAttribute("type", "macro")
    delBtn:SetAttribute("useOnKeyDown", false)
    delBtn:SetScript("PreClick", DelPreClick)
    delBtn:SetScript("PostClick", DelPostClick)
  end
  delBtn:SetText("Delete " .. (it.link or "item") .. (it.count > 1 and (" x" .. it.count) or "") .. "  (" .. ValueText(it) .. ")")
  delBtn:Show()
  if C_Timer and C_Timer.After then
    C_Timer.After(20, function() if delItem == it then HideDelete() end end)   -- stale offers go away on their own
  end
end
Bags.ShowDelete, Bags.DoDelete = ShowDelete, DoDelete

-- called when the game says the bags are full around a loot. `why` is only used by the debug prints.
function Bags.TryDrop(why, force)
  local function No(reason) Dbg("not dropping: " .. reason .. (why and (" [" .. why .. "]") or "")); return false end
  if not Bags.DropOn() then return No("Drop is off") end
  if not (force or LootActive() or CastActive()) then return No("no loot window or channel is active (or was in the last 2.5 seconds)") end
  if dropBusy then return No("a drop is already in progress") end
  if delItem then return No("a Delete offer is already waiting") end   -- several loot slots fail at once and each raises the error: one offer is enough
  if drops >= MAX_DROPS then return No("already dropped " .. MAX_DROPS .. " items for this loot") end
  if InCombatLockdown and InCombatLockdown() then
    wantDrop = why or true                        -- the Delete button cannot be armed in combat: offer it when combat ends
    return No("in combat, will offer when combat ends")
  end
  if HasCursor() then return No("the cursor is holding something") end          -- the player is holding something: leave it alone
  local it = Bags.CheapestDroppable((ScanBags(InventoryBags())))
  if not it then
    Print("drop: nothing safe to drop (only grey items and white armor or weapons are ever dropped).")
    return false
  end
  -- DeleteCursorItem is protected: it only works inside a real mouse click or key press (a "hardware event"), never from an
  -- event handler (that is the ADDON_ACTION_BLOCKED). So Drop names the item and shows a Delete button; the pickup and the
  -- delete both run inside the player's click on that button, then the loot is retried.
  Dbg("offering " .. it.link .. " from bag " .. it.bag .. " slot " .. it.slot .. (why and (" [" .. why .. "]") or ""))
  ShowDelete(it)
  Print("bags full. Click the Delete button to destroy " .. it.link .. (it.count > 1 and (" x" .. it.count) or "")
    .. " worth " .. ValueText(it) .. " and loot again.")
  return true
end

-- Right-click use is a protected action: an addon's own click handler is not allowed to call UseContainerItem
-- (the game blocks the addon). So each cell is a secure button carrying the "use this item" action itself.
-- Secure attributes cannot change in combat, so Refresh waits until combat ends.
local function InCombat() return InCombatLockdown and InCombatLockdown() end
local function Arm(b, it, live)
  if InCombat() then return end
  if live and it and it.bag and it.slot then
    b:SetAttribute("type2", "item")
    b:SetAttribute("item2", it.bag .. " " .. it.slot)
  else
    b:SetAttribute("type2", nil)
    b:SetAttribute("item2", nil)
  end
end

local function Cell(i)
  local b = buttons[i]
  if b then return b end
  b = CreateFrame("Button", nil, frame.content, "SecureActionButtonTemplate")
  b:SetAttribute("shift-type2", "")        -- shift+right-click stays a plain click (no item use)
  b:SetSize(CELL - GAP, CELL - GAP)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
  b.border = b:CreateTexture(nil, "OVERLAY"); b.border:SetAllPoints(); b.border:SetColorTexture(1, 1, 1, 0)
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.count:SetPoint("BOTTOMRIGHT", -1, 1)
  b.lvl = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  b.lvl:SetPoint("TOPLEFT", 1, -2)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, .25)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function(self)
    if self.item and CanAct(self) then Pick(self.item.bag, self.item.slot) end
  end)
  b:SetScript("OnReceiveDrag", function(self)
    if CanAct(self) then Pick(Target(self)) end
  end)
  b:SetScript("OnEnter", function(self)
    if not (GameTooltip and self.item) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    pcall(GameTooltip.SetHyperlink, GameTooltip, self.item.link)
    if self.item.who then
      for k, n in pairs(self.item.who) do GameTooltip:AddLine(k .. ": " .. n, .8, .8, .8) end
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  -- HookScript, not SetScript: SetScript would replace the secure template's own click handler and the item action would never run
  b:HookScript("OnClick", function(self, button, down)
    if down then return end
    local it = self.item
    if button ~= "RightButton" and it and ns.Mule and ns.Mule.PickClick and ns.Mule.pick and ns.Mule.PickClick(it) then return end
    if it and IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then ChatEdit_InsertLink(it.link) return end
    -- only your own live bags can be handled; saved views are look-only
    if not CanAct(self) then return end
    if button ~= "RightButton" and CursorHasItem and CursorHasItem() then
      Pick(Target(self))                 -- an item is on the cursor: a click still drops it here
    end                                  -- right-click use is the secure item action; picking up is done by dragging
  end)
  buttons[i] = b
  return b
end

-- window height for a number of item rows: header above the grid + footer buttons below it
local HEAD, FOOT, MINROWS, MAXROWS = 96, 58, 3, 13   -- FOOT: buttons row plus a 20 pixel strip of its own for the "-" grabber
-- the "-" grabber at the bottom squeezes the free space between the labels and the items (0 = normal, 1 = tightest);
-- the bag never rolls up and scrolls because of it
local SQ_HDR, SQ_GAP, SQ_ROW = 4, 6, GAP          -- most each gap can shrink: category header, space after a category, space between rows
function Bags.ClampSqueeze(s)
  s = tonumber(s)
  if not s then return 0 end
  return math.max(0, math.min(1, s))
end
function Bags.Squeeze() return Bags.ClampSqueeze(DB and DB.bagSqueeze) end
function Bags.SqueezeSizes(s)                       -- header height, space after a category, row pitch
  s = Bags.ClampSqueeze(s)
  local function cut(v) return math.floor(v * s + 0.5) end
  return HDR - cut(SQ_HDR), SGAP - cut(SQ_GAP), CELL - cut(SQ_ROW)
end
function Bags.SqueezeForHeight(want, full, tight)   -- squeeze that makes content `full` pixels tall come out near `want`
  if not (want and full and tight) or full <= tight then return 0 end
  return Bags.ClampSqueeze(math.floor((full - want) / (full - tight) * 100 + 0.5) / 100)
end
function Bags.FitPx(px)                              -- window height for a content height in pixels
  return Bags.HeadHeight() + FOOT + math.min(MAXROWS * CELL, math.max(MINROWS * CELL, px or 0))
end
function Bags.FitHeight(rows) return Bags.FitPx((rows or 0) * CELL) end

-- the left-edge drawer: one button per character you have played, plus All
local function RefreshDrawer()
  local d = frame.drawer
  local chars = CharList()
  local n = #chars + 1
  for i = 1, math.max(n, #d.btns) do
    local t = d.btns[i]
    if not t then
      t = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
      t:SetSize(DRAWER_W - 12, 22)
      t:SetPoint("TOPRIGHT", d, "TOPRIGHT", -6, -8 - (i - 1) * 24)
      t:SetScript("OnClick", function(self) viewKey = self.key; viewBank = false; drawer.t = 0; Refresh() end)
      d.btns[i] = t
    end
    if i <= n then
      local key = (i <= #chars) and chars[i].key or "ALL"
      t.key = key
      if key == "ALL" then t:SetText("All characters")
      else
        local rec = chars[i].rec
        t:SetText((rec.name or key) .. (rec.total and (" " .. math.max(0, rec.total - (rec.used or 0))) or ""))
      end
      t:Show()
    else t:Hide() end
  end
end

function Refresh()
  if not (frame and frame:IsShown()) then return end
  if InCombat() then Bags.needRefresh = true return end      -- secure cells cannot be changed in combat
  local liveView = (viewKey == nil or viewKey == CharKey()) and not viewBank
  if liveView then Bags.Snapshot() end
  local src, rec = Source()
  local sections, shown
  if sortMode == "category" then
    -- every free slot starts in General; it moves out of there as items take slots
    local free
    if filterText == "" and viewKey ~= "ALL" and rec then
      if liveView then free = LiveEmpties()
      else
        free = {}
        for _ = 1, math.max(0, (viewBank and rec.bankTotal or rec.total or 0) - (viewBank and rec.bankUsed or rec.used or 0)) do free[#free + 1] = {} end
      end
    end
    sections = Bags.Sections(src, filterText, free)
    shown = 0
    for _, s in ipairs(sections) do shown = shown + #s.items end
  elseif sortMode == "separate" and viewKey ~= "ALL" then
    -- one section per bag; the live view lists every slot so a free slot can take a bag dropped on it
    sections = Bags.SeparateSections(src, filterText, liveView and LiveBagList() or nil)
    shown = 0
    for _, s in ipairs(sections) do
      for _, e in ipairs(s.ordered) do if e.item then shown = shown + 1 end end
    end
  else
    local list = Bags.Arrange(src, sortMode == "separate" and "bag" or sortMode, filterText)
    sections, shown = { { items = list } }, #list
  end
  frame.sections = sections
  local qh, qg, qr = Bags.SqueezeSizes(Bags.Squeeze())
  local cells, heads, height = Bags.Layout(sections, COLS, CELL, qh, qg, qr)
  local list = { n = shown }
  frame.heads = frame.heads or {}
  for i = 1, math.max(#heads, #frame.heads) do
    local h, data = frame.heads[i], heads[i]
    if not h then
      h = {}
      h.fs = frame.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      h.line = frame.content:CreateTexture(nil, "ARTWORK")
      h.line:SetColorTexture(RULE_RED[1], RULE_RED[2], RULE_RED[3], RULE_RED[4])
      frame.heads[i] = h
    end
    if data then
      h.fs:ClearAllPoints(); h.fs:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 2, -data.y)
      h.fs:SetText(data.label or ("%s %d"):format(data.name, data.n))
      h.line:ClearAllPoints(); h.line:SetSize(COLS * CELL - GAP, 1)
      h.line:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -(data.y + qh - 3))
      h.fs:Show(); h.line:Show()
    else h.fs:Hide(); h.line:Hide() end
  end
  for i = 1, math.max(#cells, #buttons) do
    local c = cells[i]
    local it = c and c.item
    local b = Cell(i)
    if c then
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", frame.content, "TOPLEFT", c.x, -c.y)
    end
    if c and c.empty then
      b.icon:SetColorTexture(.08, .08, .1, .55)
      b.count:SetText(""); b.lvl:SetText("")
      b.border:SetColorTexture(1, 1, 1, 0)
      b.item, b.eBag, b.eSlot, b.live = nil, c.bag, c.slot, liveView
      Arm(b, nil, false)
      b:Show()
    elseif it then
      b.icon:SetTexture(it.icon or 134400)
      b.count:SetText(it.count > 1 and it.count or "")
      local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[it.q]
      if Bags.Opt("quality") and c and it.q and it.q > 1 then b.border:SetColorTexture(c.r, c.g, c.b, .35) else b.border:SetColorTexture(1, 1, 1, 0) end
      local gear = (it.cls == 2 or it.cls == 4) and it.ilvl and it.ilvl > 1
      b.lvl:SetText((Bags.Opt("ilvl") and gear) and tostring(it.ilvl) or "")
      b.item, b.eBag, b.eSlot, b.live = it, nil, nil, liveView
      Arm(b, it, liveView)
      b:Show()
    else
      b.item = nil; Arm(b, nil, false); b:Hide()
    end
  end
  frame.content:SetHeight(math.max(CELL, height))
  -- no wasted space: the window is only as tall as its items (3 rows least, 13 rows most, then it scrolls)
  frame:SetHeight(Bags.FitPx(height))
  -- header: text size and the rows under it follow the font setting
  local size = Bags.FontSize()
  local hl = Bags.HeaderLayout(size)
  frame.money:SetFont(MONEY_FONT, size + 6, "OUTLINE"); frame.cur:SetFont(FONT_FILE, size, "")
  frame.money:SetTextColor(1, 1, 1)
  frame.name:SetFont(FONT_FILE, size + 5, "OUTLINE")
  frame.handle:ClearAllPoints(); frame.handle:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -hl.handle)
  frame.money:ClearAllPoints(); frame.money:SetPoint("LEFT", frame.handle, "RIGHT", 8, 0)
  frame.cur:ClearAllPoints(); frame.cur:SetPoint("TOPLEFT", 10, -hl.cur)
  frame.headBand:ClearAllPoints()                          -- header band and its gold rule follow the header height
  frame.headBand:SetPoint("TOPLEFT", 3, -3); frame.headBand:SetPoint("TOPRIGHT", -3, -3); frame.headBand:SetHeight(hl.head - 5)
  frame.headHit:SetHeight(hl.head - 5)                     -- the click-to-minimize area follows the header height
  frame.headRule:ClearAllPoints()
  frame.headRule:SetPoint("TOPLEFT", 8, -(hl.head - 3)); frame.headRule:SetPoint("TOPRIGHT", -8, -(hl.head - 3))
  frame.sb:ClearAllPoints()
  frame.sb:SetPoint("TOPLEFT", 10, -hl.head); frame.sb:SetPoint("BOTTOMRIGHT", -10, FOOT)
  -- header
  local nr, ng, nb = 1, .82, 0                              -- gold unless the class colour is known
  if viewKey == "ALL" then
    frame.name:SetText("All characters")
    frame.info:SetText(("%d different items"):format(list.n))
  elseif rec then
    local total = viewBank and rec.bankTotal or rec.total or 0
    local used = viewBank and rec.bankUsed or rec.used or 0
    local when = (liveView and "live") or (date and date("%b %d %H:%M", viewBank and rec.bankTime or rec.time)) or "saved"
    local cc = rec.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[rec.class]
    if type(cc) == "table" and cc.r then nr, ng, nb = cc.r, cc.g, cc.b end
    frame.name:SetText(rec.name or viewKey)
    frame.info:SetText(when)
    frame.free:SetText(Bags.Opt("free") and Bags.FreeText(used, total) or "")
  else
    frame.name:SetText("")
    frame.info:SetText("nothing saved for this character yet")
  end
  frame.name:SetTextColor(nr, ng, nb)
  if viewKey == "ALL" or not rec then frame.free:SetText("") end
  frame.money:SetText((Bags.Opt("money") and rec and viewKey ~= "ALL") and Bags.MoneyText(rec.money) or "")
  frame.cur:SetText((Bags.Opt("currency") and rec and viewKey ~= "ALL") and Bags.CurrencyText(rec.cur, size) or "")
  frame.sortBtn:SetText(SORTS[sortMode])
  frame.bankBtn:SetText(viewBank and "Bank" or "Bags")
  RefreshDrawer()
end

-- the settings panel the gear opens
local function OptionRows()
  local function o(key) return function() return Bags.Opt(key) end, function(v) Bags.SetOpt(key, v) end end
  local rows = {}
  local function add(label, get, set) rows[#rows + 1] = { label = label, get = get, set = set } end
  add("Show free slots", o("free"))
  add("Show gold", o("money"))
  add("Show currencies", o("currency"))
  add("Item level on gear", o("ilvl"))
  add("Colour borders by quality", o("quality"))
  add("Sell grey items at vendors", function() return ns.DB.autoSell end, function(v) ns.DB.autoSell = v and true or false end)
  add("Repair at vendors", function() return ns.DB.autoRepair end, function(v) ns.DB.autoRepair = v and true or false end)
  add("Bag keys open this bag", function() return Bags.On() end, function(v) Bags.Set(v) end)
  return rows
end
Bags.OptionRows = OptionRows

function BuildOptions(f)
  local rows = OptionRows()
  local p = CreateFrame("Frame", "RealmBagsOptions", f, BackdropTemplateMixin and "BackdropTemplate" or nil)
  p:SetSize(220, 14 + #rows * 24 + 34 + 28)
  p:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, 0)
  p:SetFrameStrata("HIGH")
  if ns.UI and ns.UI.Skin then ns.UI.Skin(p) end
  p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  p.title:SetPoint("TOPLEFT", 10, -8); p.title:SetText("Bag settings")
  p.rows = {}
  for i, r in ipairs(rows) do
    local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    cb:SetSize(22, 22); cb:SetPoint("TOPLEFT", 8, -24 - (i - 1) * 24)
    local fs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0); fs:SetText(r.label)
    cb:SetScript("OnClick", function(self) r.set(self:GetChecked() and true or false) end)
    p.rows[i] = { cb = cb, get = r.get }
  end
  local delay = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  delay:SetSize(200, 22); delay:SetPoint("BOTTOMLEFT", 10, 8)
  local function DelayText()
    local d = Bags.Opt("delay")
    delay:SetText(d > 0 and ("Character drawer closes after " .. d .. "s") or "Character drawer stays open")
  end
  delay:SetScript("OnClick", function() Bags.NextDelay(); DelayText() end)
  local fl = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")      -- gold and currency text size: - and + buttons
  fl:SetPoint("BOTTOMLEFT", 12, 40)
  local fminus = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  fminus:SetSize(24, 22); fminus:SetText("-"); fminus:SetPoint("BOTTOMRIGHT", -40, 36)
  local fplus = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  fplus:SetSize(24, 22); fplus:SetText("+"); fplus:SetPoint("LEFT", fminus, "RIGHT", 4, 0)
  local function FontLabel() fl:SetText("Currency text size: " .. Bags.FontSize()) end
  fminus:SetScript("OnClick", function() Bags.StepFont(-1); FontLabel() end)
  fplus:SetScript("OnClick", function() Bags.StepFont(1); FontLabel() end)
  p.fontMinus, p.fontPlus = fminus, fplus
  p:SetScript("OnShow", function()
    for _, r in ipairs(p.rows) do r.cb:SetChecked(r.get() and true or false) end
    FontLabel()
    DelayText()
  end)
  p:Hide()
  return p
end

function Bags.ToggleOptions()
  if not frame then return end
  frame.options = frame.options or BuildOptions(frame)
  if frame.options:IsShown() then frame.options:Hide() else frame.options:Show() end
end

local function Build()
  local f = CreateFrame("Frame", "RealmBags", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(COLS * CELL + 34, 470)
  local pos = DB.bagPos
  if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("RIGHT", UIParent, "RIGHT", -60, 0) end
  f:SetScale(Bags.ClampScale(DB.bagScale or 1))
  f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) if not DB.bagLocked then self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SaveFramePos(self) end)
  f:SetFrameStrata("HIGH")
  if ns.UI and ns.UI.Skin then ns.UI.Skin(f) end
  if f.SetBackdropColor then                                -- dark navy, slightly see-through, with a thin red-brown border
    f:SetBackdropColor(NAVY[1], NAVY[2], NAVY[3], NAVY[4])
    f:SetBackdropBorderColor(EDGE_RED[1], EDGE_RED[2], EDGE_RED[3], EDGE_RED[4])
  end
  f.leather = f:CreateTexture(nil, "BACKGROUND")           -- faint navy tint over the panel
  f.leather:SetPoint("TOPLEFT", 3, -3); f.leather:SetPoint("BOTTOMRIGHT", -3, 3)
  f.leather:SetColorTexture(.05, .08, .18, .30)
  f.headBand = f:CreateTexture(nil, "BORDER")             -- header: darker band holding title, free slots, Alts, gold and the icon cluster
  f.headBand:SetColorTexture(0, 0, 0, .20)
  f.headRule = f:CreateTexture(nil, "ARTWORK")
  f.headRule:SetHeight(1); f.headRule:SetColorTexture(EDGE_RED[1], EDGE_RED[2], EDGE_RED[3], .8)
  f.footBand = f:CreateTexture(nil, "BORDER")             -- footer: matching band holding sort, bank, clean up, search and the grabber
  f.footBand:SetPoint("BOTTOMLEFT", 3, 3); f.footBand:SetPoint("BOTTOMRIGHT", -3, 3); f.footBand:SetHeight(FOOT - 5)
  f.footBand:SetColorTexture(0, 0, 0, .20)
  f.footRule = f:CreateTexture(nil, "ARTWORK")
  f.footRule:SetHeight(1); f.footRule:SetColorTexture(EDGE_RED[1], EDGE_RED[2], EDGE_RED[3], .8)
  f.footRule:SetPoint("BOTTOMLEFT", 8, FOOT - 3); f.footRule:SetPoint("BOTTOMRIGHT", -8, FOOT - 3)
  f.headHit = CreateFrame("Button", nil, f)                -- the blank header area: double-click it to fold into the pouch, drag it to move
  f.headHit:SetFrameLevel(f:GetFrameLevel() + 1)           -- under the header buttons: every header button below is raised to level +6
  f.headHit:SetPoint("TOPLEFT", 3, -3); f.headHit:SetPoint("TOPRIGHT", -3, -3); f.headHit:SetHeight(Bags.HeadHeight() - 5)
  f.headHit:RegisterForClicks("LeftButtonUp"); f.headHit:RegisterForDrag("LeftButton")
  f.headHit:SetScript("OnDragStart", function(self) self.dragged = true; if not DB.bagLocked then f:StartMoving() end end)
  f.headHit:SetScript("OnDragStop", function(self) f:StopMovingOrSizing(); SaveFramePos(f) end)
  f.headHit:SetScript("OnClick", function(self)
    self.dragged = false
  end)
  f.headHit:SetScript("OnDoubleClick", function(self)
    if self.dragged then self.dragged = false; return end
    Bags.Minimize()
  end)
  f.headHit:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine("Double-click to fold into the pouch"); GameTooltip:Show()
  end)
  f.headHit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetFont(FONT_FILE, 11, ""); f.title:SetTextColor(1, .82, 0)     -- small yellow title, top left
  f.title:SetPoint("TOPLEFT", 10, -7); f.title:SetText("Realm Bags")
  f.free = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.free:SetPoint("BOTTOMLEFT", 12, 33)                    -- footer, upper row, left end (the search box sits at the right end)
  local HL = f:GetFrameLevel() + 6                         -- header buttons sit above the fold area
  local mini = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  mini:SetSize(22, 20); mini:SetText("_")
  mini:SetPoint("TOPRIGHT", -34, -6)
  mini:SetFrameLevel(HL)
  if ns.UI and ns.UI.Modern then ns.UI.Modern(mini) end
  mini:SetScript("OnClick", function() Bags.Minimize() end)
  mini:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine("Fold into the pouch"); GameTooltip:Show()
  end)
  mini:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  local gear = CreateFrame("Button", nil, f)               -- settings, hidden behind the gear
  gear:SetSize(20, 20); gear:SetPoint("TOPRIGHT", -60, -7)
  gear:SetFrameLevel(HL)
  gear.tex = gear:CreateTexture(nil, "ARTWORK"); gear.tex:SetAllPoints()
  gear.tex:SetTexture("Interface\\Buttons\\UI-OptionsButton")
  gear:SetScript("OnClick", function() Bags.ToggleOptions() end)
  gear:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine("Bag settings"); GameTooltip:Show()
  end)
  gear:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  local lock = CreateFrame("Button", nil, f)               -- padlock: locked = no moving, no scaling
  lock:SetSize(18, 18); lock:SetPoint("TOPRIGHT", -84, -8)
  lock:SetFrameLevel(HL)
  f.lockTex = lock:CreateTexture(nil, "ARTWORK"); f.lockTex:SetAllPoints()
  f.lockTex:SetTexture(DB.bagLocked and "Interface\\Buttons\\LockButton-Locked-Up" or "Interface\\Buttons\\LockButton-Unlocked-Up")
  lock:SetScript("OnClick", function() Bags.SetLocked(not DB.bagLocked) end)
  lock:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(DB.bagLocked and "Locked. Click to unlock." or "Unlocked. Click to lock.")
    GameTooltip:Show()
  end)
  lock:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  f.lock = lock

  local grip = CreateFrame("Button", nil, f)               -- bottom-right corner: drag to scale the whole bag
  grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetFrameLevel(f:GetFrameLevel() + 10)
  grip:SetScript("OnMouseDown", function()
    if DB.bagLocked then return end
    local s = f:GetScale() or 1
    local l, t = f:GetLeft(), f:GetTop()
    if not (l and t) then return end
    f:ClearAllPoints()                                     -- pin the top-left corner so the bag grows from it
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l * s, t * s)
    grip.sizing = { l = l * s, t = t * s }
  end)
  grip:SetScript("OnUpdate", function()
    local g = grip.sizing
    if not g or not GetCursorPosition then return end
    local cx = GetCursorPosition() / (UIParent:GetEffectiveScale() or 1)
    local s = Bags.ScaleForWidth(cx - g.l, f:GetWidth())
    f:SetScale(s)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", g.l / s, g.t / s)
  end)
  grip:SetScript("OnMouseUp", function()
    if not grip.sizing then return end
    grip.sizing = nil
    DB.bagScale = f:GetScale()
    SaveFramePos(f)
  end)
  grip:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine("Drag to scale"); GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  f.grip = grip
  if DB.bagLocked then grip:Hide() end

  local sq = CreateFrame("Button", nil, f)                 -- a bar on the bottom edge: drag up to shorten the bag, right-click to reset
  sq:SetHeight(18)                                         -- its own strip along the bottom edge, below the buttons and clear of the scale grip
  sq:SetPoint("BOTTOMLEFT", 6, 3); sq:SetPoint("BOTTOMRIGHT", -22, 3)
  sq:SetFrameLevel(f:GetFrameLevel() + 10)
  sq.strip = sq:CreateTexture(nil, "BACKGROUND")
  sq.strip:SetAllPoints(); sq.strip:SetColorTexture(0, 0, 0, .25)
  sq.bar = sq:CreateTexture(nil, "OVERLAY")
  sq.bar:SetSize(60, 2); sq.bar:SetPoint("CENTER")       -- a thin yellow bar
  sq.bar:SetColorTexture(1, .82, 0, .9)
  sq:SetScript("OnMouseDown", function(_, btn)
    if btn == "RightButton" or DB.bagLocked then return end
    local s = f:GetScale() or 1
    local l, t = f:GetLeft(), f:GetTop()
    if not (l and t) then return end
    f:ClearAllPoints()                                     -- pin the top-left corner so only the bottom edge moves
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)    -- GetLeft/GetTop are already in the bag's own scale: no multiplying, or the bag jumps
    sq.sizing = { top = t * s }
  end)
  sq:SetScript("OnUpdate", function()
    local g = sq.sizing
    if not g or not GetCursorPosition then return end
    local _, cy = GetCursorPosition()
    local h = (g.top - cy / (UIParent:GetEffectiveScale() or 1)) / (f:GetScale() or 1)
    local secs = f.sections
    if not secs then return end
    -- content height the cursor asks for, against the loosest and tightest layouts of what is in the bag now
    local function tall(s) local a, b, c = Bags.SqueezeSizes(s); local _, _, ht = Bags.Layout(secs, COLS, CELL, a, b, c); return ht end
    local s = Bags.SqueezeForHeight(h - Bags.HeadHeight() - FOOT, tall(0), tall(1))
    if s ~= Bags.Squeeze() then DB.bagSqueeze = s; Refresh() end
  end)
  sq:SetScript("OnMouseUp", function(_, btn)
    if btn == "RightButton" then
      if not DB.bagLocked then DB.bagSqueeze = nil; Refresh() end
      return
    end
    if not sq.sizing then return end
    sq.sizing = nil
    SaveFramePos(f)
  end)
  sq:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Drag up to squeeze the space between items")
    GameTooltip:AddLine("Drag down to loosen it, right-click to reset", .8, .8, .8)
    GameTooltip:Show()
  end)
  sq:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  f.squeeze = sq
  if DB.bagLocked then sq:Hide() end

  f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")      -- the character's name, big and in their class colour
  f.name:SetPoint("TOPLEFT", 10, -20)
  f.info = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")  -- small grey note beside it ("live", or when it was saved)
  f.info:SetPoint("BOTTOMLEFT", f.name, "BOTTOMRIGHT", 8, 2)
  f.cur = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.cur:SetPoint("TOPLEFT", 10, -56)
  f.money = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")     -- gold, silver, copper on their own line
  f.money:SetPoint("TOPLEFT", 10, -42)
  local close = CreateFrame("Button", nil, f)                        -- flat close button instead of the red template X
  close:SetSize(22, 22); close:SetPoint("TOPRIGHT", -8, -5)
  close:SetFrameLevel(HL)
  if ns.UI and ns.UI.Button then ns.UI.Button(close) end
  close.l = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); close.l:SetPoint("CENTER"); close.l:SetText("x")
  close:SetScript("OnClick", function() f:Hide() end)

  -- character drawer: a handle on the left edge slides the list out; it slides back after the delay or on minimize
  local handle = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")   -- the "<-Alts" button under the currencies
  handle:SetSize(64, 18)
  handle:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -Bags.HeaderLayout(Bags.FontSize()).handle)
  handle:SetText("<-Alts")
  handle:SetFrameLevel(HL)
  if ns.UI and ns.UI.Modern then ns.UI.Modern(handle) end
  -- the shared Send list (the same list the EMF mail window shows)
  local sendBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  sendBtn:SetSize(96, 18)
  sendBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -Bags.HeaderLayout(Bags.FontSize()).handle)
  sendBtn:SetText("Send list")
  sendBtn:SetFrameLevel(HL)
  if ns.UI and ns.UI.Modern then ns.UI.Modern(sendBtn) end
  if ns.Mule and ns.Mule.RegisterListButton then ns.Mule.RegisterListButton(sendBtn) else sendBtn:Hide() end
  sendBtn:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Send list"); GameTooltip:AddLine("Choose which items may be mailed to your AH alt.", 1, 1, 1, true); GameTooltip:Show()
  end)
  sendBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  f.sendBtn = sendBtn
  local d = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
  d:SetPoint("TOPRIGHT", f, "TOPLEFT", -18, 0)
  d:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", -18, 0)
  d:SetWidth(1)
  if d.SetClipsChildren then d:SetClipsChildren(true) end
  if ns.UI and ns.UI.Skin then ns.UI.Skin(d) end
  if d.SetBackdropColor then
    d:SetBackdropColor(NAVY[1], NAVY[2], NAVY[3], NAVY[4])
    d:SetBackdropBorderColor(EDGE_RED[1], EDGE_RED[2], EDGE_RED[3], EDGE_RED[4])
  end
  d.btns = {}
  d:Hide()
  f.handle, f.drawer = handle, d
  handle:SetScript("OnClick", function()
    drawer.open = not drawer.open; drawer.t = 0
  end)
  handle:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine("Your characters' bags"); GameTooltip:Show()
  end)
  handle:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  f:SetScript("OnUpdate", function(_, dt)
    if drawer.w <= 0 and not drawer.open then return end
    Bags.DrawerStep(drawer, dt, d:IsMouseOver() or handle:IsMouseOver(), Bags.Opt("delay"), DRAWER_W)
    d:SetWidth(math.max(1, drawer.w))
    if drawer.w > 0 then d:Show() else d:Hide() end
  end)
  f:SetScript("OnHide", function()
    drawer.open, drawer.w, drawer.t = false, 0, 0
    d:SetWidth(1); d:Hide()
    if f.options then f.options:Hide() end
  end)

  local sb = CreateFrame("ScrollFrame", nil, f)
  f.sb = sb
  sb:SetPoint("TOPLEFT", 10, -Bags.HeadHeight()); sb:SetPoint("BOTTOMRIGHT", -10, FOOT)
  local content = CreateFrame("Frame", nil, sb)
  content:SetSize(COLS * CELL, 100)
  sb:SetScrollChild(content)
  sb:EnableMouseWheel(true)
  sb:SetScript("OnMouseWheel", function(self, d)
    local cur = self:GetVerticalScroll()
    local max = math.max(0, content:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.min(max, math.max(0, cur - d * CELL * 2)))
  end)
  f.content = content

  local sortBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  sortBtn:SetSize(86, 22); sortBtn:SetPoint("BOTTOMLEFT", 10, 3)
  sortBtn:SetScript("OnClick", function()
    for i, k in ipairs(SORT_ORDER) do
      if k == sortMode then sortMode = SORT_ORDER[i % #SORT_ORDER + 1]; break end
    end
    DB.bagSort = sortMode
    Refresh()
  end)
  f.sortBtn = sortBtn

  local bankBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  bankBtn:SetSize(56, 22); bankBtn:SetPoint("BOTTOMRIGHT", -23, 3)
  bankBtn:SetScript("OnClick", function()
    if viewKey == "ALL" then return end
    viewBank = not viewBank; Refresh()
  end)
  f.bankBtn = bankBtn

  local clean = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  clean:SetSize(80, 22); clean:SetPoint("RIGHT", bankBtn, "LEFT", -4, 0)
  clean:SetText("Clean up")
  clean:SetScript("OnClick", function()
    if InCombatLockdown and InCombatLockdown() then Print("not in combat.") return end
    local fn = (CC and CC.SortBags) or SortBags
    if fn then pcall(fn) end
    C_Timer.After(1.2, Refresh)
  end)

  local dropBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  dropBtn:SetSize(40, 22); dropBtn:SetPoint("LEFT", sortBtn, "RIGHT", 4, 0)
  dropBtn:SetScript("OnClick", function() Bags.SetDrop(not Bags.DropOn()) end)
  dropBtn:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Drop " .. (Bags.DropOn() and "|cff66ff66(on)|r" or "|cffaaaaaa(off)|r"))
    GameTooltip:AddLine(Bags.DROP_HELP, 1, 1, 1, true)
    GameTooltip:AddLine("The game only lets a click delete items, so a Delete button appears: one click destroys the item and loots again. Only grey items and white armor or weapons are offered. Uncommon and better, profession items, consumables, quest and unsellable items are never touched.", .7, .7, .7, true)
    GameTooltip:Show()
  end)
  dropBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  f.dropBtn = dropBtn
  PaintDrop()
  -- the "-" grabber now shares the button row: it fills only the gap between Drop and Clean up, so it never covers a button
  local sqz = f.squeeze
  sqz:ClearAllPoints()
  sqz:SetPoint("BOTTOMLEFT", dropBtn, "BOTTOMRIGHT", 6, 0)
  sqz:SetPoint("BOTTOMRIGHT", clean, "BOTTOMLEFT", -6, 0)
  sqz:SetHeight(22)

  local sbox = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)   -- dark box with a red-brown border, the footer's right end
  sbox:SetSize(126, 20); sbox:SetPoint("BOTTOMRIGHT", -12, 29)
  if sbox.SetBackdrop then
    sbox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    sbox:SetBackdropColor(.02, .03, .07, .95)
    sbox:SetBackdropBorderColor(EDGE_RED[1], EDGE_RED[2], EDGE_RED[3], EDGE_RED[4])
  end
  local eb = CreateFrame("EditBox", nil, sbox)                           -- minimize lives in the header only
  eb:SetPoint("TOPLEFT", 5, -1); eb:SetPoint("BOTTOMRIGHT", -5, 1); eb:SetAutoFocus(false)
  if eb.SetFontObject and _G.GameFontHighlightSmall then eb:SetFontObject(_G.GameFontHighlightSmall) end
  eb.hint = eb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")  -- faint "search" label while the box is empty
  eb.hint:SetPoint("LEFT", 0, 0); eb.hint:SetText("search")
  eb:SetScript("OnTextChanged", function(self)
    filterText = self:GetText() or ""
    if filterText == "" then self.hint:Show() else self.hint:Hide() end
    Refresh()
  end)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  f.search = eb
  f:SetScript("OnShow", function() Refresh() end)
  f:Hide()
  return f
end

function Bags.Show(key)
  if not DB then return end
  frame = frame or Build()
  if key then viewKey = key; viewBank = false end
  DB.bagMin = false; UpdatePouch()
  frame:Show(); Refresh()
end
function Bags.Hide() if frame then frame:Hide() end end
function Bags.Toggle()
  if not DB then return end
  frame = frame or Build()
  if frame:IsShown() then Bags.Minimize() else viewKey = nil; viewBank = false; Bags.Show() end   -- B again folds back to the pouch, never leaves nothing on screen
end

-- ------------------------------------------------------------ one-bag takeover
function Bags.On() return DB and DB.oneBag and true or false end
function Bags.Set(v)
  DB.oneBag = v and true or false
  Print("one bag: " .. (DB.oneBag and "ON. Your bag keys now open the Realm bag." or "off. The normal bags are back."))
end

local function HideDefaults()
  if InCombatLockdown and InCombatLockdown() then return end
  for i = 1, 13 do
    local f = _G["ContainerFrame" .. i]
    if f and f.Hide then pcall(f.Hide, f) end
  end
  if _G.ContainerFrameCombinedBags and ContainerFrameCombinedBags.Hide then pcall(ContainerFrameCombinedBags.Hide, ContainerFrameCombinedBags) end
end

local function HookKeys()
  local function opener() if Bags.On() then Bags.Show(); C_Timer.After(0, HideDefaults) end end
  local function closer() if Bags.On() then Bags.Hide() end end
  local function toggler()
    if not Bags.On() then return end
    HideDefaults()
    Bags.Toggle()
  end
  for _, n in ipairs({ "OpenAllBags", "OpenBackpack" }) do if _G[n] then pcall(hooksecurefunc, n, opener) end end
  for _, n in ipairs({ "CloseAllBags", "CloseBackpack" }) do if _G[n] then pcall(hooksecurefunc, n, closer) end end
  for _, n in ipairs({ "ToggleAllBags", "ToggleBackpack" }) do if _G[n] then pcall(hooksecurefunc, n, toggler) end end
end

-- ------------------------------------------------------------ commands + events
function Bags.Command(arg)
  arg = (arg or ""):lower()
  local sub, rest = arg:match("^(%S*)%s*(.-)$")
  if sub == "on" then Bags.Set(true)
  elseif sub == "off" then Bags.Set(false)
  elseif sub == "sort" then
    if SORTS[rest] then sortMode = rest; DB.bagSort = rest; Refresh(); Print("sorted by " .. SORTS[rest])
    else Print("sort modes: category, separate, bag, type, quality, name, value") end
  elseif sub == "lock" then Bags.SetLocked(true); Print("bag locked.")
  elseif sub == "unlock" then Bags.SetLocked(false); Print("bag unlocked.")
  elseif sub == "scale" then
    local n = tonumber(rest)
    if n then Bags.SetScaleValue(n); Print("bag scale: " .. DB.bagScale) else Print("usage: /realm bags scale 0.6 - 2") end
  elseif sub == "fontsize" then
    local n = tonumber(rest)
    if n then Bags.SetOpt("fontSize", Bags.ClampFont(n)); Print("currency text size: " .. Bags.FontSize()) else Print("usage: /realm bags fontsize 9-20") end
  elseif sub == "squeeze" then
    local n = tonumber(rest)
    if n then DB.bagSqueeze = Bags.ClampSqueeze(n / 100); Refresh(); Print("bag squeeze: " .. math.floor(Bags.Squeeze() * 100 + 0.5) .. "%")
    elseif rest == "off" then DB.bagSqueeze = nil; Refresh(); Print("bag squeeze: off")
    else Print("usage: /realm bags squeeze 0-100 | off") end
  elseif sub == "drop" then
    if rest == "on" or rest == "off" then Bags.SetDrop(rest == "on")
    elseif rest == "debug on" or rest == "debug off" then
      DB.bagDropDebug = (rest == "debug on") or nil
      Print("drop debug: " .. (DB.bagDropDebug and "ON. Loot events and the reason for every skipped drop are printed." or "off."))
    else Print("drop is " .. (Bags.DropOn() and "ON" or "off") .. ". " .. DROP_HELP .. " Use /realm bags drop on|off, or drop debug on|off.") end
  elseif sub == "forget" then
    local key = rest ~= "" and rest or nil
    for k in pairs(DB.bags) do if key and k:lower():find(key, 1, true) and k ~= CharKey() then DB.bags[k] = nil; Print("forgot " .. k) end end
  elseif sub == "who" then
    local n = 0
    for key, rec in pairs(DB.bags) do
      n = n + 1
      Print(("%s: %d item stack(s), %d/%d slots, saved %s"):format(key, rec.items and #rec.items or 0, rec.used or 0, rec.total or 0,
        rec.time and date and date("%m-%d %H:%M", rec.time) or "never"))
    end
    if n == 0 then Print("no characters saved yet.") end
  elseif sub == "help" then
    Print("/realm bags (open) | on | off | who | sort category|separate|bag|type|quality|name|value | lock | unlock | scale 0.6-2 | fontsize 9-20 | squeeze 0-100|off | drop on|off | forget <character>")
  else Bags.Toggle() end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LOGOUT")
for _, e in ipairs({ "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYER_MONEY", "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED", "UI_ERROR_MESSAGE", "PLAYER_REGEN_ENABLED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }) do pcall(ev.RegisterEvent, ev, e) end
local pending
-- auto-loot can leave items behind with no error text we recognise: a short while after the window opens, if loot is
-- still waiting and there is no free slot, treat it as a full-bag loot
local function CheckStuckLoot()
  if not (DB and Bags.DropOn() and lootOpen) then return end
  local n = (GetNumLootItems and GetNumLootItems()) or 0
  if n == 0 then return end
  if #LiveEmpties() > 0 then Dbg("loot still open but bags have free slots, leaving it"); return end
  local auto = GetCVarBool and GetCVarBool("autoLootDefault")
  if IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE") then auto = not auto end
  if not auto then Dbg("loot open, bags full, but auto-loot is off: waiting for the full-bag error"); return end
  Bags.TryDrop("loot stayed open with no free slot")
end
Bags.CheckStuck = CheckStuckLoot
ev:SetScript("OnEvent", function(_, e, a1, a2)
  if e == "LOOT_READY" then lootStamp = Now(); return
  elseif e == "LOOT_OPENED" then
    lootOpen, dropBusy, drops, lootStamp = true, false, 0, Now()
    HideDelete()                                   -- an offer left from an earlier window is stale
    Dbg("loot opened")
    if C_Timer and DB and Bags.DropOn() then C_Timer.After(0.6, CheckStuckLoot) end
    return
  elseif e == "LOOT_CLOSED" then lootOpen, dropBusy, lootStamp = false, false, Now(); Dbg("loot closed"); return
  elseif e == "UI_ERROR_MESSAGE" then
    local msg = (type(a2) == "string" and a2) or (type(a1) == "string" and a1) or nil   -- (errorType, message) in current clients
    if DB and DB.bagDropDebug and msg and LootActive() then Dbg("error text while looting: '" .. msg .. "'") end
    if DB and IsFullMsg(msg) then Bags.TryDrop("full-bag error") end
    return
  elseif e == "PLAYER_REGEN_ENABLED" then
    if wantDrop then
      local why = wantDrop
      wantDrop = nil
      if DB and Bags.DropOn() and C_Timer then C_Timer.After(0.5, function() Bags.TryDrop("combat ended after: " .. tostring(why), true) end) end
    end
    if Bags.needRefresh then Bags.needRefresh = false; if frame and frame:IsShown() then Refresh() end end
    return
  elseif e == "UNIT_SPELLCAST_CHANNEL_START" or e == "UNIT_SPELLCAST_CHANNEL_STOP" then
    if a1 == "player" then
      castStamp = Now()
      if e == "UNIT_SPELLCAST_CHANNEL_START" then drops = 0 end   -- a new channel gets a fresh allowance, like a new loot window
    end
    return
  end
  if e == "PLAYER_LOGIN" then
    DB = ns.DB
    DB.bags = DB.bags or {}
    if DB.oneBag == nil then DB.oneBag = false end
    sortMode = DB.bagSort or "category"
    HookKeys()
    DB.bagMin = true            -- every login starts minimized: the pouch is there at once, no B press needed
    UpdatePouch()
    C_Timer.After(3, function() Bags.Snapshot(); UpdatePouch() end)
  elseif not DB then return
  elseif e == "PLAYER_LOGOUT" then
    Bags.Snapshot(true)
  elseif e == "BANKFRAME_OPENED" then
    bankOpen = true
    C_Timer.After(0.5, function() Bags.Snapshot() end)
  elseif e == "BANKFRAME_CLOSED" then
    Bags.Snapshot(); bankOpen = false
  else
    if pending then return end
    pending = true
    C_Timer.After(0.5, function()
      pending = false
      Bags.Snapshot()
      if frame and frame:IsShown() then Refresh() end
    end)
  end
end)
