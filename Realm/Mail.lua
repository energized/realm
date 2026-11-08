-- Realm Mail ("EMF" - Exchange Mail Features): collect everything from the mailbox, delete a mail only after the
-- game confirms it is empty, and keep a running tally of what the Auction House paid you and returned to you.
-- Never pays COD, never deletes a mail that still holds items or money, never deletes a letter a player wrote.
local ADDON, ns = ...
local Mail = {}
ns.Mail = Mail

local DB, T
local frame
local run = nil            -- active collection state

local function Print(m) if ns.Print then ns.Print("Mail: " .. m) end end
local function Money(c) return GetCoinTextureString and GetCoinTextureString(math.floor(c or 0)) or tostring(c or 0) end

-- ------------------------------------------------------------ auction mail classification (pure, unit tested)
local function Pat(fmt, fallback)
  local s = (type(fmt) == "string" and fmt ~= "") and fmt or fallback
  s = s:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")   -- escape magic characters
  s = s:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
  return "^" .. s .. "$"
end

local PATS
local function Pats()
  if PATS then return PATS end
  PATS = {
    sold = Pat(_G.AUCTION_SOLD_MAIL_SUBJECT, "Auction successful: %s"),
    won = Pat(_G.AUCTION_WON_MAIL_SUBJECT, "Auction won: %s"),
    outbid = Pat(_G.AUCTION_OUTBID_MAIL_SUBJECT, "Outbid on %s"),
    expired = Pat(_G.AUCTION_EXPIRED_MAIL_SUBJECT, "Auction expired: %s"),
    cancelled = Pat(_G.AUCTION_REMOVED_MAIL_SUBJECT, "Auction cancelled: %s"),
  }
  return PATS
end
function Mail._ResetPats() PATS = nil end

-- returns kind ("sold", "won", "outbid", "expired", "cancelled") and the item name, or nil for ordinary mail
function Mail.Classify(subject)
  if type(subject) ~= "string" then return nil end
  for kind, pat in pairs(Pats()) do
    local name = subject:match(pat)
    if name then return kind, name end
  end
end

-- ------------------------------------------------------------ the tally
local function NewTally()
  return { since = time and time() or 0, money = 0, items = 0,
           sold = 0, soldCount = 0, won = 0, outbid = 0, returned = 0, returnedItems = {}, wonItems = {}, deleted = 0,
           soldItems = {}, bestDay = 0, bestDayKey = false, bestSale = 0, bestSaleName = false, daysActive = 0, lastDay = false }
end

-- tallies saved by an older build lack the newer stat fields; fill them in without touching the old numbers
local function Fix(t)
  t.soldItems = t.soldItems or {}
  t.returnedItems = t.returnedItems or {}
  t.wonItems = t.wonItems or {}
  t.bestDay = t.bestDay or 0
  t.bestSale = t.bestSale or 0
  t.daysActive = t.daysActive or 0
  if t.bestDayKey == nil then t.bestDayKey = false end
  if t.bestSaleName == nil then t.bestSaleName = false end
  if t.lastDay == nil then t.lastDay = false end
  return t
end

function Mail.Tally() return T end

-- ------------------------------------------------------------ per-day records (today / yesterday / last week)
local KEEP_DAYS = 35
local function DayKey(t) return date and date("%Y-%m-%d", t or time()) or "0000-00-00" end
-- days are counted from local noon so a daylight-saving change never skips or repeats a date
local function KeyAgo(n)
  local d = date("*t"); d.hour, d.min, d.sec = 12, 0, 0
  return DayKey(time(d) - n * 86400)
end
Mail._KeyAgo = KeyAgo

local function NewDay() return { money = 0, items = 0, sold = 0, soldCount = 0, won = 0, outbid = 0, returned = 0, deleted = 0 } end

local function Today()
  DB.mailDays = DB.mailDays or {}
  local key = DayKey()
  local d = DB.mailDays[key]
  if not d then
    d = NewDay(); DB.mailDays[key] = d
    local oldest = KeyAgo(KEEP_DAYS)
    for k in pairs(DB.mailDays) do if k < oldest then DB.mailDays[k] = nil end end
  end
  return d, key
end

function Mail.NoteDelete()
  if not (DB and T) then return end
  T.deleted = T.deleted + 1
  local d = Today(); d.deleted = d.deleted + 1
end

-- called only after the game confirmed the money or the item left the mail
function Mail.Record(kind, name, count, money)
  if not (T and DB) then return end
  count, money = count or 0, money or 0
  Fix(T)
  local day, key = Today()
  T.money = T.money + money
  T.items = T.items + count
  day.money = day.money + money
  day.items = day.items + count
  if money > 0 or count > 0 then
    if T.lastDay ~= key then T.daysActive = T.daysActive + 1; T.lastDay = key end
  end
  if day.money > T.bestDay then T.bestDay = day.money; T.bestDayKey = key end
  if kind == "sold" then
    T.sold = T.sold + money; T.soldCount = T.soldCount + 1
    day.sold = day.sold + money; day.soldCount = day.soldCount + 1
    if name then T.soldItems[name] = (T.soldItems[name] or 0) + 1 end
    if money > T.bestSale then T.bestSale = money; T.bestSaleName = name or false end
  elseif kind == "won" then
    day.won = day.won + count
    T.won = T.won + count
    if name then T.wonItems[name] = (T.wonItems[name] or 0) + count end
  elseif kind == "outbid" then
    T.outbid = T.outbid + money
    day.outbid = day.outbid + money
  elseif kind == "expired" or kind == "cancelled" then
    T.returned = T.returned + count
    day.returned = day.returned + count
    if name and count > 0 then T.returnedItems[name] = (T.returnedItems[name] or 0) + count end
  end
end

function Mail.ResetTally()
  if not DB then return end
  DB.mailTally = NewTally(); T = DB.mailTally
  DB.mailDays = {}
  if Mail.Refresh then Mail.Refresh() end
end

-- ------------------------------------------------------------ collection engine
local MAXATT = _G.ATTACHMENTS_MAX_RECEIVE or 16

local function Header(i)
  local _, _, sender, subject, money, cod, _, hasItem, _, _, textCreated = GetInboxHeaderInfo(i)
  return { sender = sender, subject = subject, money = money or 0, cod = cod or 0,
           hasItem = hasItem and true or false, text = textCreated and true or false }
end

local function FirstItem(i)
  for j = 1, MAXATT do
    local name, _, _, count = GetInboxItem(i, j)
    if name then return j, name, count or 1 end
  end
end

local function Finish(why)
  if not run then return end
  local r = run
  run = nil
  if r.collected > 0 or r.money > 0 or r.deleted > 0 then
    Print(("collected %d item(s) and %s, deleted %d emptied mail(s)%s."):format(r.collected, Money(r.money), r.deleted,
      r.skippedCod > 0 and (", skipped " .. r.skippedCod .. " COD") or ""))
  elseif why == "empty" then
    Print("nothing to collect.")
  end
  if why == "full" then Print("your bags are full. Make room and press Collect again.") end
  if why == "closed" then Print("mailbox closed.") end
  if Mail.Refresh then Mail.Refresh() end
end

local function Wait()
  local token = {}
  run.token = token
  C_Timer.After(1.5, function()
    if run and run.token == token then Mail.Step() end
  end)
end

-- one decision per call. The game answers each action with MAIL_INBOX_UPDATE, which calls Step again.
function Mail.Step()
  if not run then return end
  if not run.open then return Finish("closed") end
  local p = run.pending
  if p then
    run.pending = nil
    local h = Header(p.i)
    if p.kind == "money" then
      if h.subject == p.subject and h.money == 0 then
        run.money = run.money + p.money
        Mail.Record(p.class, p.name, 0, p.money)
      end
    elseif p.kind == "item" then
      local name = GetInboxItem(p.i, p.j)
      if h.subject == p.subject and not name then
        run.collected = run.collected + p.count
        Mail.Record(p.class, p.name, p.count, 0)
      end
    elseif p.kind == "delete" then
      if GetInboxNumItems() < p.before then
        run.deleted = run.deleted + 1; Mail.NoteDelete()
      end
    end
  end

  local n = GetInboxNumItems() or 0
  for i = n, 1, -1 do
    local h = Header(i)
    local class, aName = Mail.Classify(h.subject)
    local key = i .. "|" .. tostring(h.subject)
    if h.cod > 0 then
      if not run.seenCod[key] then run.seenCod[key] = true; run.skippedCod = run.skippedCod + 1 end
    elseif (run.tries[key] or 0) >= 4 then
      -- stuck on this one; leave it
    elseif h.money > 0 then
      run.tries[key] = (run.tries[key] or 0) + 1
      run.pending = { kind = "money", i = i, subject = h.subject, money = h.money, class = class, name = aName }
      TakeInboxMoney(i)
      return Wait()
    elseif FirstItem(i) then
      -- trust the attachment slots themselves, not the header flag, to decide whether anything is left
      local j, name, count = FirstItem(i)
      run.tries[key] = (run.tries[key] or 0) + 1
      run.pending = { kind = "item", i = i, j = j, subject = h.subject, name = aName or name, count = count, class = class }
      TakeInboxItem(i, j)
      return Wait()
    elseif DB.emfDelete and (class or not h.text) and not run.noDelete[key] then
      -- empty (confirmed by the header above), and either an auction/system mail or a mail with no written letter
      run.noDelete[key] = true
      run.pending = { kind = "delete", before = n }
      DeleteInboxItem(i)
      return Wait()
    end
  end
  Finish(run.collected + run.money + run.deleted > 0 and "done" or "empty")
end

function Mail.Start()
  if not (DB and GetInboxNumItems) then return end
  if run then return end
  if not Mail.IsOpen() then Print("open a mailbox first.") return end
  if InCombatLockdown and InCombatLockdown() then Print("not in combat.") return end
  run = { open = true, pending = nil, collected = 0, money = 0, deleted = 0, skippedCod = 0,
          tries = {}, seenCod = {}, noDelete = {} }
  Mail.Step()
end

function Mail.Stop() if run then Finish("stopped") end end
function Mail.Running() return run ~= nil end

local mailOpen = false
function Mail.IsOpen() return mailOpen end
function Mail._SetOpen(v) mailOpen = v and true or false; if run then run.open = mailOpen end end

-- ------------------------------------------------------------ panel
local function Lines()
  local t = T or NewTally()
  local ret = {}
  for name, n in pairs(t.returnedItems) do ret[#ret + 1] = name .. " x" .. n end
  table.sort(ret)
  local when = (date and t.since > 0) and date("%b %d", t.since) or "start"
  return {
    ("Tally since %s"):format(when),
    ("Collected: %s and %d item(s)"):format(Money(t.money), t.items),
    ("Auction sales: %d for %s"):format(t.soldCount, Money(t.sold)),
    ("Auctions won: %d item(s)"):format(t.won),
    ("Outbid refunds: %s"):format(Money(t.outbid)),
    ("Returned items: %d%s"):format(t.returned, #ret > 0 and (" (" .. table.concat(ret, ", ", 1, math.min(#ret, 3)) .. ")") or ""),
    ("Emptied mails deleted: %d"):format(t.deleted),
  }
end

-- today / yesterday block shown under the lifetime lines
local function DayLines()
  local days = (DB and DB.mailDays) or {}
  local out = { "" }
  for _, p in ipairs({ { "Today", 0 }, { "Yesterday", 1 } }) do
    local key = KeyAgo(p[2])
    local d = days[key] or NewDay()
    out[#out + 1] = ("%s (%s)"):format(p[1], key:sub(6))
    out[#out + 1] = ("  Collected: %s, %d item(s)"):format(Money(d.money), d.items)
    out[#out + 1] = ("  Sales: %d for %s"):format(d.soldCount, Money(d.sold))
  end
  return out
end

-- highest count in a name -> count map; ties go to the earlier name so the answer never flickers
local function Top(map)
  local bn, bc
  for name, c in pairs(map or {}) do
    if not bc or c > bc or (c == bc and name < bn) then bn, bc = name, c end
  end
  return bn, bc
end

local function Dated(key) return key and (" (" .. key:sub(6) .. ")") or "" end

-- lines for the slide-out panel
local function StatLines()
  local t = T or NewTally()
  local days = (DB and DB.mailDays) or {}
  local week = 0
  for n = 0, 6 do local d = days[KeyAgo(n)]; if d then week = week + d.money end end
  local topName, topN = Top(t.soldItems)
  local wonName, wonN = Top(t.wonItems)
  local retName, retN = Top(t.returnedItems)
  local avgSale = t.soldCount > 0 and math.floor(t.sold / t.soldCount) or 0
  local active = t.daysActive or 0
  return {
    "Best day: " .. Money(t.bestDay or 0) .. Dated(t.bestDayKey),
    "Top item sold: " .. (topName and ("%s (sold %d time%s)"):format(topName, topN, topN == 1 and "" or "s") or "none yet"),
    "Biggest sale: " .. Money(t.bestSale or 0) .. ((t.bestSaleName and (" - " .. t.bestSaleName)) or ""),
    "Average sale: " .. Money(avgSale),
    "Last 7 days: " .. Money(week),
    "Days with mail: " .. active .. (active > 0 and ("  (avg " .. Money(math.floor(t.money / active)) .. "/day)") or ""),
    "Most won: " .. (wonName and (wonName .. " x" .. wonN) or "none yet"),
    "Most returned: " .. (retName and (retName .. " x" .. retN) or "none yet"),
    "Total sales: " .. t.soldCount,
  }
end
Mail._Lines = Lines
Mail._DayLines = DayLines
Mail._StatLines = StatLines

-- stats drawer: a vertical "EMF" tab on the right edge. Opening drops a strip (tab width) down to the full window height,
-- and only then widens it to the right. side.cur is the total distance travelled: first down, then right.
local SIDE_W, SIDE_SPEED = 210, 600
local TAB_W, TAB_H, FULL_H = 22, 70, 268
local TRAVEL_H = FULL_H - TAB_H
local TRAVEL = TRAVEL_H + (SIDE_W - TAB_W)

function Mail.Refresh()
  if not frame then return end
  local l = Lines()
  for _, x in ipairs(DayLines()) do l[#l + 1] = x end
  frame.text:SetText(table.concat(l, "\n"))
  if frame.side then
    frame.side.text:SetText("Stats\n\n" .. table.concat(StatLines(), "\n\n"))
  end
  frame.auto:SetText("Auto-collect: " .. (DB.emfAuto and "ON" or "off"))
  frame.del:SetText("Delete emptied: " .. (DB.emfDelete and "ON" or "off"))
  frame.go:SetText(run and "Stop" or "Collect all")
end

local function Build()
  local f = CreateFrame("Frame", "RealmMailEMF", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(260, 268)
  f:SetPoint("CENTER", 0, 0)
  f:SetFrameStrata("HIGH"); f:SetToplevel(true)
  f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if ns.UI and ns.UI.Skin then ns.UI.Skin(f) end
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOPLEFT", 10, -9); f.title:SetText("Exchange Mail (EMF)")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.text:SetPoint("TOPLEFT", 10, -30); f.text:SetJustifyH("LEFT"); f.text:SetWidth(240)

  local go = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  go:SetSize(110, 22); go:SetPoint("BOTTOMLEFT", 10, 38)
  go:SetScript("OnClick", function() if run then Mail.Stop() else Mail.Start() end; Mail.Refresh() end)
  f.go = go
  local reset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  reset:SetSize(110, 22); reset:SetPoint("BOTTOMRIGHT", -10, 38); reset:SetText("Reset tally")
  reset:SetScript("OnClick", Mail.ResetTally)
  local auto = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  auto:SetSize(120, 22); auto:SetPoint("BOTTOMLEFT", 10, 10)
  auto:SetScript("OnClick", function() DB.emfAuto = not DB.emfAuto; Mail.Refresh() end)
  f.auto = auto
  local del = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  del:SetSize(120, 22); del:SetPoint("BOTTOMRIGHT", -10, 10)
  del:SetScript("OnClick", function() DB.emfDelete = not DB.emfDelete; Mail.Refresh() end)
  f.del = del

  -- stats panel that slides out of the right edge; its width grows from 0 and the text is clipped until it fits
  local side = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
  side:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, 0)
  side:SetSize(TAB_W, TAB_H)
  if side.SetClipsChildren then side:SetClipsChildren(true) end
  if ns.UI and ns.UI.Skin then ns.UI.Skin(side) end
  side.text = side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  side.text:SetPoint("TOPLEFT", TAB_W + 10, -10); side.text:SetJustifyH("LEFT"); side.text:SetWidth(SIDE_W - TAB_W - 20)
  side.cur, side.target = 0, 0
  function side.Apply(self)
    self:SetHeight(TAB_H + math.min(self.cur, TRAVEL_H))
    self:SetWidth(TAB_W + math.max(0, self.cur - TRAVEL_H))
  end
  side:SetScript("OnUpdate", function(self, elapsed)
    local step = SIDE_SPEED * (elapsed or 0.016)
    if self.cur < self.target then self.cur = math.min(self.target, self.cur + step)
    elseif self.cur > self.target then self.cur = math.max(self.target, self.cur - step) end
    self:Apply()
    if self.cur <= 0 and self.target == 0 then self:Hide() end
  end)
  side:Hide()
  f.side = side

  local tab = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  tab:SetSize(TAB_W, TAB_H); tab:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, 0)
  tab:SetText("E\nM\nF")
  if tab.SetFrameLevel and side.GetFrameLevel then tab:SetFrameLevel(side:GetFrameLevel() + 5) end
  tab:SetScript("OnClick", function() Mail.SetStats(not DB.emfStatsOpen) end)
  tab:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("EMF stats")
    GameTooltip:AddLine("Click to open or close.", 1, 1, 1)
    GameTooltip:Show()
  end)
  tab:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  f.tab = tab
  f:Hide()
  return f
end

-- open or close the stats panel; instant = true skips the slide (used when the window first appears)
function Mail.SetStats(open, instant)
  if not DB then return end
  frame = frame or Build()
  DB.emfStatsOpen = open and true or false
  local s = frame.side
  s.target = DB.emfStatsOpen and TRAVEL or 0
  if DB.emfStatsOpen then s:Show() end
  if instant then
    s.cur = s.target; s:Apply()
    if s.target == 0 then s:Hide() end
  end
  Mail.Refresh()
end

function Mail.Show()
  if not DB then return end
  frame = frame or Build()
  if mailOpen and MailFrame then
    frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 6, 0)
  end
  frame:Show()
  Mail.SetStats(DB.emfStatsOpen, true)
end
function Mail.Toggle()
  frame = frame or (DB and Build())
  if not frame then return end
  if frame:IsShown() then frame:Hide() else Mail.Show() end
end

function Mail.Command(arg)
  arg = (arg or ""):lower()
  local sub, rest = arg:match("^(%S*)%s*(.-)$")
  if sub == "collect" or sub == "go" then Mail.Start()
  elseif sub == "auto" then
    if rest == "on" then DB.emfAuto = true elseif rest == "off" then DB.emfAuto = false else DB.emfAuto = not DB.emfAuto end
    Print("auto-collect when you open the mailbox: " .. (DB.emfAuto and "ON (hold Shift to skip)" or "off"))
  elseif sub == "delete" then
    if rest == "on" then DB.emfDelete = true elseif rest == "off" then DB.emfDelete = false else DB.emfDelete = not DB.emfDelete end
    Print("delete emptied mails: " .. (DB.emfDelete and "ON (only after items and money are confirmed taken)" or "off"))
  elseif sub == "tally" then
    for _, l in ipairs(Lines()) do print("  " .. l) end
    for _, l in ipairs(DayLines()) do print("  " .. l) end
  elseif sub == "stats" then
    for _, l in ipairs(StatLines()) do print("  " .. l) end
  elseif sub == "reset" then Mail.ResetTally(); Print("tally reset.")
  elseif sub == "help" then
    Print("/realm mail (panel) | collect | auto on|off | delete on|off | tally | stats | reset")
  else Mail.Toggle() end
end

-- ------------------------------------------------------------ events
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "UI_ERROR_MESSAGE" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, e, a1, a2)
  if e == "PLAYER_LOGIN" then
    DB = ns.DB
    if DB.emfAuto == nil then DB.emfAuto = false end
    if DB.emfDelete == nil then DB.emfDelete = true end
    DB.mailTally = DB.mailTally or NewTally()
    T = Fix(DB.mailTally)
    DB.mailDays = DB.mailDays or {}
  elseif not DB then return
  elseif e == "MAIL_SHOW" then
    mailOpen = true
    C_Timer.After(0.2, function() Mail.Show() end)
    if DB.emfAuto and not (IsShiftKeyDown and IsShiftKeyDown()) then
      C_Timer.After(0.8, function() if mailOpen then Mail.Start() end end)
    end
  elseif e == "MAIL_CLOSED" then
    mailOpen = false
    if run then run.open = false; Finish("closed") end
    if frame then frame:Hide() end
  elseif e == "MAIL_INBOX_UPDATE" then
    if run then Mail.Step() end
  elseif e == "UI_ERROR_MESSAGE" then
    local msg = a2 or a1
    if run and msg and (msg == _G.ERR_INV_FULL or msg == _G.ERR_ITEM_MAX_COUNT) then Finish("full") end
  end
end)
