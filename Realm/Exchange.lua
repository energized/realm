-- Realm Exchange: treat the auction house like a stock market.
-- Records price history per item, finds dips below the recent norm, flags sell-highs in your bags.
local ADDON, ns = ...

local TAX = 0.95                 -- AH cut
local MAXITEMS, MAXSAMPLES = 3000, 48
local MIN_GAP, MAX_AGE = 1800, 14 * 86400   -- one sample per 30 min, keep 14 days
local CHUNK = 1500               -- listings processed per frame during a scan
local ROWS = 16
local MIN_STOCK_PRICE, MIN_STOCK_QTY = 100, 5
-- smart scan: a cheapest listing far above the item's own median is held back (see HoldBack)
local HOLD_MIN_SAMPLES, HOLD_CLUSTER, CLUSTER_PCT = 3, 3, 0.15
local HOLD_SCANS, HOLD_SECS = 4, 2 * 3600

ns.Exchange = {}
local DEFAULTS = { exAuto = true, exGear = false, exDock = true, exMinDisc = 0.15,
                   exMinProfit = 1000, exMinSamples = 8, exMinZ = 2,
                   exMaxPrice = 0, exMinPrice = 0, exRange = false, exSheetDays = 30,
                   exSmart = true, exOutlier = 2 }   -- copper; exMaxPrice 0 = no spending cap; exSmart holds back inflated prices
local DB, store, demoStore, live
local settings, ahButton, sheet, ignoredWin
local rolledOut                      -- opened from the AH tab; closes with the AH
local slide = { off = 0, p = 0, dir = 0 }
local TAB_GAP, SLIDE_PX, SLIDE_SECS = 26, 60, 0.2
local frame, rows = nil, {}
local scan = nil                 -- active scan state
local lastScan = 0
local results = { buys = {}, sells = {}, watch = {}, index = nil, tracked = 0 }

-- ---------- helpers ----------
-- Gold/silver/copper with the real coin icons (shared formatter in Realm.lua); h sizes the icon to the row font.
local function Money(c, h) return ns.Coin(c, h) end
local function Print(m) ns.Print(m) end
-- Ignored items (DB.exIgnore[id] = true): no signals, not recorded by scans, until restored.
local function Ignored(id) return DB and DB.exIgnore and DB.exIgnore[id] end

-- the lowest price the last scan saw for an item, and when it was seen (nil when there is no history); used by Realm Post
function ns.Exchange.Lowest(id)
  local it = store and store[id]
  if not it or #it.p == 0 then return nil end
  return it.p[#it.p], it.seen
end

local function RealmKey()
  local r = (GetRealmName and GetRealmName()) or "realm"
  if C_AuctionHouse and C_AuctionHouse.ReplicateItems then return r end
  return r .. "-" .. (UnitFactionGroup and UnitFactionGroup("player") or "")
end

local function median(t)
  local n = #t
  if n == 0 then return 0 end
  local c = {}
  for i = 1, n do c[i] = t[i] end
  table.sort(c)
  if n % 2 == 1 then return c[(n + 1) / 2] end
  return (c[n / 2] + c[n / 2 + 1]) / 2
end

-- ---------- data ----------
local function Record(id, price, qty, now)
  if Ignored(id) then return end
  local it = store[id]
  if not it then
    if not DB.exWatch[id] and (price < MIN_STOCK_PRICE or qty < MIN_STOCK_QTY) then return end
    it = { t = {}, p = {}, q = {}, seen = now }
    store[id] = it
  end
  it.seen = now
  local n = #it.t
  if n > 0 and now - it.t[n] < MIN_GAP then
    it.p[n], it.q[n] = price, qty            -- same window: overwrite
  else
    n = n + 1
    it.t[n], it.p[n], it.q[n] = now, price, qty
  end
  while #it.t > MAXSAMPLES or (#it.t > 1 and now - it.t[1] > MAX_AGE) do
    table.remove(it.t, 1); table.remove(it.p, 1); table.remove(it.q, 1)
  end
end

-- Smart scan. The scan keeps the cheapest listing of each item, so one dear listing among many changes nothing. The
-- harm comes when the cheapest listing is itself inflated (a thin market, one bait listing): it would drag the median
-- up and fake sell signals. So a price at least DB.exOutlier times the item's own median is HELD BACK: it is not saved.
-- It is let in once the market proves it is real: 3 or more listings within 15% of the cheapest (cluster), or the
-- same high price seen over 4 scans spanning 2 hours. Cheap outliers are left alone: they are real chances to buy.
-- lows = the three cheapest unit prices of the scan, sorted. Returns true when the price is held back.
local function ClusterCount(lows)
  local n = 0
  for i = 1, #lows do
    if lows[i] <= lows[1] * (1 + CLUSTER_PCT) then n = n + 1 end
  end
  return n
end

local function HoldBack(it, price, lows, now)
  if not it or DB.exSmart == false or #it.p < HOLD_MIN_SAMPLES then return false end
  local med = median(it.p)
  local function release() it.held, it.heldSince, it.heldPrice = nil, nil, nil; return false end
  if med <= 0 or price < med * (DB.exOutlier or 2) then return release() end
  if ClusterCount(lows or {}) >= HOLD_CLUSTER then return release() end
  it.held = (it.held or 0) + 1
  it.heldSince = it.heldSince or now
  it.heldPrice = price
  if it.held >= HOLD_SCANS and now - it.heldSince >= HOLD_SECS then return release() end
  return true
end

local function Prune(now)
  local count = 0
  for id, it in pairs(store) do
    if now - it.seen > MAX_AGE then store[id] = nil else count = count + 1 end
  end
  -- over the cap: drop the cheapest-by-turnover items
  if count > MAXITEMS then
    local list = {}
    for id, it in pairs(store) do list[#list + 1] = { id, it.p[#it.p] * it.q[#it.q] } end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    for i = 1, count - MAXITEMS do store[list[i][1]] = nil end
  end
end

-- Returns analysis table or nil if not enough history.
local function Analyze(it, minN)
  local n = #it.p
  if n < (minN or 3) then return end
  local cur = it.p[n]
  local base = {}
  for i = 1, n - 1 do base[i] = it.p[i] end
  local med = median(base)
  if med <= 0 then return end
  local devs = {}
  for i = 1, #base do devs[i] = math.abs(base[i] - med) end
  local sigma = math.max(1.4826 * median(devs), 0.03 * med)
  local falling = n >= 4 and it.p[n] < it.p[n - 1] and it.p[n - 1] < it.p[n - 2] and it.p[n - 2] < it.p[n - 3]
  return {
    cur = cur, med = med, n = n, qty = it.q[n],
    disc = (med - cur) / med,
    z = (med - cur) / sigma,
    net = med * TAX - cur,
    falling = falling,
  }
end

local function ItemClass(id)
  if GetItemInfoInstant then
    local _, _, _, _, _, classID = GetItemInfoInstant(id)
    return classID
  end
end

local function BagCounts()
  local counts = {}
  local CC = C_Container
  local numSlots = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
  if not numSlots then return counts end
  for bag = 0, 5 do
    for slot = 1, (numSlots(bag) or 0) do
      local link, n
      if CC and CC.GetContainerItemInfo then
        local i = CC.GetContainerItemInfo(bag, slot)
        if i then link, n = i.hyperlink, i.stackCount end
      elseif GetContainerItemInfo then
        local _, c, _, _, _, _, l = GetContainerItemInfo(bag, slot)
        link, n = l, c
      end
      local id = link and tonumber(link:match("item:(%d+)"))
      if id then counts[id] = (counts[id] or 0) + (n or 1) end
    end
  end
  return counts
end

local function Compute()
  local minDisc, minProfit = DB.exMinDisc, DB.exMinProfit
  local minN, minZ = DB.exMinSamples, DB.exMinZ
  local buys, sells, watch, track = {}, {}, {}, {}
  local ratioSum, ratioN, tracked = 0, 0, 0
  local bags = BagCounts()
  -- spending limits: a cap on the unit price, plus an optional minimum when the range toggle is on
  local maxP = (DB.exMaxPrice or 0) > 0 and DB.exMaxPrice or nil
  local minP = DB.exRange and (DB.exMinPrice or 0) or 0
  local function PriceOK(p)
    return p >= minP and (not maxP or p <= maxP)
  end
  local function QualifiesBase(a)
    return a.disc >= minDisc and a.z >= minZ and a.n >= minN and a.net >= minProfit
  end
  local function Qualifies(a)
    return QualifiesBase(a) and PriceOK(a.cur)
  end
  local above, below = 0, 0        -- would-be BUY signals priced above the max / below the min
  for id, it in pairs(store) do
    tracked = tracked + 1
    local a = not Ignored(id) and Analyze(it, 3)
    if a then
      a.id = id
      if a.n >= minN then ratioSum = ratioSum + a.cur / a.med; ratioN = ratioN + 1 end
      if Qualifies(a) then
        if a.falling then watch[#watch + 1] = a
        else
          a.score = a.net * math.sqrt(math.min(a.qty, 50))
          buys[#buys + 1] = a
        end
      elseif not a.falling and QualifiesBase(a) then
        if maxP and a.cur > maxP then above = above + 1 else below = below + 1 end
      end
      if bags[id] and a.n >= minN and a.cur >= a.med * 1.12 then
        local s = {}
        for k, v in pairs(a) do s[k] = v end
        s.owned = bags[id]
        s.score = (a.cur - a.med) * bags[id]
        sells[#sells + 1] = s
      end
    end
  end
  -- manually tracked items (always listed)
  for id in pairs(DB.exWatch) do
    local it = store[id]
    local a = it and Analyze(it, 2)
    if a then
      a.id = id
      if a.n < minN then a.tag = "LEARN"
      elseif Qualifies(a) then a.tag = a.falling and "WATCH" or "BUY"
      elseif bags[id] and a.cur >= a.med * 1.12 then a.tag = "SELL"
      else a.tag = "HOLD" end
    else
      a = { id = id, nodata = true }
    end
    track[#track + 1] = a
  end
  table.sort(buys, function(x, y) return x.score > y.score end)
  table.sort(sells, function(x, y) return x.score > y.score end)
  table.sort(watch, function(x, y) return x.disc > y.disc end)
  table.sort(track, function(x, y) return (x.disc or -9) > (y.disc or -9) end)
  results = { buys = buys, sells = sells, watch = watch, track = track, tracked = tracked,
              above = above, below = below,
              index = ratioN > 0 and (ratioSum / ratioN - 1) * 100 or nil }
  return results
end

-- ---------- ledger: what you bought and sold, plus a longer daily price history ----------
-- ledger.buys / ledger.sells keep every trade for 6 months. hist keeps the lowest price of each day for 100 days,
-- for tracked and traded items only, so the saved data stays small. The spreadsheet reads both.
local HIST_DAYS, LEDGER_KEEP, LEDGER_MAX = 100, 180 * 86400, 5000
local AH_MAIL_LIFE = 30 * 86400      -- auction mail lasts 30 days: a sale is dated from the mail's time left
local ledger, hist                   -- set at login
local traded = {}                    -- item ids with a trade: they get daily history even when not tracked

local function DayIndex(t) return math.floor(t / 86400) end

local function RecordDaily(id, price, qty, now)
  local h = hist and hist[id]
  if hist and not h then h = { d = {}, lo = {}, q = {} }; hist[id] = h end
  if not h then return end
  price = math.floor(price)
  local day, n = DayIndex(now), #h.d
  if n > 0 and h.d[n] == day then
    if price < h.lo[n] then h.lo[n] = price end
    h.q[n] = qty
  else
    n = n + 1
    h.d[n], h.lo[n], h.q[n] = day, price, qty
  end
  while n > 0 and day - h.d[1] > HIST_DAYS do
    table.remove(h.d, 1); table.remove(h.lo, 1); table.remove(h.q, 1); n = n - 1
  end
end

-- keep a trade list ordered by time (mail-dated trades can arrive out of order)
local function InsertSorted(list, e)
  local i = #list + 1
  list[i] = e
  while i > 1 and list[i - 1].t > e.t do
    list[i] = list[i - 1]; list[i - 1] = e; i = i - 1
  end
end

local function Trim(list, now)
  while #list > LEDGER_MAX or (#list > 0 and now - list[1].t > LEDGER_KEEP) do table.remove(list, 1) end
end

-- kind: "buyout" or "bid" (a won bid). src: "click" (bought from the Exchange list) or "mail" (read from an invoice)
local function LedgerBuy(id, name, unit, qty, kind, now, src)
  if not ledger or not name then return end
  now = now or time()
  qty = math.max(1, qty or 1)
  unit = math.floor((unit or 0) + .5)
  local e = { t = now, id = id, name = name, unit = unit, qty = qty, amt = unit * qty,
              kind = kind or "buyout", src = src or "click" }
  InsertSorted(ledger.buys, e); Trim(ledger.buys, now)
  if id then traded[id] = true end
  return e
end

-- gross = what the buyer paid, fee = the auction house cut; the net is what reaches you
local function LedgerSale(id, name, gross, fee, qty, t, ex)
  if not ledger or not name then return end
  qty = math.max(1, qty or 1)
  fee = fee or 0
  local e = { t = t or time(), id = id, name = name, qty = qty, gross = gross, fee = fee,
              net = gross - fee, amt = gross, ex = ex }
  InsertSorted(ledger.sells, e); Trim(ledger.sells, e.t)
  if id then traded[id] = true end
  return e
end

local function IdFromName(name)
  if GetItemInfoInstant then
    local id = GetItemInfoInstant(name)
    if id then return id end
  end
  for _, e in ipairs(ledger.buys) do
    if e.name == name and e.id then return e.id end
  end
end

-- the same invoice stays in the inbox for days: recognise it by item, amount and expiry time
local function Seen(list, name, amount, ex)
  for i = #list, 1, -1 do
    local e = list[i]
    if e.ex and e.name == name and e.amt == amount and math.abs(e.ex - ex) < 1800 then return true end
  end
end

-- a "won" invoice for something you already bought out from the list is the same purchase: mark it, do not add it twice
local function MatchClickBuy(name, id, amount, ex, now)
  for i = #ledger.buys, 1, -1 do
    local e = ledger.buys[i]
    if now - e.t > 3 * 86400 then break end
    if e.src == "click" and not e.ex and (e.name == name or (id and e.id == id)) and math.abs(e.amt - amount) <= e.qty then
      e.ex, e.amt = ex, amount
      return true
    end
  end
end

-- Reads auction invoices in the open mailbox. Returns how many new trades were recorded.
local function ScanInvoices()
  if not (ledger and GetInboxNumItems and GetInboxInvoiceInfo and GetInboxHeaderInfo) then return 0 end
  local now, added = time(), 0
  for i = 1, (GetInboxNumItems() or 0) do
    local kind, name, _, bid, buyout, _, fee, _, _, _, count = GetInboxInvoiceInfo(i)
    if (kind == "seller" or kind == "buyer") and name and (bid or 0) > 0 then
      local daysLeft = select(7, GetInboxHeaderInfo(i)) or 30
      local ex = now + daysLeft * 86400
      local t = math.min(now, ex - AH_MAIL_LIFE)
      count = (count and count > 0) and count or 1
      local id = IdFromName(name)
      if kind == "seller" then
        if not Seen(ledger.sells, name, bid, ex) then
          LedgerSale(id, name, bid, fee, count, t, ex); added = added + 1
        end
      elseif not Seen(ledger.buys, name, bid, ex) and not MatchClickBuy(name, id, bid, ex, now) then
        local how = (buyout and buyout > 0 and bid >= buyout) and "buyout" or "bid"
        local e = LedgerBuy(id, name, bid / count, count, how, t, "mail")
        e.ex, e.amt = ex, bid
        added = added + 1
      end
    end
  end
  return added
end

-- ---------- scanning ----------
local heldIds = {}                   -- items whose price the last scan held back as inflated

local function Finish()
  local now = time()
  heldIds = {}
  for id, a in pairs(scan.agg) do
    if HoldBack(store[id], a.price, a.lows, now) then
      store[id].seen = now                -- still on the market: keep the item from pruning
      heldIds[#heldIds + 1] = id
    else
      Record(id, a.price, a.qty, now)
      if DB.exWatch[id] or traded[id] then RecordDaily(id, a.price, a.qty, now) end
    end
  end
  Prune(now)
  lastScan = now
  DB.exLastScan = now
  local msg = ("Scan complete: %d items priced."):format(scan.items)
  if #heldIds > 0 then
    msg = msg .. (" %d held back as inflated (/realm ex held)."):format(#heldIds)
  end
  Print(msg)
  scan = nil
  Compute()
  ns.Exchange.Refresh()
end

local function ProcessChunk()
  if not scan then return end
  local stop = math.min(scan.i + CHUNK - 1, scan.total)
  for i = scan.i, stop do
    local count, buy, id = scan.get(i)
    if id and buy and buy > 0 and count and count > 0 and not Ignored(id) then
      local cls = ItemClass(id)
      if DB.exGear or DB.exWatch[id] or not (cls == 2 or cls == 4) then
        local unit = buy / count
        local a = scan.agg[id]
        if not a then
          a = { price = unit, qty = 0, lows = {} }
          scan.agg[id] = a
          scan.items = scan.items + 1
        end
        if unit < a.price then a.price = unit end
        local lw = a.lows                 -- the three cheapest listings, for the inflated-price check
        if #lw < 3 then lw[#lw + 1] = unit; table.sort(lw)
        elseif unit < lw[3] then lw[3] = unit; table.sort(lw) end
        a.qty = a.qty + count
      end
    end
  end
  scan.i = stop + 1
  if scan.i > scan.total then Finish() end
end

local function BeginScan(get, total)
  scan = { get = get, total = total, i = 1, agg = {}, items = 0 }
end

local function IngestReplicate()
  local C = C_AuctionHouse
  local total = C.GetNumReplicateItems and C.GetNumReplicateItems() or 0
  if total <= 0 then return false end
  BeginScan(function(i)
    -- replicate indexes are 0-based
    local _, _, count, _, _, _, _, _, _, buy, _, _, _, _, _, _, id = C.GetReplicateItemInfo(i - 1)
    return count, buy, id
  end, total)
  return true
end

local function StartScan()
  if scan then return end
  if C_AuctionHouse and C_AuctionHouse.ReplicateItems then
    Print("Scanning market...")
    scan = { waiting = "retail" }
    C_AuctionHouse.ReplicateItems()
    -- Only one full scan per 15 min is allowed (shared with Auctionator etc.).
    -- If nothing arrives, read the data another addon already pulled.
    C_Timer.After(6, function()
      if scan and scan.waiting == "retail" then
        scan = nil
        if IngestReplicate() then
          Print("Full scan is on cooldown; using the market data already loaded by another addon.")
        else
          Print("Full scan is on cooldown (15 min). Run an Auctionator scan, or try again later.")
        end
      end
    end)
  elseif QueryAuctionItems then
    local canQuery, canMass = CanSendAuctionQuery()
    if not canMass then
      Print("Full scan is on cooldown (about 15 min). Try again later.")
      return
    end
    Print("Scanning market...")
    scan = { waiting = "classic" }
    QueryAuctionItems("", nil, nil, 0, false, 0, true, false, nil)
  else
    Print("Open the auction house first.")
  end
end

local function OnReplicate()
  if scan and scan.waiting == "retail" then
    IngestReplicate()
  elseif not scan and time() - lastScan > 120 then
    -- another addon (Auctionator etc.) scanned: read the same data for free
    IngestReplicate()
  end
end

local function OnClassicList()
  if not (scan and scan.waiting == "classic") then return end
  local _, total = GetNumAuctionItems("list")
  BeginScan(function(i)
    local _, _, count, _, _, _, _, _, _, buy, _, _, _, _, _, _, id = GetAuctionItemInfo("list", i)
    return count, buy, id
  end, total)
end

-- ---------- UI ----------
local SIGCOLOR = { BUY = "ff33ff66", SELL = "ffff9933", WATCH = "ffaaaaaa", TRACK = "ff66ccff" }
local RefreshSettings

local function ItemName(id)
  local name = GetItemInfo and GetItemInfo(id)
  return name or ("item:" .. id)
end

local function ParseItem(text)
  if not text or text == "" then return end
  local id = tonumber(text:match("item:(%d+)")) or tonumber(text:match("^%s*(%d+)%s*$"))
  if not id and GetItemInfoInstant then id = GetItemInfoInstant(text) end
  return id
end

local function IgnoreItem(id)
  DB.exIgnore = DB.exIgnore or {}
  DB.exIgnore[id] = true
  DB.exWatch[id] = nil
  Print(ItemName(id) .. " is ignored: no signals and no scanning. Restore it from the Ignored list (/realm ex ignored).")
  Compute(); ns.Exchange.Refresh(); ns.Exchange.RefreshIgnored(); RefreshSettings()
end
local function UnignoreItem(id)
  if not Ignored(id) then Print(ItemName(id) .. " is not on the ignored list.") return end
  DB.exIgnore[id] = nil
  Print(ItemName(id) .. " restored. The next scan will price it again.")
  Compute(); ns.Exchange.Refresh(); ns.Exchange.RefreshIgnored()
end

local function AddWatch(id)
  if Ignored(id) then DB.exIgnore[id] = nil end   -- tracking an item brings it back
  DB.exWatch[id] = true
  Print("Tracking " .. ItemName(id) .. ". It is recorded on every scan from now on.")
  Compute(); ns.Exchange.Refresh(); RefreshSettings()
end
local function RemoveWatch(id)
  DB.exWatch[id] = nil
  Print("Stopped tracking " .. ItemName(id))
  Compute(); ns.Exchange.Refresh(); RefreshSettings()
end

-- the name on a link of that item in your bags (works even when the game has not cached the item yet)
local function BagName(id)
  local CC = C_Container
  local num = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
  local getLink = (CC and CC.GetContainerItemLink) or GetContainerItemLink
  if not (num and getLink) then return end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, (num(bag) or 0) do
      local l = getLink(bag, slot)
      if l and tonumber(l:match("item:(%d+)")) == id then return l:match("%[(.-)%]") end
    end
  end
end

-- tried: set on the one automatic retry, after the game was asked to load the item or the AH query was throttled
local function SearchAH(id, tried)
  local name = GetItemInfo and GetItemInfo(id)
  if not name then name = BagName(id) end
  if not name then
    if not tried then
      if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
      C_Timer.After(1, function() SearchAH(id, true) end)
      return
    end
    Print("Item not cached yet; hover it once, then click again.") return
  end
  if not tried and CanSendAuctionQuery and not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) and not CanSendAuctionQuery() then
    Print("The auction house is busy; searching for " .. name .. " in a moment.")
    C_Timer.After(1.5, function() SearchAH(id, true) end)
    return
  end
  local ok
  if AuctionHouseFrame and AuctionHouseFrame:IsShown() and AuctionHouseFrame.SearchBar then
    local sb = AuctionHouseFrame.SearchBar
    pcall(function()
      if sb.SearchBox then sb.SearchBox:SetText(name) end
      if sb.StartSearch then sb:StartSearch(); ok = true end
    end)
  elseif AuctionFrame and AuctionFrame:IsShown() and BrowseName then
    pcall(function()
      BrowseName:SetText(name)
      if AuctionFrameBrowse_Search then AuctionFrameBrowse_Search(); ok = true end
    end)
  end
  if not ok then Print("Couldn't drive the auction house search; search for: " .. name) end
end

local function AHTarget()
  if AuctionHouseFrame and AuctionHouseFrame:IsShown() then return AuctionHouseFrame end
  if AuctionFrame and AuctionFrame:IsShown() then return AuctionFrame end
end

-- ---------- click to buy ----------
-- Click a row: search that item live, take the cheapest listing, ask first, then buy it out.
-- A listing with no buyout can only be bid on, so the minimum bid is used instead.
local buy                                   -- pending purchase { id, token, go, ... }
local buyToken = 0
local BUY_COIN_H = 14

if StaticPopupDialogs then
  StaticPopupDialogs["REALM_EXCHANGE_BUY"] = {
    text = "%s", button1 = "Buy", button2 = CANCEL or "Cancel",
    timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function() local b = buy; if b and b.go then b.go() end end,
    OnCancel = function()
      local b = buy
      if b and b.started and not b.confirmed and C_AuctionHouse and C_AuctionHouse.CancelCommoditiesPurchase then
        C_AuctionHouse.CancelCommoditiesPurchase()
      end
      buy = nil
    end,
  }
end

local function BuyAsk(text, go)
  buy.go = go
  if StaticPopup_Show then StaticPopup_Show("REALM_EXCHANGE_BUY", text) end
end

local function BidNeeded(r)
  local cur = r.bidAmount or 0
  if cur > 0 then return math.ceil(cur * 1.05) end   -- assumed 5% minimum raise over the current bid
  return r.minBid or 0
end

local function OnItemResults(key)
  local AH, b = C_AuctionHouse, buy
  local bestBuy, bestBid
  for i = 1, AH.GetNumItemSearchResults(key) do
    local r = AH.GetItemSearchResultInfo(key, i)
    if r and not r.containsOwnerItem then
      if r.buyoutAmount and r.buyoutAmount > 0 then
        if not bestBuy or r.buyoutAmount < bestBuy.buyoutAmount then bestBuy = r end
      elseif not bestBid or BidNeeded(r) < BidNeeded(bestBid) then
        bestBid = r
      end
    end
  end
  if bestBuy then
    BuyAsk(("Buy out %s for %s?"):format(b.name, Money(bestBuy.buyoutAmount, BUY_COIN_H)), function()
      AH.PlaceBid(bestBuy.auctionID, bestBuy.buyoutAmount)
      local q = math.max(1, bestBuy.quantity or 1)
      LedgerBuy(b.id, b.name, bestBuy.buyoutAmount / q, q, "buyout")   -- a bid is recorded later, from the "won" mail
      Print("Buyout sent for " .. b.name .. ".")
      buy = nil
    end)
  elseif bestBid then
    local amt = BidNeeded(bestBid)
    BuyAsk(("%s has no buyout. Bid %s?"):format(b.name, Money(amt, BUY_COIN_H)), function()
      AH.PlaceBid(bestBid.auctionID, amt)
      Print("Bid sent for " .. b.name .. ".")
      buy = nil
    end)
  else
    Print("No listings you can buy for " .. b.name .. ".")
    buy = nil
  end
end

local function OnCommodityResults(id)
  local AH, b = C_AuctionHouse, buy
  if (AH.GetNumCommoditySearchResults(id) or 0) < 1 then
    Print("No listings for " .. b.name .. ".")
    buy = nil
    return
  end
  local r = AH.GetCommoditySearchResultInfo(id, 1)
  BuyAsk(("Buy 1 %s for %s?"):format(b.name, Money(r.unitPrice, BUY_COIN_H)), function()
    b.started = true
    AH.StartCommoditiesPurchase(id, 1)
  end)
end

-- events: search results, the commodity price quote, then the purchase result
local function BuyEvent(event, a1, a2)
  local b = buy
  if not b then return end
  if event == "ITEM_SEARCH_RESULTS_UPDATED" then
    if not b.go and type(a1) == "table" and a1.itemID == b.id then OnItemResults(a1) end
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    if not b.go and a1 == b.id then OnCommodityResults(a1) end
  elseif event == "COMMODITY_PRICE_UPDATED" then
    if b.started and not b.final then
      b.final = true
      b.paid = a2 or a1 or 0
      BuyAsk(("Final price for 1 %s: %s. Confirm?"):format(b.name, Money(a2 or a1 or 0, BUY_COIN_H)), function()
        b.confirmed = true
        C_AuctionHouse.ConfirmCommoditiesPurchase(b.id, 1)
      end)
    end
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    if b.confirmed then
      LedgerBuy(b.id, b.name, b.paid or 0, 1, "buyout")
      Print("Bought 1 " .. b.name .. "."); buy = nil
    end
  elseif event == "COMMODITY_PURCHASE_FAILED" then
    if b.started then Print("The purchase of " .. b.name .. " failed."); buy = nil end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    buy = nil
  end
end

local function BuyItem(id)
  local AH = C_AuctionHouse
  if not (AH and AH.SendSearchQuery and AH.MakeItemKey) then
    Print("Click-to-buy needs the retail-style auction house.")
    return
  end
  if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
    Print("Open the auction house first, then click an item to buy it.")
    return
  end
  buyToken = buyToken + 1
  local token = buyToken
  buy = { id = id, token = token, name = ItemName(id) }
  local sorts = (Enum and Enum.AuctionHouseSortOrder)
    and { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } } or {}
  AH.SendSearchQuery(AH.MakeItemKey(id), sorts, true)
  C_Timer.After(6, function()
    if buy and buy.token == token and not buy.go then
      Print("No listings came back for " .. ItemName(id) .. ".")
      buy = nil
    end
  end)
end

local function Dock()
  local target = AHTarget()
  if DB and DB.exDock and frame and target then
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", target, "TOPRIGHT", TAB_GAP - slide.off, 0)
  end
end

-- Spreadsheet columns: { x offset in the row, width, justify }
local COLS = {
  sig   = { 8, 44, "LEFT" },
  name  = { 74, 148, "LEFT" },
  price = { 226, 112, "RIGHT" },
  pct   = { 342, 40, "RIGHT" },
  extra = { 388, 82, "RIGHT" },
}
local SIGRGB = { BUY = { .2, 1, .4 }, SELL = { 1, .6, .2 }, WATCH = { .67, .67, .67 }, TRACK = { .4, .8, 1 } }
local COIN_H = 12   -- coin icon height, matched to the row font
local ROW_W, ROW_Y0 = 472, -58

local function Cell(parent, col)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("LEFT", col[1], 0)
  fs:SetWidth(col[2])
  fs:SetJustifyH(col[3])
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  return fs
end

local function ItemIcon(id)
  if GetItemIcon then return GetItemIcon(id) end
  if GetItemInfoInstant then return select(5, GetItemInfoInstant(id)) end
end

-- Item name in its quality colour.
local function ItemLabel(id)
  local name, q
  if GetItemInfo then local n, _, qq = GetItemInfo(id); name, q = n, qq end
  if not name then return "|cff888888item:" .. id .. "|r" end
  local col = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  local hex = col and (col.hex or (col.r and ("|cff%02x%02x%02x"):format(
    math.floor(col.r * 255 + .5), math.floor(col.g * 255 + .5), math.floor(col.b * 255 + .5))))
  return (hex or "|cffffffff") .. name .. "|r"
end

local function Build()
  local f = CreateFrame("Frame", "RealmExchange", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(492, 68 + ROWS * 20 + 34)
  f:SetPoint("CENTER", 200, 0)
  f:SetFrameStrata("HIGH"); f:SetToplevel(true)   -- above the travel compass (MEDIUM); a click raises it over other Realm windows
  f:SetClampedToScreen(true)
  f:SetMovable(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetScript("OnShow", function() Dock() end)
  ns.UI.Skin(f)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOPLEFT", 10, -9)
  f.index = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.index:SetPoint("TOPLEFT", 10, -28)
  f.foot = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.foot:SetPoint("BOTTOMLEFT", 10, 12)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() f:Hide() end)

  local sheetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  sheetBtn:SetSize(90, 20); sheetBtn:SetText("Spreadsheet")
  sheetBtn:SetPoint("TOPRIGHT", close, "TOPLEFT", 0, -4)
  sheetBtn:SetScript("OnClick", function() ns.Exchange.ShowSheet() end)

  local ignBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  ignBtn:SetSize(86, 20); ignBtn:SetText("Ignored (0)")
  ignBtn:SetPoint("TOPRIGHT", sheetBtn, "TOPLEFT", -4, 0)
  ignBtn:SetScript("OnClick", function() ns.Exchange.ShowIgnored() end)
  f.ignBtn = ignBtn

  local scanBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  scanBtn:SetSize(70, 20); scanBtn:SetText("Scan")
  scanBtn:SetPoint("BOTTOMRIGHT", -10, 8)
  scanBtn:SetScript("OnClick", StartScan)

  local setBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  setBtn:SetSize(80, 20); setBtn:SetText("Settings >")
  setBtn:SetPoint("RIGHT", scanBtn, "LEFT", -6, 0)
  setBtn:SetScript("OnClick", function() ns.Exchange.ShowSettings() end)

  local mailBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  mailBtn:SetSize(60, 20); mailBtn:SetText("Mail")
  mailBtn:SetPoint("RIGHT", setBtn, "LEFT", -6, 0)
  mailBtn:SetScript("OnClick", function() if ns.Mail then ns.Mail.Toggle() end end)

  -- column headers
  for _, h in ipairs({ { "SIGNAL", COLS.sig }, { "ITEM", COLS.name }, { "PRICE NOW", COLS.price },
                       { "VS MEDIAN", COLS.pct }, { "PROFIT / OWNED", COLS.extra } }) do
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", 10 + h[2][1], -44)
    fs:SetWidth(h[2][2] + (h[1] == "PROFIT / OWNED" and 12 or 0))
    fs:SetJustifyH(h[2][3])
    fs:SetText(h[1])
  end

  for i = 1, ROWS do
    local r = CreateFrame("Button", nil, f)
    r:SetSize(ROW_W, 20)
    r:SetPoint("TOPLEFT", 10, ROW_Y0 - (i - 1) * 20)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.a = false
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.06 or 0.02)
    r.stripe = r:CreateTexture(nil, "ARTWORK")
    r.stripe:SetPoint("TOPLEFT", 0, 0); r.stripe:SetPoint("BOTTOMLEFT", 0, 0); r.stripe:SetWidth(3)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 54, 0)
    r.icon:SetTexCoord(.07, .93, .07, .93)
    r.sig, r.name, r.price, r.pct, r.extra =
      Cell(r, COLS.sig), Cell(r, COLS.name), Cell(r, COLS.price), Cell(r, COLS.pct), Cell(r, COLS.extra)
    r:SetScript("OnEnter", function(self)
      if not self.a or not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink("item:" .. self.a.id)
      GameTooltip:AddLine(" ")
      if not self.a.nodata then
        GameTooltip:AddLine(("Now %s  |  median %s"):format(Money(self.a.cur), Money(self.a.med)), 1, 1, 1)
        GameTooltip:AddLine(("%d samples  |  %d on market  |  z-score %.1f"):format(self.a.n, self.a.qty, self.a.z), .7, .7, .7)
      end
      GameTooltip:AddLine(self.kind == "SELL"
        and "Click: search AH   Shift-click: link   Right-click: track/untrack   Alt-click: ignore"
        or "Click: buy out (or bid)   Ctrl-click: search AH   Shift-click: link   Right-click: track/untrack   Alt-click: ignore", .5, .8, 1)
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    r:SetScript("OnClick", function(self, button)
      if not self.a then return end
      local id = self.a.id
      if button == "RightButton" then
        if DB.exWatch[id] then RemoveWatch(id) else AddWatch(id) end
      elseif IsAltKeyDown and IsAltKeyDown() then
        IgnoreItem(id)
      elseif IsShiftKeyDown() and ChatEdit_InsertLink then
        local _, link = GetItemInfo(id)
        if link then ChatEdit_InsertLink(link) end
      elseif self.kind == "SELL" or IsControlKeyDown() then
        SearchAH(id)
      else
        BuyItem(id)
      end
    end)
    rows[i] = r
  end
  f:Hide()
  return f
end

local function ClearRow(row)
  row.a = false
  row.kind = nil
  row.sig:SetText(""); row.name:SetText(""); row.price:SetText(""); row.pct:SetText(""); row.extra:SetText("")
  row.icon:SetTexture(nil)
  row.name:SetWidth(COLS.name[2])
  row.stripe:SetColorTexture(0, 0, 0, 0)
end

-- One spreadsheet row: signal | icon + item | price in coin icons | % vs median | profit / owned / status
local function FillRow(row, sig, a)
  local rgb = SIGRGB[sig]
  row.stripe:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
  row.sig:SetText(("|c%s%s|r"):format(SIGCOLOR[sig], sig))
  row.icon:SetTexture(ItemIcon(a.id) or 134400)
  row.name:SetText(ItemLabel(a.id))
  if a.nodata then
    row.price:SetText("|cff888888no data yet|r")
    row.pct:SetText("")
    row.extra:SetText("|cff888888scan the AH|r")
    return
  end
  row.price:SetText(Money(a.cur, COIN_H))
  local delta = math.floor((a.cur / a.med - 1) * 100)
  local col = delta < 0 and "ff33ff66" or (delta > 0 and "ffff9933" or "ffffffff")
  row.pct:SetText(("|c%s%+d%%|r"):format(col, delta))
  local extra
  if sig == "SELL" then
    extra = ("|cffff9933x%d owned|r"):format(a.owned)
  elseif sig == "TRACK" then
    extra = a.tag == "BUY" and "|cff33ff66BUY|r" or a.tag == "WATCH" and "|cffaaaaaafalling|r"
      or a.tag == "SELL" and "|cffff9933SELL|r" or a.tag == "LEARN"
      and ("|cff888888learning %d/%d|r"):format(a.n, DB.exMinSamples) or "|cff888888hold|r"
  else
    extra = "|cff33ff66+|r" .. Money(a.net, COIN_H)
  end
  row.extra:SetText(extra)
end

-- Scan price of one item for the tooltips and the gear popup: current price, median, number of scans, time of the last
-- scan. nil when the item was never priced (or while the demo data is showing).
function ns.Exchange.Price(id)
  local it = store and store ~= demoStore and store[id]
  local n = it and #it.p or 0
  if n == 0 then return end
  return it.p[n], (n >= 3 and median(it.p) or it.p[n]), n, it.t[n]
end

function ns.Exchange.Refresh()
  if not frame or not frame:IsShown() then return end
  local res = results
  frame.title:SetText("Realm Exchange" .. (store == demoStore and "  |cffff4040[DEMO DATA]|r" or ""))
  if res.index then
    local col = res.index < -1 and "ff33ff66" or (res.index > 1 and "ffff9933" or "ffffffff")
    frame.index:SetText(("Market index: |c%s%+.1f%%|r vs median  (green = cheaper than usual)"):format(col, res.index))
  else
    frame.index:SetText("Market index: needs more scans over a few hours")
  end
  local list = {}
  local function add(sig, src, limit)
    for i = 1, math.min(limit, #src) do list[#list + 1] = { sig, src[i] } end
  end
  add("TRACK", res.track, 6)
  add("SELL", res.sells, 3)
  add("BUY", res.buys, 5)
  -- no BUY in the price range: say whether the dips sit above or below it
  if #res.buys == 0 and ((res.above or 0) > 0 or (res.below or 0) > 0) then
    local hi, lo = res.above or 0, res.below or 0
    local msg
    if hi > 0 and lo > 0 then
      msg = ("Nothing in your range, but %d in the higher ranges and %d in the lower ranges."):format(hi, lo)
    elseif hi > 0 then
      msg = ("Nothing in your range, but %d in the higher ranges."):format(hi)
    else
      msg = ("Nothing in your range, but %d in the lower ranges."):format(lo)
    end
    list[#list + 1] = { "NOTE", msg }
  end
  add("WATCH", res.watch, 2)
  for i = 1, ROWS do
    local row, e = rows[i], list[i]
    if e and e[1] == "NOTE" then
      ClearRow(row)
      row.name:SetWidth(ROW_W - 20)
      row.name:SetText("|cffffcc33" .. e[2] .. "|r")
      row:Show()
    elseif e then
      ClearRow(row)
      row.a = e[2]
      row.kind = e[1]
      FillRow(row, e[1], e[2])
      row:Show()
    else
      ClearRow(row); row:Hide()
    end
  end
  if #list == 0 then
    ClearRow(rows[1])
    rows[1].name:SetWidth(ROW_W - 20)
    rows[1].name:SetText("|cff888888No dips right now. Scan again later; right-click any item to track it.|r")
    rows[1]:Show()
  end
  local ago = lastScan > 0 and math.floor((time() - lastScan) / 60) .. " min ago" or "never"
  frame.foot:SetText(("%d items | scan %s | /realm ex help"):format(res.tracked, ago))
end

-- ---------- spreadsheet: trades and prices over 30 / 60 / 90 days ----------
local function Dur(s)
  if not s then return "-" end
  if s < 3600 then return math.max(1, math.floor(s / 60 + .5)) .. "m" end
  if s < 86400 then return math.floor(s / 3600) .. "h " .. math.floor((s % 3600) / 60) .. "m" end
  return math.floor(s / 86400) .. "d " .. math.floor((s % 86400) / 3600) .. "h"
end

-- current scan price, plus the lowest / average / highest daily low saved inside the window
local function MarketStats(id, from)
  local cur
  local it = id and live and live[id]
  if it and #it.p > 0 then cur = it.p[#it.p] end
  local h = id and hist and hist[id]
  local lo, hi, sum, n = nil, nil, 0, 0
  if h then
    local d0 = DayIndex(from)
    for i = 1, #h.d do
      if h.d[i] >= d0 then
        local p = h.lo[i]
        lo = math.min(lo or p, p); hi = math.max(hi or p, p)
        sum = sum + p; n = n + 1
      end
    end
  end
  return cur, lo, hi, n > 0 and sum / n or nil, n
end

-- One row per item with trades in the last `days` days (plus every tracked item).
-- Profit pairs each sale with the oldest unsold purchases of the same item (first in, first out), even ones bought
-- before the window; turnaround is the time between that purchase and the sale.
function ns.Exchange.Sheet(days, now)
  now = now or time()
  local from = now - days * 86400
  local out = { rows = {}, days = days, totals = { spent = 0, net = 0, profit = 0, bought = 0, sold = 0 } }
  if not ledger then return out end
  local rows, lots = {}, {}
  local function row(key, id, name)
    local r = rows[key]
    if not r then
      r = { key = key, id = id, name = name, bought = 0, spent = 0, sold = 0, net = 0,
            mQty = 0, mNet = 0, mCost = 0, turnSum = 0, buyouts = 0, bids = 0 }
      rows[key] = r
    end
    return r
  end
  for _, b in ipairs(ledger.buys) do
    local key = b.id or ("n:" .. b.name)
    lots[key] = lots[key] or {}
    table.insert(lots[key], { t = b.t, unit = b.unit, left = b.qty })
    if b.t >= from then
      local r = row(key, b.id, b.name)
      r.bought = r.bought + b.qty
      r.spent = r.spent + b.unit * b.qty
      if b.kind == "bid" then r.bids = r.bids + 1 else r.buyouts = r.buyouts + 1 end
    end
  end
  for _, s in ipairs(ledger.sells) do
    local key = s.id or ("n:" .. s.name)
    local r = s.t >= from and row(key, s.id, s.name) or nil
    local need, got, cost, turn = s.qty, 0, 0, 0
    for _, lot in ipairs(lots[key] or {}) do
      if need <= 0 or lot.t > s.t + 3600 then break end
      if lot.left > 0 then
        local take = math.min(lot.left, need)
        lot.left, need, got = lot.left - take, need - take, got + take
        cost = cost + take * lot.unit
        turn = turn + take * math.max(0, s.t - lot.t)
      end
    end
    if r then
      r.sold = r.sold + s.qty
      r.net = r.net + s.net
      if got > 0 then
        r.mQty = r.mQty + got
        r.mNet = r.mNet + s.net * got / s.qty
        r.mCost = r.mCost + cost
        r.turnSum = r.turnSum + turn
      end
    end
  end
  for id in pairs(DB.exWatch or {}) do row(id, id, ItemName(id)) end
  local t, turnQty, turnSum = out.totals, 0, 0
  for _, r in pairs(rows) do
    r.avgBuy = r.bought > 0 and r.spent / r.bought or nil
    r.avgNet = r.sold > 0 and r.net / r.sold or nil
    r.profit = r.mNet - r.mCost
    r.avgTurn = r.mQty > 0 and r.turnSum / r.mQty or nil
    r.cur, r.lo, r.hi, r.avg, r.mDays = MarketStats(r.id, from)
    r.vs = (r.cur and r.avgBuy and r.avgBuy > 0) and (r.cur / r.avgBuy - 1) or nil
    t.spent, t.net, t.profit = t.spent + r.spent, t.net + r.net, t.profit + r.profit
    t.bought, t.sold = t.bought + r.bought, t.sold + r.sold
    turnQty, turnSum = turnQty + r.mQty, turnSum + r.turnSum
    out.rows[#out.rows + 1] = r
  end
  t.avgTurn = turnQty > 0 and turnSum / turnQty or nil
  table.sort(out.rows, function(a, b)
    if a.profit ~= b.profit then return a.profit > b.profit end
    if a.spent ~= b.spent then return a.spent > b.spent end
    return a.name < b.name
  end)
  return out
end

local SROWS, SROW_Y0, SROW_W = 14, -66, 760
local SHEET_W, SHEET_H, SHEET_SPEED, EX_W = 780, 70 + SROWS * 20 + 34, 1100, 492   -- sheet size, slide speed (px/s), Exchange window width
local SCOLS = {
  name   = { 28, 128, "LEFT" },
  bought = { 160, 40, "RIGHT" },
  avgbuy = { 204, 92, "RIGHT" },
  now    = { 300, 92, "RIGHT" },
  vs     = { 396, 44, "RIGHT" },
  sold   = { 444, 40, "RIGHT" },
  avgnet = { 488, 92, "RIGHT" },
  turn   = { 584, 56, "RIGHT" },
  profit = { 644, 108, "RIGHT" },
}
local SHEADS = { { "ITEM", "name" }, { "BOUGHT", "bought" }, { "AVG PAID", "avgbuy" }, { "PRICE NOW", "now" },
                 { "VS PAID", "vs" }, { "SOLD", "sold" }, { "AVG SALE", "avgnet" }, { "TURN", "turn" }, { "PROFIT", "profit" } }
local srows, sheetOff = {}, 0
local DASH = "|cff888888-|r"

local function Signed(c)
  if c < 0 then return "-" .. Money(-c, COIN_H) end
  return Money(c, COIN_H)
end

local function PrintHistory(id)
  local days = DB.exSheetDays or 30
  local _, lo, hi, avg, n = MarketStats(id, time() - days * 86400)
  if n == 0 then
    Print(ItemName(id) .. ": no daily prices saved yet. Track it and scan the auction house on a few different days.")
    return
  end
  Print(("%s, last %d days (%d days saved): low %s, average %s, high %s"):format(
    ItemName(id), days, n, Money(lo), Money(math.floor(avg)), Money(hi)))
end

-- what clicking an item on the spreadsheet offers: { label, action, needs an item id }
local SMENU = {
  { "Buy now (buyout, or bid)", function(id) BuyItem(id) end, true },
  { "Search auction house", function(id) SearchAH(id) end, true },
  { "Track / stop tracking", function(id) if DB.exWatch[id] then RemoveWatch(id) else AddWatch(id) end end, true },
  { "Link in chat", function(id)
      local _, link = GetItemInfo(id)
      if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
    end, true },
  { "Print price history to chat", function(id) PrintHistory(id) end, true },
  { "Ignore / un-ignore item", function(id) if Ignored(id) then UnignoreItem(id) else IgnoreItem(id) end end, true },
  { "Close menu", function() end },
}

local function ClearSheetRow(row)
  row.item = nil
  for _, c in pairs(row.cells) do c:SetText("") end
  row.icon:SetTexture(nil)
  row.cells.name:SetWidth(SCOLS.name[2])
end

local function FillSheetRow(row, r)
  local c = row.cells
  row.item = r
  row.icon:SetTexture((r.id and ItemIcon(r.id)) or 134400)
  c.name:SetText(r.id and ItemLabel(r.id) or ("|cffffffff" .. r.name .. "|r"))
  c.bought:SetText(r.bought > 0 and tostring(r.bought) or DASH)
  c.avgbuy:SetText(r.avgBuy and Money(math.floor(r.avgBuy + .5), COIN_H) or DASH)
  c.now:SetText(r.cur and Money(math.floor(r.cur + .5), COIN_H) or DASH)
  if r.vs then
    local pct = math.floor(r.vs * 100)
    c.vs:SetText(("|c%s%+d%%|r"):format(pct >= 0 and "ff33ff66" or "ffff4040", pct))
  else
    c.vs:SetText(DASH)
  end
  c.sold:SetText(r.sold > 0 and tostring(r.sold) or DASH)
  c.avgnet:SetText(r.avgNet and Money(math.floor(r.avgNet + .5), COIN_H) or DASH)
  c.turn:SetText(r.avgTurn and Dur(r.avgTurn) or DASH)
  if r.mQty > 0 then
    local p = math.floor(r.profit + .5)
    c.profit:SetText(("|c%s%s%s|r"):format(p >= 0 and "ff33ff66" or "ffff4040", p >= 0 and "+" or "", Signed(p)))
  else
    c.profit:SetText(DASH)
  end
end

function ns.Exchange.RefreshSheet()
  if not sheet or not sheet:IsShown() then return end
  local days = DB.exSheetDays or 30
  local data = ns.Exchange.Sheet(days)
  for _, b in ipairs(sheet.dayBtns) do
    b:SetText(b.days == days and ("|cff33ff66%d days|r"):format(b.days) or (b.days .. " days"))
  end
  local t = data.totals
  sheet.sum:SetText(("Last %d days:  spent %s   sold after AH cut %s   profit %s   avg turnaround %s"):format(
    days, Money(t.spent, COIN_H), Money(t.net, COIN_H), Signed(math.floor(t.profit + .5)), t.avgTurn and Dur(t.avgTurn) or "-"))
  local n = #data.rows
  sheetOff = math.max(0, math.min(sheetOff, n - SROWS))
  for i = 1, SROWS do
    local row, r = srows[i], data.rows[sheetOff + i]
    ClearSheetRow(row)
    if r then
      FillSheetRow(row, r); row:Show()
    elseif i == 1 then
      row.cells.name:SetWidth(SROW_W - 20)
      row.cells.name:SetText("|cff888888No trades yet. Buy from the Exchange list or open your mailbox after sales; they show up here.|r")
      row:Show()
    else
      row:Hide()
    end
  end
  sheet.foot:SetText(("%d items | rows %d-%d | click an item for options | mouse wheel scrolls"):format(
    n, n > 0 and sheetOff + 1 or 0, math.min(n, sheetOff + SROWS)))
end

local function ShowSheetMenu(row)
  local m = sheet.menu
  m.row = row
  m.title:SetText(row.item.id and ItemLabel(row.item.id) or row.item.name)
  m:ClearAllPoints()
  m:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 40, 0)
  m:Show()
end

local function BuildSheet()
  local f = CreateFrame("Frame", "RealmExchangeSheet", frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(SHEET_W, SHEET_H)
  f:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2)
  f:SetClampedToScreen(true)
  f:SetFrameStrata("HIGH")
  ns.UI.Skin(f)
  -- opens in two moves: drops down at the Exchange width, then widens right to the full sheet width.
  -- Children sit at fixed offsets from the top left and are clipped while it grows (clipping is lifted when done,
  -- so the row menu can reach outside the sheet).
  if f.SetClipsChildren then f:SetClipsChildren(true) end
  f.curW, f.curH, f.goW, f.goH = SHEET_W, SHEET_H, SHEET_W, SHEET_H
  f:SetScript("OnUpdate", function(self, elapsed)
    if self.curW == self.goW and self.curH == self.goH then return end
    local step = SHEET_SPEED * (elapsed or 0.016)
    if self.curH < self.goH then
      self.curH = math.min(self.goH, self.curH + step)          -- move 1: down
    elseif self.curW < self.goW then
      self.curW = math.min(self.goW, self.curW + step)          -- move 2: right
    end
    self:SetSize(math.max(1, self.curW), math.max(1, self.curH))
    if self.curW == self.goW and self.curH == self.goH and self.SetClipsChildren then
      self:SetClipsChildren(false)
    end
  end)
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -9); title:SetText("Exchange Spreadsheet")
  f.sum = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.sum:SetPoint("TOPLEFT", 10, -32); f.sum:SetWidth(760); f.sum:SetJustifyH("LEFT")
  f.foot = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.foot:SetPoint("TOPLEFT", 10, -(SHEET_H - 24))
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPLEFT", SHEET_W - 28, 2)
  close:SetScript("OnClick", function() f:Hide() end)

  f.dayBtns = {}
  for i, d in ipairs({ 30, 60, 90 }) do
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(64, 20); b:SetPoint("TOPLEFT", 180 + (i - 1) * 68, -6)
    b.days = d
    b:SetScript("OnClick", function() DB.exSheetDays = d; sheetOff = 0; ns.Exchange.RefreshSheet() end)
    f.dayBtns[i] = b
  end

  for _, h in ipairs(SHEADS) do
    local col = SCOLS[h[2]]
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", 10 + col[1], -52)
    fs:SetWidth(col[2]); fs:SetJustifyH(col[3])
    fs:SetText(h[1])
  end

  for i = 1, SROWS do
    local r = CreateFrame("Button", nil, f)
    r:SetSize(SROW_W, 20)
    r:SetPoint("TOPLEFT", 10, SROW_Y0 - (i - 1) * 20)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.06 or 0.02)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 8, 0)
    r.icon:SetTexCoord(.07, .93, .07, .93)
    r.cells = {}
    for key, col in pairs(SCOLS) do r.cells[key] = Cell(r, col) end
    r:SetScript("OnEnter", function(self)
      local it = self.item
      if not it or not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if it.id then GameTooltip:SetHyperlink("item:" .. it.id) else GameTooltip:SetText(it.name) end
      GameTooltip:AddLine(" ")
      if it.bought > 0 then
        GameTooltip:AddLine(("Bought %d: %d buyouts, %d bids won"):format(it.bought, it.buyouts, it.bids), 1, 1, 1)
      end
      if it.mQty > 0 then
        GameTooltip:AddLine(("Resold %d: cost %s, received %s"):format(it.mQty, Money(math.floor(it.mCost + .5)), Money(math.floor(it.mNet + .5))), 1, 1, 1)
      end
      if it.mDays > 0 then
        GameTooltip:AddLine(("Market, %d days saved: low %s | avg %s | high %s"):format(
          it.mDays, Money(it.lo), Money(math.floor(it.avg + .5)), Money(it.hi)), .7, .7, .7)
      end
      GameTooltip:AddLine("Click for options", .5, .8, 1)
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    r:SetScript("OnClick", function(self) if self.item then ShowSheetMenu(self) end end)
    srows[i] = r
  end

  local function page(delta)
    sheetOff = sheetOff + delta
    ns.Exchange.RefreshSheet()
  end
  local nxt = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  nxt:SetSize(30, 20); nxt:SetText(">"); nxt:SetPoint("TOPLEFT", SHEET_W - 40, -(SHEET_H - 28))
  nxt:SetScript("OnClick", function() page(SROWS) end)
  local prv = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  prv:SetSize(30, 20); prv:SetText("<"); prv:SetPoint("RIGHT", nxt, "LEFT", -4, 0)
  prv:SetScript("OnClick", function() page(-SROWS) end)
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, d) page(-d * 3) end)

  local m = CreateFrame("Frame", "RealmExchangeSheetMenu", f, BackdropTemplateMixin and "BackdropTemplate" or nil)
  m:SetSize(200, 34 + #SMENU * 22)
  m:SetFrameStrata("FULLSCREEN_DIALOG"); m:SetClampedToScreen(true)
  ns.UI.Skin(m)
  m.title = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  m.title:SetPoint("TOPLEFT", 10, -8); m.title:SetWidth(180); m.title:SetJustifyH("LEFT")
  m.btns = {}
  for i, opt in ipairs(SMENU) do
    local b = CreateFrame("Button", nil, m, "UIPanelButtonTemplate")
    b:SetSize(184, 20); b:SetText(opt[1]); b:SetPoint("TOPLEFT", 8, -28 - (i - 1) * 22)
    b:SetScript("OnClick", function()
      local row = m.row
      m:Hide()
      if not (row and row.item) then return end
      if opt[3] and not row.item.id then
        Print("The game has not learned this item yet. Hover it once in your bags, then try again.")
        return
      end
      opt[2](row.item.id, row.item)
      ns.Exchange.RefreshSheet()
    end)
    m.btns[i] = b
  end
  m:Hide()
  f.menu = m
  f:Hide()
  return f
end

function ns.Exchange.ShowSheet(show, days)
  if not sheet then return end
  if days then DB.exSheetDays = days end
  if show == nil then show = not sheet:IsShown() end
  if show then
    if not sheet:IsShown() then
      sheet.curW, sheet.curH, sheet.goW, sheet.goH = EX_W, 1, SHEET_W, SHEET_H
      sheet:SetSize(EX_W, 1)
      if sheet.SetClipsChildren then sheet:SetClipsChildren(true) end
      sheet:Show()                          -- the OnUpdate in BuildSheet drops it down, then widens it
    end
  else
    sheet.curW, sheet.curH = SHEET_W, SHEET_H
    sheet:SetSize(SHEET_W, SHEET_H)
    sheet:Hide()
  end
  ns.Exchange.RefreshSheet()
end

-- ---------- ignored items window (slides out left of the Exchange window) ----------
local IROWS, ioff, irows = 12, 0, {}
local IGN_W, IGN_SPEED = 260, 900         -- width of the Ignored panel and how fast it slides out (pixels per second)

local function IgnoredIds()
  local ids = {}
  for id in pairs(DB.exIgnore or {}) do ids[#ids + 1] = id end
  table.sort(ids, function(a, b) return tostring(ItemName(a)):lower() < tostring(ItemName(b)):lower() end)
  return ids
end

function ns.Exchange.RefreshIgnored()
  if not DB then return end
  local ids = IgnoredIds()
  if frame and frame.ignBtn then frame.ignBtn:SetText(("Ignored (%d)"):format(#ids)) end
  if not ignoredWin or not ignoredWin:IsShown() then return end
  ioff = math.max(0, math.min(ioff, #ids - IROWS))
  for i = 1, IROWS do
    local r, id = irows[i], ids[ioff + i]
    if id then
      r.id = id; r.text:SetText(ItemName(id)); r:Show()
    else
      r.id = false; r:Hide()
    end
  end
  if #ids == 0 then ignoredWin.empty:Show() else ignoredWin.empty:Hide() end
  ignoredWin.foot:SetText(("%d ignored | rows %d-%d"):format(#ids, #ids > 0 and ioff + 1 or 0, math.min(#ids, ioff + IROWS)))
end

local function BuildIgnored()
  local p = CreateFrame("Frame", "RealmExchangeIgnored", frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  -- slides out of the right edge of the Exchange window (Settings uses the same edge, so they take turns).
  -- Children sit at fixed offsets from the left and are clipped while the panel widens.
  p:SetSize(IGN_W, 92 + IROWS * 20)
  p:SetPoint("TOPLEFT", frame, "TOPRIGHT", 2, 0)
  p:SetClampedToScreen(true)
  if p.SetClipsChildren then p:SetClipsChildren(true) end
  ns.UI.Skin(p)
  p.cur, p.target = 0, 0
  p:SetScript("OnUpdate", function(self, elapsed)
    if self.cur == self.target then return end
    local step = IGN_SPEED * (elapsed or 0.016)
    if self.cur < self.target then self.cur = math.min(self.target, self.cur + step)
    else self.cur = math.max(self.target, self.cur - step) end
    self:SetWidth(math.max(1, self.cur))
  end)
  local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("TOPLEFT", 10, -9); t:SetText("Ignored items")
  local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
  close:SetPoint("TOPLEFT", IGN_W - 28, 2)
  close:SetScript("OnClick", function() ns.Exchange.ShowIgnored(false) end)
  local hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 10, -30); hint:SetWidth(240); hint:SetJustifyH("LEFT")
  hint:SetText("No signals and no scanning. Restore brings an item back.")
  p.empty = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  p.empty:SetPoint("TOPLEFT", 10, -62); p.empty:SetWidth(240); p.empty:SetJustifyH("LEFT")
  p.empty:SetText("Nothing ignored. Alt-click a row in the list to ignore it.")
  p.foot = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  p.foot:SetPoint("BOTTOMLEFT", 10, 38)
  for i = 1, IROWS do
    local r = CreateFrame("Frame", nil, p)
    r:SetSize(240, 20); r:SetPoint("TOPLEFT", 10, -52 - (i - 1) * 20)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 0, 0); r.text:SetWidth(170); r.text:SetJustifyH("LEFT")
    r.del = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.del:SetSize(62, 18); r.del:SetText("Restore"); r.del:SetPoint("RIGHT", 0, 0)
    r.id = false
    r.del:SetScript("OnClick", function() if r.id then UnignoreItem(r.id) end end)
    irows[i] = r
  end
  local all = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  all:SetSize(90, 20); all:SetText("Restore all"); all:SetPoint("BOTTOMLEFT", 10, 10)
  all:SetScript("OnClick", function()
    local n = 0
    for id in pairs(DB.exIgnore or {}) do DB.exIgnore[id] = nil; n = n + 1 end
    Print(n .. " item(s) restored. The next scan will price them again.")
    Compute(); ns.Exchange.Refresh(); ns.Exchange.RefreshIgnored()
  end)
  local function page(d) ioff = ioff + d; ns.Exchange.RefreshIgnored() end
  local nxt = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  nxt:SetSize(30, 20); nxt:SetText(">"); nxt:SetPoint("BOTTOMLEFT", IGN_W - 40, 10)
  nxt:SetScript("OnClick", function() page(IROWS) end)
  local prv = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  prv:SetSize(30, 20); prv:SetText("<"); prv:SetPoint("RIGHT", nxt, "LEFT", -4, 0)
  prv:SetScript("OnClick", function() page(-IROWS) end)
  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", function(_, d) page(-d * 3) end)
  p:Hide()
  return p
end

function ns.Exchange.ShowIgnored(show)
  if not ignoredWin then return end
  if show == nil then show = not ignoredWin:IsShown() end
  if show then
    if settings and settings:IsShown() then ns.Exchange.ShowSettings(false) end     -- same edge: one at a time
    ignoredWin.cur, ignoredWin.target = 0, IGN_W
    ignoredWin:SetWidth(1)
    ignoredWin:Show()                       -- the OnUpdate above widens it to full size
  else
    ignoredWin.cur, ignoredWin.target = 0, 0
    ignoredWin:Hide()
  end
  ns.Exchange.RefreshIgnored()
end

-- ---------- settings panel (expands from the Exchange window) ----------
local function MakeEditBox(parent)
  local ok, eb = pcall(CreateFrame, "EditBox", nil, parent, "InputBoxTemplate")
  if not ok or not eb then
    eb = CreateFrame("EditBox", nil, parent)
    eb:SetFontObject("ChatFontNormal")
    local bg = eb:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(.118, .165, .22, 1)
  end
  eb:SetAutoFocus(false)
  return eb
end

-- Price limits are typed into gold / silver / copper boxes (blank = 0). 100 copper = 1 silver, 100 silver = 1 gold.
local COIN_NAMES = { "Gold", "Silver", "Copper" }
local COIN_ICON = "|TInterface\\MoneyFrame\\UI-%sIcon:12:12:0:0|t"
local function SplitCoin(c)
  c = math.floor(tonumber(c) or 0)
  return math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
end

-- Plain-language help for the "?" box, one entry per setting (worded for a five-year-old)
ns.Exchange.HELP = {
  "|cffffd100Click a row|r: I look up that item at the auction house. If it has a buy-now price I buy it. If it only takes bids, I bid. I always ask you first, so nothing is bought by accident.",
  "|cffffd100Min dip below median|r: A median is the usual price. This is how much cheaper than usual something must be before I say BUY. A big number means only huge bargains.",
  "|cffffd100Min profit per item|r: After the auction house takes its cut, this is the least money you must make on one item. A big number hides tiny wins.",
  "|cffffd100Samples before signals|r: How many times I must see a price before I trust it. Few is quick but I may guess wrong. Many is slow but sure.",
  "|cffffd100Sensitivity|r: How strange a price must look. A big number means only very strange prices count.",
  "|cffffd100Hold back inflated prices|r: Sometimes one seller lists an item for far too much, and that one price would fool me. When the lowest price is way above the usual, I leave it out of my notes. I let it in again when several sellers agree on it, or when it stays that high for a couple of hours. Type /realm ex held to see what I am holding back.",
  "|cffffd100Inflated = times the median|r: How many times bigger than usual a price must be before I call it too high. 2.0 means twice the usual price.",
  "|cffffd100Auto-scan|r: I look at the whole market for you each time you open the auction house.",
  "|cffffd100Include weapons and armor|r: Also check gear. Gear prices jump around a lot, so this starts OFF.",
  "|cffffd100Dock beside auction house|r: Sticks this window next to the auction house so it follows it.",
  "|cffffd100Price range|r: Turns on a minimum price too. Then you only see items between your min and your max.",
  "|cffffd100Max price|r: The most you want to pay for one item. Gold, silver and copper boxes. Leave them empty for no limit.",
  "|cffffd100Min price|r: The least price you want to look at. It only works while Price range is ON.",
  "|cffffd100Tracked items|r: Items you always want me to watch. Shift-click an item into the box and press Enter. Press x to stop.",
  "|cffffd100Ignored items|r: Alt-click a row (or use the click menu on the spreadsheet) and I stop showing and scanning that item. The Ignored button at the top keeps the list. Press Restore next to an item and it comes back on the next scan.",
  "|cffffd100Spreadsheet|r: The Spreadsheet button opens a table of what you bought and sold. Pick 30, 60 or 90 days. It shows what you paid, what the item costs now, how long it took to sell, and how much you made. Click an item for choices: buy it, search for it, track it, or share it. I only learn from today on, so the table fills up over time. Sales are read from your auction mail when you open the mailbox.",
}

local function BuildSettings()
  local p = CreateFrame("Frame", "RealmExchangeSettings", frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  p:SetSize(280, 646)
  p:SetPoint("TOPLEFT", frame, "TOPRIGHT", 2, 0)
  p:SetClampedToScreen(true)
  ns.UI.Skin(p)
  local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("TOPLEFT", 10, -9); t:SetText("Exchange Settings")

  -- "?" box: every setting in plain words
  local hp = CreateFrame("Frame", nil, p, BackdropTemplateMixin and "BackdropTemplate" or nil)
  hp:SetSize(310, 700)
  hp:SetPoint("TOPLEFT", p, "TOPRIGHT", 2, 0)
  ns.UI.Skin(hp)
  local hh = hp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  hh:SetPoint("TOPLEFT", 10, -9); hh:SetText("What does this all mean?")
  local ht = hp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ht:SetPoint("TOPLEFT", 10, -30); ht:SetWidth(290); ht:SetJustifyH("LEFT"); ht:SetJustifyV("TOP")
  ht:SetText(table.concat(ns.Exchange.HELP, "\n\n"))
  hp:Hide()
  p.help = hp
  local q = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  q:SetSize(24, 20); q:SetText("?"); q:SetPoint("TOPRIGHT", -8, -6)
  q:SetScript("OnClick", function() if hp:IsShown() then hp:Hide() else hp:Show() end end)

  p.vals, p.toggles, p.coinboxes = {}, {}, {}
  local y = -34

  local function Stepper(label, key, step, lo, hi, fmt, scale)
    local fs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 10, y - 4); fs:SetText(label)
    local minus = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    minus:SetSize(22, 20); minus:SetText("-"); minus:SetPoint("TOPLEFT", 170, y)
    local val = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    val:SetPoint("LEFT", minus, "RIGHT", 4, 0); val:SetWidth(44)
    local plus = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    plus:SetSize(22, 20); plus:SetText("+"); plus:SetPoint("LEFT", val, "RIGHT", 4, 0)
    local function change(d)
      local v = (DB[key] / scale) + d * step
      v = math.max(lo, math.min(hi, v))
      DB[key] = math.floor(v / step + .5) * step * scale
      Compute(); ns.Exchange.Refresh(); RefreshSettings()
    end
    minus:SetScript("OnClick", function() change(-1) end)
    plus:SetScript("OnClick", function() change(1) end)
    p.vals[#p.vals + 1] = { val, key, fmt, scale }
    y = y - 26
  end
  Stepper("Min dip below median (%)", "exMinDisc", 1, 3, 60, "%d", .01)
  Stepper("Min profit per item (silver)", "exMinProfit", 5, 0, 1000, "%d", 100)
  Stepper("Samples before signals", "exMinSamples", 1, 3, 30, "%d", 1)
  Stepper("Sensitivity (z-score)", "exMinZ", .5, .5, 5, "%.1f", 1)
  Stepper("Inflated = times the median", "exOutlier", .5, 1.5, 6, "%.1f", 1)

  local function Toggle(label, key)
    local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    b:SetSize(260, 22); b:SetPoint("TOPLEFT", 10, y)
    b:SetScript("OnClick", function()
      DB[key] = not DB[key]
      if key == "exGear" or key == "exRange" then Compute(); ns.Exchange.Refresh() end
      if key == "exDock" then Dock() end
      RefreshSettings()
    end)
    p.toggles[#p.toggles + 1] = { b, key, label }
    y = y - 26
  end
  Toggle("Auto-scan when AH opens", "exAuto")
  Toggle("Hold back inflated prices", "exSmart")
  Toggle("Include weapons and armor", "exGear")
  Toggle("Dock beside auction house", "exDock")
  Toggle("Price range (min to max)", "exRange")

  -- Price limits: three boxes (gold, silver, copper) with the coin icon after each; Enter or clicking away applies
  local function CoinBoxes(label, key)
    local fs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 10, y - 2)
    fs:SetText(label)
    local boxes, widths, x = {}, { 70, 34, 34 }, 14
    local function commit()
      if p.syncing or p.escaping then return end
      local g, s, c = tonumber(boxes[1]:GetText()) or 0, tonumber(boxes[2]:GetText()) or 0, tonumber(boxes[3]:GetText()) or 0
      DB[key] = math.floor(g * 10000 + s * 100 + c)
      Compute(); ns.Exchange.Refresh(); RefreshSettings()
    end
    for i = 1, 3 do
      local eb = MakeEditBox(p)
      eb:SetSize(widths[i], 20); eb:SetPoint("TOPLEFT", x, y - 20)
      eb:SetNumeric(true)
      eb:SetMaxLetters(i == 1 and 6 or 2)
      eb:SetJustifyH("RIGHT")
      eb:SetScript("OnEnterPressed", function(self) self:ClearFocus(); commit() end)
      eb:SetScript("OnEditFocusLost", commit)
      eb:SetScript("OnEscapePressed", function(self)
        p.escaping = true; self:ClearFocus(); p.escaping = false
        RefreshSettings()
      end)
      local ic = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      ic:SetPoint("LEFT", eb, "RIGHT", 4, 0)
      ic:SetText(COIN_ICON:format(COIN_NAMES[i]))
      boxes[i] = eb
      x = x + widths[i] + 24
    end
    p.coinboxes[#p.coinboxes + 1] = { boxes, key }
    y = y - 46
  end
  CoinBoxes("Max price to spend per item (blank = no limit)", "exMaxPrice")
  CoinBoxes("Min price per item (used when Price range is ON)", "exMinPrice")

  y = y - 8
  local h = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  h:SetPoint("TOPLEFT", 10, y); h:SetText("Tracked items")
  y = y - 20
  local hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 10, y); hint:SetText("Click the box, shift-click an item, press Enter")
  y = y - 16
  local eb = MakeEditBox(p)
  eb:SetSize(190, 20); eb:SetPoint("TOPLEFT", 14, y)
  local function submit()
    local id = ParseItem(eb:GetText())
    if id then AddWatch(id); eb:SetText("") else Print("Couldn't read an item from that. Shift-click an item or type its ID.") end
    eb:ClearFocus()
  end
  eb:SetScript("OnEnterPressed", submit)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  p.edit = eb
  local add = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  add:SetSize(56, 20); add:SetText("Add"); add:SetPoint("LEFT", eb, "RIGHT", 8, 0)
  add:SetScript("OnClick", submit)
  y = y - 28

  p.wrows = {}
  for i = 1, 10 do
    local r = CreateFrame("Frame", nil, p)
    r:SetSize(260, 18); r:SetPoint("TOPLEFT", 10, y - (i - 1) * 18)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 0, 0)
    r.del = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.del:SetSize(20, 16); r.del:SetText("x"); r.del:SetPoint("RIGHT", 0, 0)
    r.id = false
    r.del:SetScript("OnClick", function() if r.id then RemoveWatch(r.id) end end)
    p.wrows[i] = r
  end
  p:Hide()
  return p
end

function RefreshSettings()
  if not settings or not settings:IsShown() then return end
  for _, v in ipairs(settings.vals) do
    local val, key, fmt, scale = v[1], v[2], v[3], v[4]
    val:SetText(fmt:format(DB[key] / scale))
  end
  for _, t in ipairs(settings.toggles) do
    t[1]:SetText(t[3] .. ": " .. (DB[t[2]] and "|cff33ff66ON|r" or "|cffff4040OFF|r"))
  end
  settings.syncing = true
  for _, cb in ipairs(settings.coinboxes) do
    local boxes, key = cb[1], cb[2]
    local parts = { SplitCoin(DB[key]) }
    local active = key == "exMaxPrice" or DB.exRange
    for i = 1, 3 do
      if not boxes[i]:HasFocus() then boxes[i]:SetText(parts[i] > 0 and tostring(parts[i]) or "") end
      boxes[i]:SetAlpha(active and 1 or 0.4)
    end
  end
  settings.syncing = false
  local ids = {}
  for id in pairs(DB.exWatch) do ids[#ids + 1] = id end
  table.sort(ids)
  for i, r in ipairs(settings.wrows) do
    local id = ids[i]
    if id then
      r.id = id; r.text:SetText(ItemName(id)); r:Show()
    else
      r.id = false; r:Hide()
    end
  end
end

function ns.Exchange.ShowSettings(show)
  if not settings then return end
  if show == nil then show = not settings:IsShown() end
  if show and ignoredWin and ignoredWin:IsShown() then ns.Exchange.ShowIgnored(false) end   -- same edge: one at a time
  settings:SetShown(show)
  RefreshSettings()
end

-- Button on the auction house window + docking
local hooked = {}

local function UpdateTab()
  if ahButton then ahButton:SetText((frame and frame:IsShown()) and "<" or ">") end
end

-- Roll the Exchange out from (or back into) the auction house's right edge.
local function Roll(out)
  if not frame then return end
  if out then
    if not frame:IsShown() then
      slide.p, slide.off = 0, SLIDE_PX
      frame:SetAlpha(0); frame:Show(); Compute(); ns.Exchange.Refresh()
    end
    slide.dir = 1; rolledOut = true
  else
    slide.dir = -1
  end
  Dock(); UpdateTab()
end

function ns.Exchange.CloseWithAH()
  slide.dir, slide.p, slide.off = 0, 0, 0
  if frame then
    frame:SetAlpha(1)
    if rolledOut and frame:IsShown() then frame:Hide() end
  end
  rolledOut = false
  UpdateTab()
end

local function HookTarget(t)
  if t and not hooked[t] then
    hooked[t] = true
    pcall(function() t:HookScript("OnShow", function() C_Timer.After(0, Dock) end) end)
    pcall(function() t:HookScript("OnHide", function() ns.Exchange.CloseWithAH() end) end)
  end
end

local function AttachAHButton()
  HookTarget(AuctionHouseFrame); HookTarget(AuctionFrame)
  local target = AHTarget()
  if not target then return end
  if not ahButton then
    ahButton = CreateFrame("Button", "RealmExchangeAHButton", target, "UIPanelButtonTemplate")
    ahButton:SetSize(110, 22); ahButton:SetText(">")
    ahButton:SetScript("OnClick", function()
      Roll(not (frame:IsShown() and slide.dir >= 0))
    end)
    ahButton:SetScript("OnEnter", function(self)
      if not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText("Realm Exchange")
      GameTooltip:AddLine("Click to roll out or tuck away.", 1, 1, 1)
      GameTooltip:Show()
    end)
    ahButton:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    if ns.UI and ns.UI.Modern then ns.UI.Modern(ahButton) end
    pcall(function()
      frame:HookScript("OnShow", UpdateTab)
      frame:HookScript("OnHide", UpdateTab)
    end)
  end
  if ahButton:GetParent() ~= target then ahButton:SetParent(target) end
  ahButton:ClearAllPoints()
  ahButton:SetPoint("TOPRIGHT", target, "BOTTOMRIGHT", -8, 2)   -- below the window: the bottom-right corner is the Buyout button
  ahButton:SetFrameLevel((target:GetFrameLevel() or 1) + 20)
  ahButton:Show()
  UpdateTab()
end

-- ---------- demo ----------
local DEMO_IDS = { 2589, 2592, 2318, 2770, 2771, 2772, 2447, 765, 785, 118, 3820, 2835, 4306, 4338, 2453, 2450 }
local function MakeDemo()
  demoStore = {}
  local now = time()
  math.randomseed(now)
  for k, id in ipairs(DEMO_IDS) do
    local base = 200 + math.random(100, 4000)
    local it = { t = {}, p = {}, q = {}, seen = now }
    for i = 1, 24 do
      it.t[i] = now - (24 - i + 1) * 3600 * 4
      it.p[i] = math.floor(base * (1 + (math.random() - .5) * .08))
      it.q[i] = math.random(20, 400)
    end
    if k % 4 == 1 then it.p[24] = math.floor(base * .65)                  -- sudden dip: BUY
    elseif k % 4 == 2 then                                                -- falling knife: WATCH
      it.p[21], it.p[22], it.p[23], it.p[24] = base * .95, base * .85, base * .75, base * .6
    elseif k % 4 == 3 then it.p[24] = math.floor(base * 1.3) end         -- spike: SELL if in bags
    demoStore[id] = it
  end
end

-- ---------- commands ----------
function ns.Exchange.Command(arg)
  arg = arg or ""
  local cmd, val = arg:match("^(%S*)%s*(%S*)")
  arg = arg or ""
  if cmd == "scan" then
    StartScan()
  elseif cmd == "clear" then
    for k in pairs(live) do live[k] = nil end
    Compute(); ns.Exchange.Refresh()
    Print("Price history cleared for this realm.")
  elseif cmd == "min" then
    local v = tonumber(val)
    if v and v > 0 and v < 100 then DB.exMinDisc = v / 100; Print("Minimum dip: " .. v .. "%") else Print("Usage: /realm ex min 15") end
    Compute(); ns.Exchange.Refresh(); RefreshSettings()
  elseif cmd == "profit" then
    local v = tonumber(val)
    if v then DB.exMinProfit = v * 100; Print("Minimum profit per item: " .. v .. " silver") else Print("Usage: /realm ex profit 10 (silver)") end
    Compute(); ns.Exchange.Refresh()
  elseif cmd == "auto" then
    DB.exAuto = not DB.exAuto
    Print("Auto-scan on opening the AH: " .. (DB.exAuto and "on" or "off"))

  elseif cmd == "smart" then
    DB.exSmart = not DB.exSmart
    Print("Hold back inflated prices: " .. (DB.exSmart and "on" or "off"))
    RefreshSettings()
  elseif cmd == "outlier" then
    local v = tonumber(val)
    if v and v >= 1.5 and v <= 6 then
      DB.exOutlier = v; Print(("A price %.1f times the median or more counts as inflated."):format(v)); RefreshSettings()
    else Print("Usage: /realm ex outlier 2 (between 1.5 and 6)") end
  elseif cmd == "held" then
    if #heldIds == 0 then Print("Nothing is held back from the last scan.") end
    for i = 1, math.min(10, #heldIds) do
      local id = heldIds[i]
      local it = store[id]
      Print(("%s: %s asked, usually %s (held for %d scan%s)"):format(ItemName(id), Money(math.floor(it.heldPrice or 0)),
        Money(math.floor(median(it.p))), it.held or 1, (it.held or 1) == 1 and "" or "s"))
    end
    if #heldIds > 10 then Print(("...and %d more."):format(#heldIds - 10)) end
  elseif cmd == "gear" then
    DB.exGear = not DB.exGear
    Print("Track weapons/armor: " .. (DB.exGear and "on (noisy)" or "off"))
  elseif cmd == "demo" then
    if val == "off" then store = live else MakeDemo(); store = demoStore end
    Compute()
    if frame then frame:Show() end
    ns.Exchange.Refresh()
  elseif cmd == "debug" then
    local C = C_AuctionHouse
    Print("C_AuctionHouse: " .. tostring(C ~= nil) .. "  ReplicateItems: " .. tostring(C and C.ReplicateItems ~= nil))
    Print("Replicate items loaded: " .. tostring(C and C.GetNumReplicateItems and C.GetNumReplicateItems() or "n/a"))
    Print("QueryAuctionItems: " .. tostring(QueryAuctionItems ~= nil) .. "  scanning: " .. tostring(scan ~= nil))
    Print("Tracked items: " .. tostring(results.tracked) .. "  last scan: " .. tostring(lastScan))
  elseif cmd == "track" then
    local id = ParseItem(arg:match("^%S*%s*(.*)$"))
    if id then AddWatch(id) else Print("Usage: /realm ex track <shift-click an item or ID>") end
  elseif cmd == "untrack" then
    local id = ParseItem(arg:match("^%S*%s*(.*)$"))
    if id then RemoveWatch(id) else Print("Usage: /realm ex untrack <item or ID>") end
  elseif cmd == "ignore" then
    local id = ParseItem(arg:match("^%S*%s*(.*)$"))
    if id then IgnoreItem(id) else Print("Usage: /realm ex ignore <shift-click an item or ID>") end
  elseif cmd == "unignore" then
    local id = ParseItem(arg:match("^%S*%s*(.*)$"))
    if id then UnignoreItem(id) else Print("Usage: /realm ex unignore <item or ID>") end
  elseif cmd == "ignored" then
    if not frame:IsShown() then frame:Show(); Compute(); ns.Exchange.Refresh() end
    ns.Exchange.ShowIgnored(true)
  elseif cmd == "dock" then
    DB.exDock = true
    if not frame:IsShown() then frame:Show(); Compute(); ns.Exchange.Refresh() end
    if AHTarget() then Dock(); Print("Docked beside the auction house.")
    else Print("Open the auction house first, then run /realm ex dock.") end
  elseif cmd == "sheet" or cmd == "spreadsheet" then
    if not frame:IsShown() then frame:Show(); Compute(); ns.Exchange.Refresh() end
    local d = tonumber(val)
    ns.Exchange.ShowSheet(true, (d == 30 or d == 60 or d == 90) and d or nil)
  elseif cmd == "settings" then
    if not frame:IsShown() then frame:Show(); Compute(); ns.Exchange.Refresh() end
    ns.Exchange.ShowSettings(true)
  elseif cmd == "help" then
    Print("/realm ex | settings | track <item> | untrack <item> | ignore <item> | unignore <item> | ignored | scan | debug | min <pct> | profit <silver> | auto | smart | outlier <x> | held | gear | clear | demo [off]")
  else
    if not frame then return end
    if frame:IsShown() then frame:Hide() else frame:Show(); Compute(); ns.Exchange.Refresh() end
  end
end

-- ---------- events ----------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "REPLICATE_ITEM_LIST_UPDATE", "AUCTION_ITEM_LIST_UPDATE",
                     "ITEM_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_PRICE_UPDATED",
                     "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "MAIL_SHOW", "MAIL_INBOX_UPDATE" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a1, a2)
  BuyEvent(event, a1, a2)
  if event == "PLAYER_LOGIN" then
    DB = ns.DB
    for k, v in pairs(DEFAULTS) do if DB[k] == nil then DB[k] = v end end
    DB.exWatch = DB.exWatch or {}
    DB.exIgnore = DB.exIgnore or {}
    DB.ex = DB.ex or {}
    local key = RealmKey()
    DB.ex[key] = DB.ex[key] or {}
    DB.exLedger = DB.exLedger or {}
    DB.exLedger[key] = DB.exLedger[key] or {}
    ledger = DB.exLedger[key]
    ledger.buys, ledger.sells = ledger.buys or {}, ledger.sells or {}
    DB.exHist = DB.exHist or {}
    DB.exHist[key] = DB.exHist[key] or {}
    hist = DB.exHist[key]
    for _, e in ipairs(ledger.buys) do if e.id then traded[e.id] = true end end
    for _, e in ipairs(ledger.sells) do if e.id then traded[e.id] = true end end
    live = DB.ex[key]
    store = live
    lastScan = DB.exLastScan or 0
    frame = Build()
    settings = BuildSettings()
    sheet = BuildSheet()
    ignoredWin = BuildIgnored()
    ns.Exchange.RefreshIgnored()
    pcall(hooksecurefunc, "ChatEdit_InsertLink", function(text)
      if settings.edit and settings.edit:HasFocus() then settings.edit:Insert(text) end
    end)
    Compute()
  elseif event == "AUCTION_HOUSE_SHOW" then
    for _, delay in ipairs({ 0.1, 0.6, 1.5 }) do
      C_Timer.After(delay, function() AttachAHButton(); Dock() end)
    end
    if DB.exAuto and time() - lastScan > 900 then StartScan() end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    ns.Exchange.CloseWithAH()
  elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
    OnReplicate()
  elseif event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then
    if ScanInvoices() > 0 then ns.Exchange.RefreshSheet() end
  elseif event == "AUCTION_ITEM_LIST_UPDATE" then
    OnClassicList()
  end
end)

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, el)
  if scan and scan.get then ProcessChunk() end
  if slide.dir ~= 0 and frame then
    slide.p = slide.p + slide.dir * (el or 0.02) / SLIDE_SECS
    if slide.p >= 1 then slide.p, slide.dir = 1, 0
    elseif slide.p <= 0 then slide.p, slide.dir = 0, 0; frame:Hide(); rolledOut = false end
    slide.off = SLIDE_PX * (1 - slide.p)
    frame:SetAlpha(slide.dir == 0 and slide.p == 0 and 1 or slide.p)
    Dock()
  end
end)

-- test hooks
ns.Exchange._Record, ns.Exchange._Compute, ns.Exchange._Analyze = Record, Compute, Analyze
ns.Exchange._BuyItem, ns.Exchange._BuyEvent = BuyItem, BuyEvent
ns.Exchange._LedgerBuy, ns.Exchange._LedgerSale, ns.Exchange._ScanInvoices = LedgerBuy, LedgerSale, ScanInvoices
ns.Exchange._RecordDaily = RecordDaily
ns.Exchange._HoldBack = HoldBack
ns.Exchange._Held = function() return heldIds end
ns.Exchange._Ignore, ns.Exchange._Unignore = IgnoreItem, UnignoreItem
ns.Exchange._Ledger = function() return ledger, hist end
