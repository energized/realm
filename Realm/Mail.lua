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
           sold = 0, soldCount = 0, won = 0, outbid = 0, returned = 0, returnedItems = {}, wonItems = {}, deleted = 0 }
end

function Mail.Tally() return T end

-- called only after the game confirmed the money or the item left the mail
function Mail.Record(kind, name, count, money)
  if not T then return end
  count, money = count or 0, money or 0
  T.money = T.money + money
  T.items = T.items + count
  if kind == "sold" then
    T.sold = T.sold + money; T.soldCount = T.soldCount + 1
  elseif kind == "won" then
    T.won = T.won + count
    if name then T.wonItems[name] = (T.wonItems[name] or 0) + count end
  elseif kind == "outbid" then
    T.outbid = T.outbid + money
  elseif kind == "expired" or kind == "cancelled" then
    T.returned = T.returned + count
    if name and count > 0 then T.returnedItems[name] = (T.returnedItems[name] or 0) + count end
  end
end

function Mail.ResetTally()
  if not DB then return end
  DB.mailTally = NewTally(); T = DB.mailTally
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
        run.deleted = run.deleted + 1; T.deleted = T.deleted + 1
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
Mail._Lines = Lines

function Mail.Refresh()
  if not frame then return end
  local l = Lines()
  frame.text:SetText(table.concat(l, "\n"))
  frame.auto:SetText("Auto-collect: " .. (DB.emfAuto and "ON" or "off"))
  frame.del:SetText("Delete emptied: " .. (DB.emfDelete and "ON" or "off"))
  frame.go:SetText(run and "Stop" or "Collect all")
end

local function Build()
  local f = CreateFrame("Frame", "RealmMailEMF", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(260, 218)
  f:SetPoint("CENTER", 0, 0)
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
  f:Hide()
  return f
end

function Mail.Show()
  if not DB then return end
  frame = frame or Build()
  if mailOpen and MailFrame then
    frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 6, 0)
  end
  frame:Show(); Mail.Refresh()
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
  elseif sub == "reset" then Mail.ResetTally(); Print("tally reset.")
  elseif sub == "help" then
    Print("/realm mail (panel) | collect | auto on|off | delete on|off | tally | reset")
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
    T = DB.mailTally
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
