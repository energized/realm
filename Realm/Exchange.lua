-- Realm Exchange: treat the auction house like a stock market.
-- Records price history per item, finds dips below the recent norm, flags sell-highs in your bags.
local ADDON, ns = ...

local TAX = 0.95                 -- AH cut
local MAXITEMS, MAXSAMPLES = 3000, 48
local MIN_GAP, MAX_AGE = 1800, 14 * 86400   -- one sample per 30 min, keep 14 days
local CHUNK = 1500               -- listings processed per frame during a scan
local ROWS = 16
local MIN_STOCK_PRICE, MIN_STOCK_QTY = 100, 5

ns.Exchange = {}
local DEFAULTS = { exAuto = true, exGear = false, exDock = true, exMinDisc = 0.15,
                   exMinProfit = 1000, exMinSamples = 8, exMinZ = 2 }
local DB, store, demoStore, live
local settings, ahButton
local frame, rows = nil, {}
local scan = nil                 -- active scan state
local lastScan = 0
local results = { buys = {}, sells = {}, watch = {}, index = nil, tracked = 0 }

-- ---------- helpers ----------
local function Money(c) return GetCoinTextureString and GetCoinTextureString(math.floor(c)) or (math.floor(c) .. "c") end
local function Print(m) ns.Print(m) end

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
  local function Qualifies(a)
    return a.disc >= minDisc and a.z >= minZ and a.n >= minN and a.net >= minProfit
  end
  for id, it in pairs(store) do
    tracked = tracked + 1
    local a = Analyze(it, 3)
    if a then
      a.id = id
      if a.n >= minN then ratioSum = ratioSum + a.cur / a.med; ratioN = ratioN + 1 end
      if Qualifies(a) then
        if a.falling then watch[#watch + 1] = a
        else
          a.score = a.net * math.sqrt(math.min(a.qty, 50))
          buys[#buys + 1] = a
        end
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
              index = ratioN > 0 and (ratioSum / ratioN - 1) * 100 or nil }
  return results
end

-- ---------- scanning ----------
local function Finish()
  local now = time()
  for id, a in pairs(scan.agg) do Record(id, a.price, a.qty, now) end
  Prune(now)
  lastScan = now
  DB.exLastScan = now
  Print(("Scan complete: %d items priced."):format(scan.items))
  scan = nil
  Compute()
  ns.Exchange.Refresh()
end

local function ProcessChunk()
  if not scan then return end
  local stop = math.min(scan.i + CHUNK - 1, scan.total)
  for i = scan.i, stop do
    local count, buy, id = scan.get(i)
    if id and buy and buy > 0 and count and count > 0 then
      local cls = ItemClass(id)
      if DB.exGear or DB.exWatch[id] or not (cls == 2 or cls == 4) then
        local unit = buy / count
        local a = scan.agg[id]
        if not a then
          a = { price = unit, qty = 0 }
          scan.agg[id] = a
          scan.items = scan.items + 1
        end
        if unit < a.price then a.price = unit end
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

local function AddWatch(id)
  DB.exWatch[id] = true
  Print("Tracking " .. ItemName(id) .. ". It is recorded on every scan from now on.")
  Compute(); ns.Exchange.Refresh(); RefreshSettings()
end
local function RemoveWatch(id)
  DB.exWatch[id] = nil
  Print("Stopped tracking " .. ItemName(id))
  Compute(); ns.Exchange.Refresh(); RefreshSettings()
end

local function SearchAH(id)
  local name = GetItemInfo and GetItemInfo(id)
  if not name then Print("Item not cached yet; hover it once, then click again.") return end
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

local function Dock()
  local target = AHTarget()
  if DB and DB.exDock and frame and target then
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", target, "TOPRIGHT", 6, 0)
  end
end

local function Build()
  local f = CreateFrame("Frame", "RealmExchange", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(450, 60 + ROWS * 20 + 34)
  f:SetPoint("CENTER", 200, 0)
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

  local scanBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  scanBtn:SetSize(70, 20); scanBtn:SetText("Scan")
  scanBtn:SetPoint("BOTTOMRIGHT", -10, 8)
  scanBtn:SetScript("OnClick", StartScan)

  local setBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  setBtn:SetSize(80, 20); setBtn:SetText("Settings >")
  setBtn:SetPoint("RIGHT", scanBtn, "LEFT", -6, 0)
  setBtn:SetScript("OnClick", function() ns.Exchange.ShowSettings() end)

  for i = 1, ROWS do
    local r = CreateFrame("Button", nil, f)
    r:SetSize(430, 20)
    r:SetPoint("TOPLEFT", 10, -50 - (i - 1) * 20)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.a = false
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 0, 0)
    r.text:SetJustifyH("LEFT")
    r:SetScript("OnEnter", function(self)
      if not self.a or not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink("item:" .. self.a.id)
      GameTooltip:AddLine(" ")
      if not self.a.nodata then
        GameTooltip:AddLine(("Now %s  |  median %s"):format(Money(self.a.cur), Money(self.a.med)), 1, 1, 1)
        GameTooltip:AddLine(("%d samples  |  %d on market  |  z-score %.1f"):format(self.a.n, self.a.qty, self.a.z), .7, .7, .7)
      end
      GameTooltip:AddLine("Click: search AH   Shift-click: link   Right-click: track/untrack", .5, .8, 1)
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    r:SetScript("OnClick", function(self, button)
      if not self.a then return end
      local id = self.a.id
      if button == "RightButton" then
        if DB.exWatch[id] then RemoveWatch(id) else AddWatch(id) end
      elseif IsShiftKeyDown() and ChatEdit_InsertLink then
        local _, link = GetItemInfo(id)
        if link then ChatEdit_InsertLink(link) end
      else
        SearchAH(id)
      end
    end)
    rows[i] = r
  end
  f:Hide()
  return f
end

local function RowText(sig, a)
  local c = SIGCOLOR[sig]
  if sig == "TRACK" then
    if a.nodata then
      return ("|c%sTRACK|r %s  |cff888888no data yet, scan the AH|r"):format(c, ItemName(a.id))
    end
    local delta = math.floor((a.cur / a.med - 1) * 100)
    local tag = a.tag == "BUY" and "|cff33ff66BUY|r" or a.tag == "WATCH" and "|cffaaaaaaWATCH (falling)|r"
      or a.tag == "SELL" and "|cffff9933SELL|r" or a.tag == "LEARN"
      and ("|cff888888learning %d/%d|r"):format(a.n, DB.exMinSamples) or "|cff888888hold|r"
    return ("|c%sTRACK|r %s  %s  %+d%%  %s"):format(c, ItemName(a.id), Money(a.cur), delta, tag)
  elseif sig == "SELL" then
    return ("|c%s%-5s|r %s x%d  %s  |cffff9933+%d%%|r vs median"):format(c, sig, ItemName(a.id), a.owned, Money(a.cur), math.floor((a.cur / a.med - 1) * 100))
  end
  return ("|c%s%-5s|r %s  %s  |cff33ff66-%d%%|r  profit ~%s"):format(c, sig, ItemName(a.id), Money(a.cur), math.floor(a.disc * 100), Money(a.net))
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
  add("WATCH", res.watch, 2)
  for i = 1, ROWS do
    local row, e = rows[i], list[i]
    if e then
      row.a = e[2]
      row.text:SetText(RowText(e[1], e[2]))
      row:Show()
    else
      row.a = false; row:Hide()
    end
  end
  if #list == 0 then
    rows[1].text:SetText("|cff888888No dips right now. Scan again later; right-click any item to track it.|r")
    rows[1]:Show()
  end
  local ago = lastScan > 0 and math.floor((time() - lastScan) / 60) .. " min ago" or "never"
  frame.foot:SetText(("%d items | scan %s | /realm ex help"):format(res.tracked, ago))
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

local function BuildSettings()
  local p = CreateFrame("Frame", "RealmExchangeSettings", frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  p:SetSize(280, 470)
  p:SetPoint("TOPLEFT", frame, "TOPRIGHT", 2, 0)
  p:SetClampedToScreen(true)
  ns.UI.Skin(p)
  local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("TOPLEFT", 10, -9); t:SetText("Exchange Settings")

  p.vals, p.toggles = {}, {}
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

  local function Toggle(label, key)
    local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    b:SetSize(260, 22); b:SetPoint("TOPLEFT", 10, y)
    b:SetScript("OnClick", function()
      DB[key] = not DB[key]
      if key == "exGear" then Compute(); ns.Exchange.Refresh() end
      if key == "exDock" then Dock() end
      RefreshSettings()
    end)
    p.toggles[#p.toggles + 1] = { b, key, label }
    y = y - 26
  end
  Toggle("Auto-scan when AH opens", "exAuto")
  Toggle("Include weapons and armor", "exGear")
  Toggle("Dock beside auction house", "exDock")

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
  settings:SetShown(show)
  RefreshSettings()
end

-- Button on the auction house window + docking
local hooked = {}
local function HookTarget(t)
  if t and not hooked[t] then
    hooked[t] = true
    pcall(function() t:HookScript("OnShow", function() C_Timer.After(0, Dock) end) end)
  end
end

local function AttachAHButton()
  HookTarget(AuctionHouseFrame); HookTarget(AuctionFrame)
  local target = AHTarget()
  if not target then return end
  if not ahButton then
    ahButton = CreateFrame("Button", "RealmExchangeAHButton", target, "UIPanelButtonTemplate")
    ahButton:SetSize(84, 20); ahButton:SetText("Exchange")
    ahButton:SetScript("OnClick", function()
      if frame:IsShown() then frame:Hide()
      else frame:Show(); Compute(); ns.Exchange.Refresh() end
    end)
  end
  if ahButton:GetParent() ~= target then ahButton:SetParent(target) end
  ahButton:ClearAllPoints()
  ahButton:SetPoint("TOPRIGHT", target, "TOPRIGHT", -40, -4)
  ahButton:Show()
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
  elseif cmd == "dock" then
    DB.exDock = true
    if not frame:IsShown() then frame:Show(); Compute(); ns.Exchange.Refresh() end
    if AHTarget() then Dock(); Print("Docked beside the auction house.")
    else Print("Open the auction house first, then run /realm ex dock.") end
  elseif cmd == "settings" then
    if not frame:IsShown() then frame:Show(); Compute(); ns.Exchange.Refresh() end
    ns.Exchange.ShowSettings(true)
  elseif cmd == "help" then
    Print("/realm ex | settings | track <item> | untrack <item> | scan | debug | min <pct> | profit <silver> | auto | gear | clear | demo [off]")
  else
    if not frame then return end
    if frame:IsShown() then frame:Hide() else frame:Show(); Compute(); ns.Exchange.Refresh() end
  end
end

-- ---------- events ----------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "REPLICATE_ITEM_LIST_UPDATE", "AUCTION_ITEM_LIST_UPDATE" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    DB = ns.DB
    for k, v in pairs(DEFAULTS) do if DB[k] == nil then DB[k] = v end end
    DB.exWatch = DB.exWatch or {}
    DB.ex = DB.ex or {}
    local key = RealmKey()
    DB.ex[key] = DB.ex[key] or {}
    live = DB.ex[key]
    store = live
    lastScan = DB.exLastScan or 0
    frame = Build()
    settings = BuildSettings()
    pcall(hooksecurefunc, "ChatEdit_InsertLink", function(text)
      if settings.edit and settings.edit:HasFocus() then settings.edit:Insert(text) end
    end)
    Compute()
  elseif event == "AUCTION_HOUSE_SHOW" then
    for _, delay in ipairs({ 0.1, 0.6, 1.5 }) do
      C_Timer.After(delay, function() AttachAHButton(); Dock() end)
    end
    if DB.exAuto and time() - lastScan > 900 then StartScan() end
  elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
    OnReplicate()
  elseif event == "AUCTION_ITEM_LIST_UPDATE" then
    OnClassicList()
  end
end)

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function() if scan and scan.get then ProcessChunk() end end)

-- test hooks
ns.Exchange._Record, ns.Exchange._Compute, ns.Exchange._Analyze = Record, Compute, Analyze
