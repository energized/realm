-- Realm Post: a running POST list for your auction house alt.
-- Learning: every item you post by hand is added to the list, with the duration and stack size you used. Items on the
-- list that are in your bags can then be posted with one click each, priced a few percent under the lowest price the
-- Exchange scan last saw. Items you remove stay off the list until you post them by hand again.
-- The game only lets an addon post when you click, so each click posts one stack. Never posts below the floor
-- (the item's vendor price, or a floor you set), never posts an item that is not on the list, never lists soulbound items.
local ADDON, ns = ...
local Post = {}
ns.Post = Post

local DB
local MAX_QUOTE_AGE = 3 * 86400    -- ignore Exchange prices older than this
local DEFAULT_UNDER = 5            -- percent under the lowest listing
local DEFAULT_DUR = 3              -- 1 = 12 h, 2 = 24 h, 3 = 48 h
local DUR_TEXT = { "12h", "24h", "48h" }
local selfPosting = false

local function Print(m) if ns.Print then ns.Print("Post: " .. m) end end

-- ------------------------------------------------------------ prices (pure, unit tested)
-- the price to list one item at, or nil and the reason
function Post.Price(lowest, under, floor)
  if not lowest or lowest <= 0 then return nil, "no price data: scan the auction house first" end
  under = under or DEFAULT_UNDER
  local price = math.floor(lowest * (100 - under) / 100)
  if price < 1 then return nil, "price would be zero" end
  if floor and floor > 0 and price < floor then return nil, "market is below your floor" end
  return price
end

local function VendorPrice(id)
  if not GetItemInfo then return 0 end
  local ok, _, _, _, _, _, _, _, _, _, _, p = pcall(GetItemInfo, id)
  return (ok and tonumber(p)) or 0
end

local function NameOf(id)
  local n = GetItemInfo and select(1, GetItemInfo(id))
  return n or ("item " .. tostring(id))
end

function Post.Quote(id)
  local e = DB and DB.postList and DB.postList[id]
  if not e then return nil, "not on the list" end
  local lowest, seen = nil, nil
  if ns.Exchange and ns.Exchange.Lowest then lowest, seen = ns.Exchange.Lowest(id) end
  if lowest and seen and time() - seen > MAX_QUOTE_AGE then return nil, "price data is old: rescan" end
  return Post.Price(lowest, DB.postUnder, math.max(e.floor or 0, VendorPrice(id)))
end

-- ------------------------------------------------------------ learning
-- called for every manual post (and by the tests); returns true when the item is new to the list
function Post.Learn(id, name, dur, stack, unit)
  if not (DB and id) or DB.postLearn == false then return false end
  local e = DB.postList[id]
  local new = e == nil
  e = e or { n = 0 }
  e.name = name or e.name or NameOf(id)
  e.dur = dur or e.dur or DEFAULT_DUR
  if stack and stack > 0 then e.stack = stack end
  if unit and unit > 0 then e.last = unit end
  e.n = e.n + 1
  e.t = time()
  DB.postList[id] = e
  -- track it in the Exchange so scans keep its price fresh
  if DB.exWatch and not (DB.exIgnore and DB.exIgnore[id]) then DB.exWatch[id] = true end
  if new then Print((e.name or "item") .. " added to the POST list.") end
  if Post.RefreshUI then Post.RefreshUI() end
  return new
end

function Post.Remove(id)
  if not (DB and DB.postList[id]) then return false end
  DB.postList[id] = nil
  if Post.RefreshUI then Post.RefreshUI() end
  return true
end

local function IdFromLocation(loc)
  if not (loc and C_Item and C_Item.GetItemID) then return nil end
  local ok, id = pcall(C_Item.GetItemID, loc)
  return ok and id or nil
end

function Post.OnPostCommodity(loc, dur, qty, unit)
  if selfPosting then return end
  local id = IdFromLocation(loc)
  if id then Post.Learn(id, nil, dur, qty, unit) end
end

function Post.OnPostItem(loc, dur, qty, bid, buyout)
  if selfPosting then return end
  local id = IdFromLocation(loc)
  if not id then return end
  local unit = (buyout and qty and qty > 0) and math.floor(buyout / qty) or nil
  Post.Learn(id, nil, dur, qty, unit)
end

-- ------------------------------------------------------------ what is in the bags
function Post.Candidates()
  local out = {}
  if not (DB and next(DB.postList)) then return out end
  local CC = C_Container
  local numSlots = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
  if not numSlots then return out end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, (numSlots(bag) or 0) do
      local id, count, locked, bound
      if CC and CC.GetContainerItemInfo then
        local i = CC.GetContainerItemInfo(bag, slot)
        if i then id, count, locked, bound = i.itemID, i.stackCount, i.isLocked, i.isBound end
      elseif GetContainerItemInfo then
        local _, c, l, _, _, _, link, _, _, itemId, b = GetContainerItemInfo(bag, slot)
        id, count, locked, bound = itemId or (link and tonumber(link:match("item:(%d+)"))), c, l, b
      end
      local e = id and DB.postList[id]
      if e and not locked and not bound then
        out[#out + 1] = { id = id, bag = bag, slot = slot, count = count or 1, entry = e, name = e.name or NameOf(id) }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.count > b.count
  end)
  return out
end

-- ------------------------------------------------------------ posting (must run inside a click)
local function AHOpen()
  return (AuctionHouseFrame and AuctionHouseFrame:IsShown()) or (AuctionFrame and AuctionFrame:IsShown())
end

function Post.PostOne(c)
  if not AHOpen() then return false, "open the auction house first" end
  local price, why = Post.Quote(c.id)
  if not price then return false, why end
  local AH = C_AuctionHouse
  if not (AH and AH.PostItem and ItemLocation) then
    return false, "this client has no C_AuctionHouse posting API; post by hand"
  end
  local loc = ItemLocation:CreateFromBagAndSlot(c.bag, c.slot)
  local dur = c.entry.dur or DEFAULT_DUR
  local stack = math.max(1, math.min(c.count, c.entry.stack or c.count))
  local status = AH.GetItemCommodityStatus and AH.GetItemCommodityStatus(loc) or 0
  selfPosting = true
  local ok, err
  if status == 2 and AH.PostCommodity then
    ok, err = pcall(AH.PostCommodity, loc, dur, stack, price)
  else
    ok, err = pcall(AH.PostItem, loc, dur, stack, nil, price * stack)
  end
  selfPosting = false
  if not ok then return false, tostring(err) end
  c.entry.n = (c.entry.n or 0) + 1
  c.entry.t = time()
  c.entry.last = price
  return true, ("%s x%d at %s each, %s"):format(c.name, stack, ns.Coin(price), DUR_TEXT[dur] or "?")
end

function Post.Next()
  local list = Post.Candidates()
  if #list == 0 then Print("nothing from the POST list is in your bags.") return false end
  local firstWhy
  for _, c in ipairs(list) do
    local ok, msg = Post.PostOne(c)
    if ok then Print("posted " .. msg); if Post.RefreshUI then Post.RefreshUI() end return true end
    firstWhy = firstWhy or (c.name .. ": " .. tostring(msg))
    if msg and msg:find("open the auction house", 1, true) then break end
  end
  Print("could not post: " .. tostring(firstWhy))
  return false
end

-- ------------------------------------------------------------ window
local win, rowsUI, ROWS, off = nil, {}, 10, 0
local ahButton

local function SortedIds()
  local ids = {}
  for id in pairs(DB.postList or {}) do ids[#ids + 1] = id end
  table.sort(ids, function(a, b)
    return tostring(DB.postList[a].name or a):lower() < tostring(DB.postList[b].name or b):lower()
  end)
  return ids
end

function Post.RefreshUI()
  if not (win and DB) then return end
  if ahButton then ahButton:SetText(("POST list (%d)"):format(#SortedIds())) end
  if not win:IsShown() then return end
  local ids = SortedIds()
  local have = {}
  local cands = Post.Candidates()
  for _, c in ipairs(cands) do have[c.id] = (have[c.id] or 0) + c.count end
  off = math.max(0, math.min(off, #ids - ROWS))
  for i = 1, ROWS do
    local r, id = rowsUI[i], ids[off + i]
    if id then
      local e = DB.postList[id]
      local price, why = Post.Quote(id)
      r.id = id
      r.text:SetText(("%s |cff888888x%d|r  %s"):format(e.name or id, have[id] or 0,
        price and ns.Coin(price) or ("|cff888888" .. (why or "?") .. "|r")))
      if have[id] and price then r.post:Enable() else r.post:Disable() end
      r:Show()
    else
      r.id = false; r:Hide()
    end
  end
  win.empty:SetText(#ids == 0 and "Empty. Post an item by hand and Realm learns it." or "")
  win.next:SetText(("Post next (%d)"):format(#cands))
  win.learn:SetText("Learn: " .. (DB.postLearn == false and "off" or "ON"))
  win.under:SetText(("Undercut %d%%"):format(DB.postUnder or DEFAULT_UNDER))
end

local function Build()
  local f = CreateFrame("Frame", "RealmPostWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(330, 110 + ROWS * 20)
  f:SetPoint("CENTER", 0, 0)
  f:SetFrameStrata("HIGH"); f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if ns.UI and ns.UI.Skin then ns.UI.Skin(f) end
  local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("TOPLEFT", 10, -9); t:SetText("POST list")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() f:Hide() end)
  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 10, -30); hint:SetWidth(310); hint:SetJustifyH("LEFT")
  hint:SetText("Items you post by hand are added. One click posts one stack under the lowest price.")
  f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.empty:SetPoint("TOPLEFT", 10, -66); f.empty:SetWidth(310); f.empty:SetJustifyH("LEFT")
  for i = 1, ROWS do
    local r = CreateFrame("Frame", nil, f)
    r:SetSize(310, 20); r:SetPoint("TOPLEFT", 10, -52 - (i - 1) * 20)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 0, 0); r.text:SetWidth(200); r.text:SetJustifyH("LEFT")
    r.del = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.del:SetSize(24, 18); r.del:SetText("X"); r.del:SetPoint("RIGHT", 0, 0)
    r.post = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.post:SetSize(50, 18); r.post:SetText("Post"); r.post:SetPoint("RIGHT", r.del, "LEFT", -4, 0)
    r.id = false
    r.del:SetScript("OnClick", function() if r.id then Post.Remove(r.id) end end)
    r.post:SetScript("OnClick", function()
      if not r.id then return end
      for _, c in ipairs(Post.Candidates()) do
        if c.id == r.id then
          local ok, msg = Post.PostOne(c)
          Print(ok and ("posted " .. msg) or ("could not post: " .. tostring(msg)))
          Post.RefreshUI()
          return
        end
      end
      Print("that item is not in your bags.")
    end)
    rowsUI[i] = r
  end
  f.next = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.next:SetSize(110, 22); f.next:SetPoint("BOTTOMLEFT", 10, 10)
  f.next:SetScript("OnClick", Post.Next)
  f.learn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.learn:SetSize(90, 22); f.learn:SetPoint("LEFT", f.next, "RIGHT", 6, 0)
  f.learn:SetScript("OnClick", function() DB.postLearn = (DB.postLearn == false); Post.RefreshUI() end)
  f.under = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.under:SetSize(100, 22); f.under:SetPoint("BOTTOMRIGHT", -10, 10)
  f.under:SetScript("OnClick", function()        -- cycles 1, 2, 3, 5, 8, 10, 15 percent
    local steps = { 1, 2, 3, 5, 8, 10, 15 }
    local cur, nxt = DB.postUnder or DEFAULT_UNDER, steps[1]
    for i, v in ipairs(steps) do if v == cur then nxt = steps[i % #steps + 1] end end
    DB.postUnder = nxt; Post.RefreshUI()
  end)
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, d) off = off - d * 3; Post.RefreshUI() end)
  f:Hide()
  return f
end

function Post.Show(show)
  if not DB then return end
  win = win or Build()
  if show == nil then show = not win:IsShown() end
  local target = AuctionHouseFrame or AuctionFrame
  if show then
    if target and target:IsShown() then win:ClearAllPoints(); win:SetPoint("TOPRIGHT", target, "TOPLEFT", -4, 0) end
    win:Show()
  else win:Hide() end
  Post.RefreshUI()
end
function Post.Window() return win end

local function AttachButton()
  if not DB then return end
  win = win or Build()
  local target = (AuctionHouseFrame and AuctionHouseFrame:IsShown() and AuctionHouseFrame) or AuctionFrame or AuctionHouseFrame
  if not target then return end
  if not ahButton then
    ahButton = CreateFrame("Button", "RealmPostAHButton", target, "UIPanelButtonTemplate")
    ahButton:SetSize(110, 22)
    ahButton:SetScript("OnClick", function() Post.Show() end)
  end
  if ns.UI and ns.UI.Modern then ns.UI.Modern(ahButton) end
  if ahButton:GetParent() ~= target then ahButton:SetParent(target) end
  ahButton:ClearAllPoints()
  -- bottom right, on the same line as the Exchange ">" button and just left of it (110 wide at -8, plus a 6px gap)
  ahButton:SetPoint("TOPRIGHT", target, "BOTTOMRIGHT", -124, 2)
  ahButton:SetFrameLevel((target:GetFrameLevel() or 1) + 20)
  ahButton:Show()
  Post.RefreshUI()
end

-- ------------------------------------------------------------ commands
local function IdOf(text)
  if not text or text == "" then return nil end
  return tonumber(text:match("item:(%d+)")) or tonumber(text:match("^%s*(%d+)%s*$"))
end

function Post.Command(arg)
  arg = (arg or ""):lower()
  local sub, rest = arg:match("^(%S*)%s*(.-)$")
  if not DB then return end
  if sub == "" then Post.Show()
  elseif sub == "add" then
    local id = IdOf(rest)
    if id then Post.Learn(id) else Print("Usage: /realm post add <item link or id>") end
  elseif sub == "remove" or sub == "del" then
    local id = IdOf(rest)
    if id and Post.Remove(id) then Print("removed item " .. id .. ".") else Print("Usage: /realm post remove <item link or id>") end
  elseif sub == "list" then
    for _, id in ipairs(SortedIds()) do
      local e = DB.postList[id]
      local price, why = Post.Quote(id)
      print(("  %s (%d): %s"):format(e.name or id, id, price and ns.Coin(price) or tostring(why)))
    end
  elseif sub == "next" then Post.Next()
  elseif sub == "under" then
    local v = tonumber(rest)
    if v and v >= 0 and v <= 50 then DB.postUnder = v; Print("undercut: " .. v .. "%") else Print("Usage: /realm post under 5") end
  elseif sub == "floor" then
    local id, silver = rest:match("^(%S+)%s+(%d+)")
    id = IdOf(id)
    if id and DB.postList[id] then DB.postList[id].floor = tonumber(silver) * 100; Print("floor set to " .. silver .. " silver.") else Print("Usage: /realm post floor <item> <silver>") end
  elseif sub == "learn" then
    if rest == "off" then DB.postLearn = false elseif rest == "on" then DB.postLearn = true else DB.postLearn = (DB.postLearn == false) end
    Print("learning from your manual posts: " .. (DB.postLearn == false and "off" or "ON"))
  elseif sub == "dur" then
    local v = tonumber(rest)
    if v and v >= 1 and v <= 3 then
      for _, e in pairs(DB.postList) do e.dur = v end
      Print("every item on the list now posts for " .. DUR_TEXT[v] .. ".")
    else Print("Usage: /realm post dur 1|2|3  (12h, 24h, 48h)") end
  else Print("/realm post (window) | add <item> | remove <item> | list | next | under <n> | floor <item> <silver> | learn on|off | dur 1|2|3") end
end

-- ------------------------------------------------------------ events
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "BAG_UPDATE_DELAYED" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, e)
  if e == "PLAYER_LOGIN" then
    DB = ns.DB
    DB.postList = DB.postList or {}
    if DB.postLearn == nil then DB.postLearn = true end
    if C_AuctionHouse and hooksecurefunc then
      if C_AuctionHouse.PostCommodity then pcall(hooksecurefunc, C_AuctionHouse, "PostCommodity", Post.OnPostCommodity) end
      if C_AuctionHouse.PostItem then pcall(hooksecurefunc, C_AuctionHouse, "PostItem", Post.OnPostItem) end
    end
  elseif not DB then return
  elseif e == "AUCTION_HOUSE_SHOW" then
    C_Timer.After(0.3, AttachButton)
  elseif e == "AUCTION_HOUSE_CLOSED" then
    if win then win:Hide() end
  elseif e == "BAG_UPDATE_DELAYED" then
    if win and win:IsShown() then Post.RefreshUI() end
  end
end)
