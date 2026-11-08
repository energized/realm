-- Realm Mule: mail the things this character cannot use (armor, weapons, crafting goods) to your auction house alt.
-- You pick the alt once and Realm remembers it. When your bags are getting full of such items, you are near an inn and
-- you can afford the postage, the compass sends you to a mailbox, and opening it mails the items for you.
-- Never mails soulbound items, quest items, grey junk, a gear upgrade Realm has found for you, or anything on the keep list.
-- Also keeps what you can use: armor and weapons your class can wear (even above your level), your professions' tools,
-- materials and recipes, class reagents, and items your current quests ask for.
-- Never mails to yourself. Stops the moment money runs short or the mailbox closes.
local ADDON, ns = ...
local Mule = {}
ns.Mule = Mule

local DB
local POSTAGE = 30            -- copper per mail, used until the game reports the real price
local RESERVE = 100           -- copper always left in your pocket after postage
local NEAR = 450              -- yards: only reroute when an inn is this close
local MIN_ITEMS = 6           -- stacks waiting before bags count as "somewhat full of these"
local FULL_FRACTION = 0.75    -- ...or this share of slots used with at least two such stacks
local SNOOZE = 20 * 60        -- seconds a "later" (or a failed attempt) silences the reroute
local BOX_GAP = 0.004         -- map units: mailbox spots closer than this are the same box

local function Print(m) if ns.Print then ns.Print("Mule: " .. m) end end
local function Now() return (GetTime and GetTime()) or 0 end
local function SelfName() return (UnitName and UnitName("player")) or "?" end
local function Stamp() return (time and time()) or 0 end

-- ------------------------------------------------------------ link check (the "2FA" between this character and the AH alt)
-- Choosing an alt mails it a test letter with a short code. On the alt, Realm sees the letter and answers it with the
-- subject "confirm <CODE>". Back on this character, Realm finds that answer, the codes match, and the link is confirmed:
-- the mail really reaches that character, so it is the right one. State per alt: unsent -> sent -> verified.
local CODE_CHARS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"      -- no 0/O/1/I/L: easy to read and to type
local CHECK_DAYS = 29                                      -- mail lives 30 days; after this a new code is sent
local function NewCode()
  local out = {}
  for i = 1, 5 do local k = math.random(#CODE_CHARS); out[i] = CODE_CHARS:sub(k, k) end
  return table.concat(out)
end
local function LinkOf(alt)
  DB.muleLink = DB.muleLink or {}
  DB.muleLink[alt] = DB.muleLink[alt] or { state = "unsent" }
  return DB.muleLink[alt]
end

-- ------------------------------------------------------------ which items go (pure, unit tested)
-- Items this character can use or needs are never mailed: armor and weapons its class can ever wear (also those it is
-- too low level for yet), the tools and materials of its own professions, recipes for them, class reagents, and
-- anything a current quest asks for. Everything else that is unbound can go.
local TOOLS = {                       -- item name pattern -> the profession it is the tool of
  { "skinning knife", "Skinning" }, { "mining pick", "Mining" }, { "blacksmith hammer", "Blacksmithing" },
  { "arclight spanner", "Engineering" }, { "gyromatic", "Engineering" }, { "gnomish army knife", "Engineering" },
  { "runed .* rod", "Enchanting" }, { "fishing pole", "Fishing" },
}
local GOODS = {                       -- trade goods subclass -> professions that use it
  [1] = { Engineering = true }, [2] = { Engineering = true }, [3] = { Engineering = true },
  [5] = { Tailoring = true, ["First Aid"] = true }, [6] = { Leatherworking = true },
  [7] = { Mining = true, Blacksmithing = true, Engineering = true }, [8] = { Cooking = true }, [9] = { Alchemy = true },
  [10] = { Alchemy = true, Enchanting = true, Engineering = true, Blacksmithing = true, Tailoring = true, Leatherworking = true },
  [12] = { Enchanting = true }, [14] = { Enchanting = true }, [15] = { Enchanting = true },
}
local CRAFTS = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring", "Cooking", "First Aid", "Mining" }
local RECIPE = { [1] = "Leatherworking", [2] = "Tailoring", [3] = "Engineering", [4] = "Blacksmithing", [5] = "Cooking",
                 [6] = "Alchemy", [7] = "First Aid", [8] = "Enchanting" }
local REAGENT_USERS = { MAGE = true, PRIEST = true, PALADIN = true, DRUID = true, SHAMAN = true, ROGUE = true, WARLOCK = true }

-- me = { gear = class gear table (armor/weapon types), token = class token, profs = { [name] = true }, quest = { [lowercase item name] = true } }
-- Returns true when this character can use or needs the item. Unsure counts as "keep".
function Mule.Keeps(it, me)
  if not it or not me then return false end
  local nm = it.name and it.name:lower()
  if nm and me.quest and me.quest[nm] then return true end
  local profs, g, c, sc = me.profs or {}, me.gear, it.cls, it.sub
  if c == 2 or c == 4 then
    if nm then for _, t in ipairs(TOOLS) do if nm:find(t[1]) then return profs[t[2]] == true end end end
    if c == 2 and sc == 20 then return profs.Fishing == true end
    if not g or sc == nil then return true end                       -- class or kind unknown: never risk mailing it
    if c == 2 then return sc == 14 or g.weaponSubclasses[sc] == true end   -- 14: unnamed tools and oddities stay
    if it.loc == "INVTYPE_CLOAK" or sc == 0 or sc >= 11 then
      return not (sc == 0 and it.loc == "INVTYPE_HOLDABLE" and not g.holdable)
    end
    if sc == 6 then return g.armorSubclasses[6] == true end
    if sc >= 7 and sc <= 10 then return g.relicSubclass == sc end
    local top = 1
    for t = 1, 4 do if g.armorSubclasses[t] then top = math.max(top, t) end end
    return sc <= top                                                  -- cloth < leather < mail < plate, any level
  end
  if c == 7 then
    local set = GOODS[sc or -1]
    if set then
      for p in pairs(set) do if profs[p] then return true end end
      return false
    end
    for _, p in ipairs(CRAFTS) do if profs[p] then return true end end   -- thread, salt and other odds and ends
    return false
  end
  if c == 5 then return REAGENT_USERS[me.token or ""] == true end
  if c == 9 then local p = RECIPE[sc or -1]; return p ~= nil and profs[p] == true end
  return false
end

-- it = { id, link, cls, sub, loc, name, q, fam, bound }. keep = { [itemId] = true }. upgrades = { [link] = true } (found by Realm's gear engine)
-- me = see Mule.Keeps; without it only the rules below apply.
-- ok = { [itemId] = name }: items you approved on the send list; they go even when Realm would have held them back.
function Mule.Wanted(it, keep, upgrades, me, ok)
  if not it or it.bound then return false end
  if (it.q or 0) < 1 then return false end                         -- grey junk belongs to the vendor
  if keep and it.id and keep[it.id] then return false end
  if ok and it.id and ok[it.id] then return true end
  if upgrades and it.link and upgrades[it.link] then return false end
  if me and Mule.Keeps(it, me) then return false end
  local c = it.cls
  if c == 2 or c == 4 then return true end                         -- weapons, armor
  if c == 3 or c == 5 or c == 7 or c == 8 or c == 9 then return true end   -- gems, reagents, trade goods, enhancements, recipes
  if it.fam and it.fam ~= 0 then return true end                   -- anything sitting in a profession bag
  return false
end

-- items = every slot's item. Returns the plan: which stacks, what they cost to mail, and whether it is time.
-- s = { alt, on, money, postage, used, total, keep, upgrades, min }
function Mule.Plan(items, s)
  local list = {}
  for _, it in ipairs(items or {}) do
    if Mule.Wanted(it, s.keep, s.upgrades, s.me, s.ok) then list[#list + 1] = it end
  end
  local postage = s.postage or POSTAGE
  local n = #list
  local plan = { list = list, n = n, postage = postage, cost = n * postage }
  plan.enough = (s.money or 0) >= plan.cost + RESERVE
  local total = s.total or 0
  plan.full = total > 0 and (s.used or 0) / total >= FULL_FRACTION
  local min = s.min or MIN_ITEMS
  plan.ready = n >= min or (plan.full and n >= 2)
  if not s.alt or s.alt == "" then plan.why = "no alt chosen"
  elseif s.on == false then plan.why = "switched off"
  elseif s.verified == false then plan.why = "auto-mail is off until you log in on the alt once (or it answers the link check)"
  elseif n == 0 then plan.why = "nothing to mail"
  elseif not plan.enough then plan.why = "not enough money for postage"
  elseif not plan.ready then plan.why = "bags are not full of these yet"
  end
  plan.due = plan.why == nil
  return plan
end

-- ------------------------------------------------------------ reading the bags
local function InfoFor(link)                  -- class, subclass, equip slot
  local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if inst then
    local ok, _, _, _, loc, _, c, sc = pcall(inst, link)
    if ok then return c, sc, loc end
  end
end

local function Slot(bag, slot)
  local CC = C_Container
  if CC and CC.GetContainerItemInfo then
    local i = CC.GetContainerItemInfo(bag, slot)
    if i and i.hyperlink then return i.hyperlink, i.stackCount or 1, i.quality, i.itemID, i.isBound, i.isLocked end
  elseif GetContainerItemInfo then
    local _, count, locked, quality, _, _, link, _, _, id, bound = GetContainerItemInfo(bag, slot)
    if link then return link, count or 1, quality, id, bound, locked end
  end
end

function Mule.Scan()
  local out, total, used = {}, 0, 0
  local CC = C_Container
  local numSlots = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
  if not numSlots then return out, 0, 0 end
  local freeFn = (CC and CC.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local size = numSlots(bag) or 0
    local fam = 0
    if freeFn then
      local ok, _, f = pcall(freeFn, bag)
      if ok and type(f) == "number" then fam = f end
    end
    total = total + size
    for slot = 1, size do
      local link, count, q, id, bound, locked = Slot(bag, slot)
      if link then
        used = used + 1
        if not locked then
          local cls, sub, loc = InfoFor(link)
          out[#out + 1] = { bag = bag, slot = slot, link = link, count = count, q = q or 1,
                            id = id or tonumber(link:match("item:(%d+)")), cls = cls or 99, sub = sub, loc = loc,
                            fam = fam, bound = bound and true or false,
                            name = link:match("%[(.-)%]") or "?" }
        end
      end
    end
  end
  return out, total, used
end

local function Postage()
  local p = GetSendMailPrice and GetSendMailPrice()
  return (type(p) == "number" and p > 0) and p or POSTAGE
end

local function UpgradeSet()
  local set = {}
  local G = ns.TB and ns.TB.Gear
  for _, u in ipairs((G and G.upgrades) or {}) do if u.link then set[u.link] = true end end
  return set
end

-- names of items the current quests still ask for, from the quest objectives ("Wolf Meat: 3/8")
local function QuestItems()
  local set = {}
  local function add(text)
    local n = type(text) == "string" and text:match("^(.-):%s*%d+%s*/%s*%d+")
    if n and n ~= "" then set[n:lower()] = true end
  end
  pcall(function()
    local QL = C_QuestLog
    if QL and QL.GetNumQuestLogEntries and QL.GetInfo and QL.GetQuestObjectives then
      for i = 1, (QL.GetNumQuestLogEntries()) do
        local info = QL.GetInfo(i)
        if info and not info.isHeader and info.questID then
          for _, o in ipairs(QL.GetQuestObjectives(info.questID) or {}) do if o.type == "item" then add(o.text) end end
        end
      end
    elseif GetNumQuestLogEntries and GetQuestLogLeaderBoard then
      for i = 1, (GetNumQuestLogEntries()) do
        for j = 1, (GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i) or 0) do
          local text, kind = GetQuestLogLeaderBoard(j, i)
          if kind == "item" then add(text) end
        end
      end
    end
  end)
  return set
end

-- who is playing: class gear rules (from the class guide), professions, quest items
local function Me()
  local TB = ns.TB
  local cls = TB and TB.Class and TB.Class()
  local P = ns.Path and ns.Path.Prof
  local profs = {}
  if P and P.Known then
    local ok, known = pcall(P.Known)
    if ok and type(known) == "table" then for name in pairs(known) do profs[name] = true end end
  end
  return { gear = cls and cls.gear, token = TB and TB.ClassToken and TB.ClassToken(), profs = profs, quest = QuestItems() }
end
Mule.Me = Me

local function Settings(total, used)
  local alt = DB and DB.muleTo
  local link = alt and DB.muleLink and DB.muleLink[alt]
  local verified                      -- nil with no alt; false until the alt has answered the link check
  -- the alt is trusted once the letter was answered, or once the player has logged in on it (the name is then exact)
  if alt then verified = (link ~= nil and (link.state == "verified" or link.named == true)) end
  return { alt = alt, on = DB and DB.muleOn, verified = verified, money = GetMoney and GetMoney() or 0, postage = Postage(),
           used = used, total = total, keep = DB and DB.muleKeep, ok = DB and DB.muleOk, upgrades = UpgradeSet(), min = DB and DB.muleMin, me = Me() }
end

function Mule.Current()
  local items, total, used = Mule.Scan()
  return Mule.Plan(items, Settings(total, used))
end

-- ------------------------------------------------------------ the "ok to send" list
-- Items Realm holds back (you can use them, or it is not sure) can be approved here and are then mailed like the rest.
-- One list, saved in RealmDB: the bags, the EMF mail window and the Mule window all read and change this same list.
local TRADABLE = { [2] = true, [3] = true, [4] = true, [5] = true, [7] = true, [8] = true, [9] = true }

local function ItemId(it)
  if not it then return nil end
  return it.id or (it.link and tonumber(tostring(it.link):match("item:(%d+)")))
end

local function ByName(a, b)
  if a.name ~= b.name then return a.name < b.name end
  return a.id < b.id
end

function Mule.OkList()
  local out = {}
  for id, name in pairs((DB and DB.muleOk) or {}) do
    out[#out + 1] = { id = id, name = type(name) == "string" and name or ("item " .. id) }
  end
  table.sort(out, ByName)
  return out
end

-- items in your bags that could be mailed but are held back (usable by you, wanted for a quest, an upgrade...), one per item
function Mule.Held()
  local out = {}
  if not DB then return out end
  local items = Mule.Scan()
  local s = Settings(0, 0)
  local seen = {}
  for _, it in ipairs(items) do
    local id = ItemId(it)
    if id and not seen[id] and not it.bound and (it.q or 0) >= 1 and TRADABLE[it.cls] then
      seen[id] = true
      if not (DB.muleOk and DB.muleOk[id]) and not (DB.muleKeep and DB.muleKeep[id])
         and not Mule.Wanted(it, s.keep, s.upgrades, s.me, s.ok) then
        out[#out + 1] = { id = id, name = it.name or ("item " .. id), link = it.link }
      end
    end
  end
  table.sort(out, ByName)
  return out
end

function Mule.Approve(id, name)
  if not (DB and id) then return false end
  DB.muleOk = DB.muleOk or {}
  DB.muleOk[id] = (type(name) == "string" and name ~= "") and name or ("item " .. id)
  if DB.muleKeep then DB.muleKeep[id] = nil end       -- one list or the other, never both
  Mule.MarkDirty(); Mule.Changed()
  return true
end

function Mule.Unapprove(id)
  if not (DB and id and DB.muleOk and DB.muleOk[id]) then return false end
  DB.muleOk[id] = nil
  Mule.MarkDirty(); Mule.Changed()
  return true
end

-- click mode: Mule.pick is "add", "remove" or nil. The bags call PickClick with the item that was clicked.
function Mule.SetPick(mode)
  if mode == Mule.pick then mode = nil end
  Mule.pick = mode
  if mode == "add" then Print("add by click is ON: left-click an item in your bags to allow mailing it. Press the button again to stop.")
  elseif mode == "remove" then Print("remove by click is ON: left-click an item in your bags to take it off the send list. Press the button again to stop.")
  else Print("click mode is off.") end
  Mule.Changed()
end

function Mule.PickClick(it)
  local mode = Mule.pick
  if not mode then return false end
  local id = ItemId(it)
  if not id then return true end
  local name = it.name or (it.link and tostring(it.link):match("%[(.-)%]")) or ("item " .. id)
  if mode == "add" then
    if it.bound then Print(name .. " is soulbound and cannot be mailed.")
    elseif Mule.Approve(id, name) then Print(name .. " is on the send list: it will be mailed to your alt.") end
  elseif Mule.Unapprove(id) then Print(name .. " is off the send list.")
  else Print(name .. " was not on the send list.") end
  return true
end

-- every "Send list" button (bags, EMF) registers here, so they all show the same count
local listButtons = {}
function Mule.RefreshListButtons()
  if not DB then return end
  local n = #Mule.Held()
  for _, b in ipairs(listButtons) do b:SetText(n > 0 and ("Send list (" .. n .. ")") or "Send list") end
end
function Mule.RegisterListButton(b)
  listButtons[#listButtons + 1] = b
  b:SetScript("OnClick", function() Mule.ShowList() end)
  Mule.RefreshListButtons()
end

local lwin, LROWS = nil, 7

function Mule.RefreshList()
  if not (lwin and DB) then return end
  local held, oks = Mule.Held(), Mule.OkList()
  for i = 1, LROWS do
    local r, h = lwin.held[i], held[i]
    if h then r.id, r.name = h.id, h.name; r.text:SetText("|cff33ff33+|r " .. h.name); r:Show() else r.id = nil; r:Hide() end
    local r2, o = lwin.ok[i], oks[i]
    if o then r2.id, r2.name = o.id, o.name; r2.text:SetText("|cffff5555x|r " .. o.name); r2:Show() else r2.id = nil; r2:Hide() end
  end
  lwin.heldHdr:SetText(("Held back in your bags (%d). Click one to allow mailing it."):format(#held))
  lwin.okHdr:SetText(("On the send list (%d). Click one to remove it."):format(#oks))
  lwin.heldMore:SetText(#held > LROWS and ("+ " .. (#held - LROWS) .. " more: use Add by click") or (#held == 0 and "Nothing is held back right now." or ""))
  lwin.okMore:SetText(#oks > LROWS and ("+ " .. (#oks - LROWS) .. " more: use Remove by click") or (#oks == 0 and "Nothing on the list yet." or ""))
  lwin.add:SetText(Mule.pick == "add" and "Add by click: ON" or "Add by click")
  lwin.remove:SetText(Mule.pick == "remove" and "Remove by click: ON" or "Remove by click")
end

function Mule.Changed()
  if Mule.RefreshUI then Mule.RefreshUI() end
  Mule.RefreshList()
  Mule.RefreshListButtons()
end

local function BuildList()
  local f = CreateFrame("Frame", "RealmMuleList", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(300, 412)
  f:SetPoint("CENTER", 300, 0)
  f:SetFrameStrata("HIGH"); f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if ns.UI and ns.UI.Skin then ns.UI.Skin(f) end
  if UISpecialFrames then table.insert(UISpecialFrames, "RealmMuleList") end
  local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("TOPLEFT", 10, -9); t:SetText("Send list: items that may be mailed")
  local close = CreateFrame("Button", nil, f)
  close:SetSize(22, 22); close:SetPoint("TOPRIGHT", -6, -6)
  if ns.UI and ns.UI.Button then ns.UI.Button(close) end
  close.l = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); close.l:SetPoint("CENTER"); close.l:SetText("x")
  close:SetScript("OnClick", function() f:Hide() end)
  local function Btn(label, x, w, mode)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(w, 22); b:SetPoint("TOPLEFT", x, -32)
    b:SetText(label)
    if ns.UI and ns.UI.Modern then ns.UI.Modern(b) end
    b:SetScript("OnClick", function() Mule.SetPick(mode) end)
    return b
  end
  f.add, f.remove = Btn("Add by click", 10, 138, "add"), Btn("Remove by click", 152, 138, "remove")
  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 10, -60); hint:SetWidth(280); hint:SetJustifyH("LEFT")
  hint:SetText("Turn a click mode on, then left-click items in your bags. Or click a row below. The bags and the mail window share this list.")
  f.heldHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.heldHdr:SetPoint("TOPLEFT", 10, -96); f.heldHdr:SetWidth(280); f.heldHdr:SetJustifyH("LEFT")
  f.okHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.okHdr:SetPoint("TOPLEFT", 10, -252); f.okHdr:SetWidth(280); f.okHdr:SetJustifyH("LEFT")
  f.heldMore = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.heldMore:SetPoint("TOPLEFT", 10, -112 - LROWS * 18); f.heldMore:SetWidth(280); f.heldMore:SetJustifyH("LEFT")
  f.okMore = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.okMore:SetPoint("TOPLEFT", 10, -268 - LROWS * 18); f.okMore:SetWidth(280); f.okMore:SetJustifyH("LEFT")
  f.held, f.ok = {}, {}
  for i = 1, LROWS do
    for _, spec in ipairs({ { f.held, -112, Mule.Approve }, { f.ok, -268, Mule.Unapprove } }) do
      local r = CreateFrame("Button", nil, f)
      r:SetSize(280, 18); r:SetPoint("TOPLEFT", 10, spec[2] - (i - 1) * 18)
      r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      r.text:SetPoint("LEFT", 0, 0)
      r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, .12)
      local fn = spec[3]
      r:SetScript("OnClick", function(self) if self.id then fn(self.id, self.name) end end)
      spec[1][i] = r
    end
  end
  f:Hide()
  return f
end

function Mule.ShowList(show)
  if not DB then return end
  lwin = lwin or BuildList()
  if show == nil then show = not lwin:IsShown() end
  if show then
    local emf = _G.RealmMailEMF
    if Mule.MailIsOpen() and emf and emf:IsShown() then
      lwin:ClearAllPoints(); lwin:SetPoint("TOPRIGHT", emf, "TOPLEFT", -4, 0)
    end
    lwin:Show(); Mule.RefreshList()
  else lwin:Hide() end
end
function Mule.ListWindow() return lwin end

-- ------------------------------------------------------------ the saved alt list
-- every character Realm has seen (from the bag snapshots) except the one playing
function Mule.Alts()
  local out = {}
  local me = SelfName()
  for key, rec in pairs((DB and DB.bags) or {}) do
    local name = rec.name or key:match("^([^-]+)")
    if name and name ~= me then out[#out + 1] = { name = name, class = rec.class, level = rec.level } end
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

-- a name typed in any case -> the saved alt's exact name
function Mule.FindAlt(text)
  text = (text or ""):lower()
  if text == "" then return nil end
  local part
  for _, a in ipairs(Mule.Alts()) do
    if a.name:lower() == text then return a.name end
    if a.name:lower():find(text, 1, true) and not part then part = a.name end
  end
  return part
end

function Mule.SetAlt(name)
  if not DB then return false end
  if name == SelfName() then Print("pick a different character: you cannot mail to yourself.") return false end
  DB.muleTo = name
  if name then
    Print("items will be mailed to " .. name .. ".")
    local l = LinkOf(name)
    if not l.named and l.state ~= "verified" then
      Print("log in on " .. name .. " once so Realm can confirm the name; auto-mail starts after that. Realm also mails " .. name .. " a test letter when you open a mailbox.")
    end
  else Print("no alt chosen; nothing will be mailed.") end
  Mule.MarkDirty()
  if Mule.RefreshUI then Mule.RefreshUI() end
  -- a mailbox is open and this alt has not answered a check yet: start its link check now (the "2FA" repeats per alt)
  if name and Mule.MailIsOpen() and LinkOf(name).state == "unsent" and not Mule.Sending() then
    if Mule.SendCheck() then Mule.RefreshUI() end
  end
  return true
end

-- ------------------------------------------------------------ mailboxes Realm has seen (learned when you open one)
local function PlayerMap()
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
  if ok and type(m) == "number" then return m end
end

local function PlayerXY(map)
  if not (map and C_Map and C_Map.GetPlayerMapPosition) then return nil end
  local pos = C_Map.GetPlayerMapPosition(map, "player")
  if not pos then return nil end
  local x, y
  if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
  if type(x) ~= "number" or (x == 0 and y == 0) then return nil end
  return x, y
end

function Mule.LearnBox(map, x, y)
  if not (DB and map and x and y) then return false end
  DB.mailboxes = DB.mailboxes or {}
  local list = DB.mailboxes[map] or {}
  DB.mailboxes[map] = list
  for _, b in ipairs(list) do
    if math.abs(b[1] - x) < BOX_GAP and math.abs(b[2] - y) < BOX_GAP then return false end
  end
  if #list >= 6 then table.remove(list, 1) end
  list[#list + 1] = { x, y }
  return true
end

-- ------------------------------------------------------------ the compass stop
local state = { due = false, n = 0, alt = nil, why = "not checked" }
local dirty, lastCalc, snoozeUntil = true, -1000, 0
local nearCache = { t = -1000 }

function Mule.MarkDirty() dirty = true end
function Mule.State() return state end
function Mule.Snooze(secs) snoozeUntil = Now() + (secs or SNOOZE) end

function Mule.Refresh()
  dirty, lastCalc = false, Now()
  if not DB then state = { due = false, n = 0, why = "not loaded" } return state end
  local p = Mule.Current()
  state = { due = p.due, n = p.n, cost = p.cost, alt = DB.muleTo, why = p.why }
  return state
end

local function Faction()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  return f == "Horde" and "H" or "A"
end

-- nearest usable inn in the player's zone and its distance in yards
local function NearInn(map)
  local P = ns.Path
  if not (P and P.Vector and ns.Inns and P.Inn and P.Inn.XY) then return nil end
  local fac, best, bd = Faction(), nil, nil
  for _, e in ipairs(ns.Inns) do
    if e[2] == map and (not e[5] or e[5] == fac) then
      local x, y = P.Inn.XY(e)
      local b, d = P.Vector(map, x, y)
      if b and (not bd or d < bd) then best, bd = e, d end
    end
  end
  return best, bd
end

-- The compass target while a mail errand is due, or nil. Cheap enough to call every compass tick.
function Mule.Target()
  if not DB then return nil end
  local now = Now()
  if dirty and now - lastCalc > 3 then Mule.Refresh() end
  if not state.due or now < snoozeUntil then return nil end
  if InCombatLockdown and InCombatLockdown() then return nil end
  if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return nil end
  if IsInInstance then
    local inInst = IsInInstance()
    if inInst then return nil end
  end
  local map = PlayerMap()
  if not map then return nil end
  if nearCache.map ~= map or now - nearCache.t > 2 then
    local inn, d = NearInn(map)
    nearCache = { map = map, t = now, inn = inn, d = d }
  end
  local inn, d = nearCache.inn, nearCache.d
  if not inn or not d or d > NEAR then return nil end
  local sub = ("Mail %d item(s) to %s"):format(state.n, state.alt or "your alt")
  local P = ns.Path
  local best, bd
  for _, b in ipairs((DB.mailboxes and DB.mailboxes[map]) or {}) do
    local br, dist = P.Vector(map, b[1], b[2])
    if br and (not bd or dist < bd) then best, bd = b, dist end
  end
  if best then
    return { kind = "mail", p = { best[1], best[2] }, m = map, title = "Mailbox", sub = sub }
  end
  local x, y = P.Inn.XY(inn)
  return { kind = "mail", p = { x, y }, m = map, title = "Mailbox near " .. inn[1], sub = sub .. " (mailbox is usually by the inn)" }
end

-- ------------------------------------------------------------ mailing
local send = nil
local mailOpen = false

local function SendFn() return (C_SendMail and C_SendMail.SendMail) or SendMail end
local function ClickAttach()
  local f = (C_SendMail and C_SendMail.ClickSendMailItemButton) or ClickSendMailItemButton
  if f then f() return true end
end
local function Attached()
  local f = (C_SendMail and C_SendMail.GetSendMailItem) or GetSendMailItem
  if f then return (f(1)) end
end
local function Pickup(bag, slot)
  local f = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem
  if f then f(bag, slot) return true end
end

local function ClearSend()
  local f = (C_SendMail and C_SendMail.ClearSendMail) or ClearSendMail
  if f then pcall(f) end
end

-- The recipient text to try, best first. WoW Forever has two-part names and its mail box can reject the short saved
-- one ("Please enter a full character name"), so the saved name, name-realm and the first name are all candidates.
-- A form the game accepted before goes first; a name typed with /realm mule full goes before everything.
function Mule.Forms(name)
  local out, seen = {}, {}
  local function add(s)
    if s and s ~= "" and not seen[s:lower()] then seen[s:lower()] = true; out[#out + 1] = s end
  end
  if not name then return out end
  add(DB and DB.muleFull and DB.muleFull[name])
  add(DB and DB.muleForm and DB.muleForm[name])
  local rec
  for _, r in pairs((DB and DB.bags) or {}) do if r.name == name then rec = r break end end
  local names = (rec and rec.names) or {}
  -- a two-part name ("Aawesome AAdeals") is the whole character name here: it goes before the short one
  for _, s in ipairs(names) do
    if s:find(" ", 1, true) and not s:find("-", 1, true) then add(s) end
  end
  add(name)
  if rec and rec.full then add(rec.full) end
  for _, s in ipairs(names) do add(s) end
  -- name-realm last: the game treats it as another realm and asks "Really send...?"
  if rec and rec.realm and rec.realm ~= "" then add(name .. "-" .. rec.realm:gsub("[%s%-']", "")) end
  add(name:match("^(%S+)%s+%S"))
  return out
end

-- Is this recipient text one of YOUR saved characters (any spelling, with or without the realm)? Returns its record.
-- Spaces, dashes and apostrophes are ignored, because the game squashes the realm name ("CAMWOW US1 Realm 6 PvP" shows as
-- "CAMWOWUS1Realm6PvP" in its "Really send...?" popup).
local function Squash(s) return (tostring(s or ""):lower():gsub("[%s%-']", "")) end
function Mule.Mine(text)
  if type(text) ~= "string" or text == "" then return nil end
  local want = Squash(text)
  for _, r in pairs((DB and DB.bags) or {}) do
    if r.name then
      local c = { r.name, r.full }
      for _, s in ipairs(r.names or {}) do c[#c + 1] = s end
      if r.realm and r.realm ~= "" then c[#c + 1] = r.name .. "-" .. r.realm end
      for _, s in ipairs(c) do
        if s and Squash(s) == want then return r end
      end
    end
  end
end

local function Done(why)
  if not send then return end
  local s = send
  send = nil
  if s.sent > 0 then
    Print(("mailed %d item(s) to %s."):format(s.sent, s.alt))
  elseif why == "empty" then
    Print("nothing to mail.")
  end
  if why == "money" then Print("stopped: not enough money left for postage.") end
  if why == "failed" then
    Print("the game refused a mail" .. (s.err and (' ("' .. s.err .. '")') or "") .. "; stopped.")
    if s.err then Print("tried: " .. table.concat(s.forms or {}, ", ") .. ". If you know the exact name, type /realm mule full <name>.") end
    if not s.kind then Mule.Snooze() end       -- a failed link-check letter must not silence the item reroute
  end
  if why == "closed" then Print("mailbox closed.") end
  if s.failed > 0 and why ~= "failed" then Print(s.failed .. " item(s) could not be attached and were left in your bags."); Mule.Snooze() end
  Mule.MarkDirty()
  if Mule.RefreshUI then Mule.RefreshUI() end
  -- a link-check letter went out first: now the item run the mailbox opening wanted
  if why == "letter" and mailOpen and DB and DB.muleTo and DB.muleOn ~= false then
    C_Timer.After(0.6, function() if mailOpen and not send then Mule.Start(false) end end)
  end
end

local function KeyOf(it) return it.bag .. ":" .. it.slot .. ":" .. tostring(it.id) end

-- a letter with words and no items (the link-check mail and its answer)
local function StepLetter()
  local token = {}
  send.pending = { key = "letter", name = send.kind, count = 1, token = token }
  local fn = SendFn()
  local ok = fn and pcall(fn, send.forms[send.fi] or send.alt, send.subject, send.body)
  if not ok then send.pending = nil; return Done("failed") end
  C_Timer.After(5, function()          -- the game never confirmed
    if send and send.pending and send.pending.token == token and not send.pending.confirm then
      send.pending = nil; send.err = send.err or "no answer from the mailbox"
      Done("failed")
    end
  end)
end

function Mule.Step()
  if not send then return end
  if not mailOpen then return Done("closed") end
  if send.pending then return end
  if (GetMoney and GetMoney() or 0) < Postage() + RESERVE then return Done("money") end
  if send.kind then return StepLetter() end
  local items, total, used = Mule.Scan()
  local plan = Mule.Plan(items, Settings(total, used))
  local pick
  for _, it in ipairs(plan.list) do
    if not send.skip[KeyOf(it)] then pick = it break end
  end
  if not pick then return Done(send.sent + send.failed > 0 and "done" or "empty") end
  local key = KeyOf(pick)
  if not (Pickup(pick.bag, pick.slot) and ClickAttach()) then
    send.skip[key] = true; send.failed = send.failed + 1
    if ClearCursor then ClearCursor() end
    return C_Timer.After(0.2, Mule.Step)
  end
  C_Timer.After(0.3, function()
    if not send then return end
    if not Attached() then
      if ClearCursor then ClearCursor() end
      send.skip[key] = true; send.failed = send.failed + 1
      return Mule.Step()
    end
    local token = {}
    send.pending = { key = key, name = pick.name, count = pick.count, token = token }
    local fn = SendFn()
    local ok = fn and pcall(fn, send.forms[send.fi] or send.alt, "Realm: " .. pick.name, "")
    if not ok then send.pending = nil; return Done("failed") end
    C_Timer.After(5, function()          -- the game never confirmed: skip this one and carry on
      if send and send.pending and send.pending.token == token and not send.pending.confirm then
        send.skip[key] = true; send.failed = send.failed + 1; send.pending = nil
        Mule.Step()
      end
    end)
  end)
end

-- wait for the EMF collector (it fills your bags) to finish, then start mailing
local function Begin(tries)
  if not send then return end
  -- a link-check letter carries no items, so it never waits for the collector
  if not send.kind and ns.Mail and ns.Mail.Running and ns.Mail.Running() and tries < 30 then
    return C_Timer.After(1, function() Begin(tries + 1) end)
  end
  Mule.Step()
end

-- manual = true: the player pressed "Mail now", so the "is it time yet" rule is skipped
function Mule.Start(manual)
  if not DB then return false end
  if send then return false end
  if not mailOpen then Print("open a mailbox first.") return false end
  if InCombatLockdown and InCombatLockdown() then Print("not in combat.") return false end
  if not DB.muleTo then Print("choose an alt first: /realm mule to <name>.") return false end
  if DB.muleTo == SelfName() then Print("you cannot mail to yourself; choose another alt.") return false end
  local p = Mule.Current()
  if not manual and not p.due then return false end
  if manual and p.n == 0 then Print("nothing to mail.") return false end
  send = { alt = DB.muleTo, sent = 0, failed = 0, skip = {}, pending = nil, forms = Mule.Forms(DB.muleTo), fi = 1 }
  Begin(0)
  return true
end

local function StartLetter(kind, alt, forms, subject, body, code)
  if send or not mailOpen or not DB then return false end
  if InCombatLockdown and InCombatLockdown() then return false end
  send = { alt = alt, kind = kind, code = code, subject = subject, body = body, sent = 0, failed = 0, skip = {},
           pending = nil, forms = forms, fi = 1 }
  Begin(0)
  return true
end

-- mail the chosen alt a letter with a fresh code (needs a mailbox open)
function Mule.SendCheck()
  if not (DB and DB.muleTo) or send or not mailOpen then return false end
  local alt, me = DB.muleTo, SelfName()
  if alt == me then return false end
  local code = NewCode()
  local body = ("This letter is a test from Realm on %s.\n\nIf you can read it, %s is the right character for auction mail.\n\n"
    .. "What to do: log in on this character with Realm installed and open the mailbox. Realm answers by itself.\n"
    .. "If it does not, reply to this letter and make the subject exactly:  confirm %s\n\nCode: %s"):format(me, alt, code, code)
  return StartLetter("check", alt, Mule.Forms(alt), "Realm link check " .. code, body, code)
end

local checkTried = false     -- the link-check letter was already attempted during this mailbox visit

-- start the link check again for the chosen alt with a new code (the Re-check button and /realm mule verify)
function Mule.Recheck()
  if not (DB and DB.muleTo) then Print("choose an alt first.") return false end
  DB.muleLink = DB.muleLink or {}
  local old = DB.muleLink[DB.muleTo]
  DB.muleLink[DB.muleTo] = { state = "unsent", named = old and old.named or nil, namedAt = old and old.namedAt or nil }
  checkTried = false
  if not mailOpen then
    Print("open a mailbox and the link-check letter goes to " .. DB.muleTo .. ".")
  elseif send then
    Print("another mail is still being sent; try again in a moment.")
  elseif not Mule.SendCheck() then
    Print("could not send the letter right now; try again in a moment.")
  end
  Mule.MarkDirty()
  if Mule.RefreshUI then Mule.RefreshUI() end
  return true
end

function Mule.Stop() if send then Done("stopped") end end
function Mule.Sending() return send ~= nil end
function Mule._SetOpen(v) mailOpen = v and true or false end
function Mule.MailIsOpen() return mailOpen end

local letterTried = {}       -- codes already attempted since this mailbox opened: a refused letter is not retried in a loop

local function OnSendSuccess()
  if not (send and send.pending) then return end
  if send.kind == "check" then
    local l = LinkOf(send.alt)
    l.state, l.code, l.sentAt, l.via = "sent", send.code, Stamp(), nil
    DB.muleForm = DB.muleForm or {}
    DB.muleForm[send.alt] = send.forms[send.fi]
    Print(("the game accepted link-check letter %s for \"%s\" (saved character %s). It is a delivery test: log in on %s and open its mailbox; Realm answers it."):format(
      send.code, tostring(send.forms[send.fi]), send.alt, send.alt))
    send.pending = nil
    return Done("letter")
  elseif send.kind == "reply" then
    DB.muleReplied = DB.muleReplied or {}
    DB.muleReplied[send.code] = true
    Print(("answered the link check from %s (confirm %s). Open the mailbox on that character to finish."):format(send.alt, send.code))
    send.pending = nil
    return Done("letter")
  end
  DB.muleForm = DB.muleForm or {}
  DB.muleForm[send.alt] = send.forms[send.fi]        -- remember the spelling the game accepted
  send.sent = send.sent + 1
  send.pending = nil
  C_Timer.After(0.4, Mule.Step)
end

-- The game printed an error while a mail was waiting for its answer: it refused the mail. A recipient complaint moves on
-- to the next spelling of the name; anything else stops the run and shows the game's own words.
local function OnMailError(msg)
  if not (send and send.pending) or type(msg) ~= "string" then return end
  local s = send        -- ClearSend can fire game events that end the run, so hold our own reference
  s.err = msg
  local l = msg:lower()
  local recipient = l:find("name", 1, true) or l:find("recipient", 1, true) or l:find("player", 1, true)
    or l:find("character", 1, true) or l:find("not found", 1, true)
  ClearSend()
  if send ~= s then return end        -- the run ended while the form was cleared: nothing left to retry
  if recipient and s.forms and s.forms[s.fi + 1] then
    s.fi = s.fi + 1
    s.pending = nil
    Print(("the game said \"%s\"; trying \"%s\"."):format(msg, s.forms[s.fi]))
    return C_Timer.After(0.2, Mule.Step)
  end
  s.pending = nil
  Done("failed")
end

-- The game can answer a mail with a popup instead of an error: "This character might be someone you don't know. Really
-- send <name>?" It shows when it does not recognise the name as one of your characters (a realm spelling does that), so
-- the right name is probably a different spelling. While another spelling is left, cancel it and try that one. On the
-- last spelling leave the popup for the player: only they know whether that character is theirs.
-- press Accept on the popup the game just showed; true when it was pressed
local function AcceptPopup(which)
  local frame
  if StaticPopup_Visible then
    local ok, _, f = pcall(StaticPopup_Visible, which)
    if ok then frame = f end
  end
  if not frame then return false end
  if frame.button1 and frame.button1.Click then return pcall(frame.button1.Click, frame.button1) end
  if StaticPopup_OnClick then return pcall(StaticPopup_OnClick, frame, 1) end
  return false
end

local function OnConfirmPopup(which, a1, a2)
  if not (send and send.pending) then return end
  -- the name in the popup is one of your own saved characters, and it is the alt Realm is mailing: it is the right
  -- character, so accept for the player (the game asks because it cannot tell it is on the same account)
  local mine = Mule.Mine(a1) or Mule.Mine(a2)
  if mine and mine.name == send.alt and AcceptPopup(which) then
    send.pending.confirm = true
    Print(('the game asked to confirm sending to "%s"; that is your saved character %s, so Realm confirmed it.'):format(tostring(Mule.Mine(a1) and a1 or a2), mine.name))
    return
  end
  local form = send.forms[send.fi] or send.alt
  if not (type(a1) == "string" and form and a1:lower():find(form:lower(), 1, true)) then return end
  if send.forms[send.fi + 1] then
    if StaticPopup_Hide then pcall(StaticPopup_Hide, which) end
    local s = send
    ClearSend()
    if send ~= s then return end        -- the run ended while the form was cleared
    s.fi = s.fi + 1
    s.pending = nil
    Print(('the game asked to confirm sending to "%s", so it does not know that name as your character; trying "%s".'):format(form, s.forms[s.fi]))
    C_Timer.After(0.2, Mule.Step)
  else
    send.pending.confirm = true
    Print(('the game is asking you to confirm sending to "%s". Confirm only if that is your alt. If not, cancel and type /realm mule full <exact name>.'):format(form))
  end
end
Mule._Popup = OnConfirmPopup

-- ------------------------------------------------------------ link check: reading the inbox
-- On the character that sent the letter: an answer "confirm <CODE>" with the right code confirms the link.
-- On the alt: a letter "Realm link check <CODE>" from one of your own characters is answered. force = the player typed
-- /realm mule confirm: answer it even when the sender is not a saved character.
local function InboxLetters()
  local out = {}
  if not (GetInboxNumItems and GetInboxHeaderInfo) then return out end
  for i = 1, (GetInboxNumItems() or 0) do
    local _, _, sender, subject = GetInboxHeaderInfo(i)
    if type(subject) == "string" then out[#out + 1] = { sender = sender, subject = subject } end
  end
  return out
end

function Mule.CheckInbox(force)
  if not (DB and mailOpen) then return end
  local me = SelfName()
  for _, m in ipairs(InboxLetters()) do
    -- the answer to a letter this character sent
    local word, c = m.subject:match("^%s*(%a+)%s+(%w+)%s*$")
    if word and word:lower() == "confirm" then
      c = c:upper()
      for alt, l in pairs(DB.muleLink or {}) do
        if l.state == "sent" and l.code == c then
          l.state, l.verifiedAt, l.via, l.code = "verified", Stamp(), m.sender, nil
          Print(("link confirmed: %s answered the test letter (from \"%s\"). That is your AH alt."):format(alt, tostring(m.sender)))
          if Mule.RefreshUI then Mule.RefreshUI() end
        end
      end
    end
    -- a letter for this character to answer
    local lc = m.subject:match("^%s*[Rr]ealm link check (%w+)%s*$")
    local sender = m.sender
    if lc and sender and sender ~= "" and Squash(sender) ~= Squash(me) then
      lc = lc:upper()
      local replied = DB.muleReplied and DB.muleReplied[lc]
      if not replied and not send and (force or not letterTried[lc]) then
        local rec = Mule.Mine(sender)
        if rec or force then
          letterTried[lc] = true
          local forms, seen = { sender }, { [sender:lower()] = true }
          if rec then
            for _, f in ipairs(Mule.Forms(rec.name)) do
              if not seen[f:lower()] then seen[f:lower()] = true; forms[#forms + 1] = f end
            end
          end
          StartLetter("reply", rec and rec.name or sender, forms, "confirm " .. lc,
            ("Answer from %s to the Realm link check %s. Nothing to do: open your mailbox on the character that sent it."):format(me, lc), lc)
          return
        else
          letterTried[lc] = true
          Print(("a link-check letter came from \"%s\", who is not one of your saved characters, so Realm left it. If it is yours, type /realm mule confirm."):format(sender))
        end
      end
    end
  end
end

-- one line for the window and /realm mule status
function Mule.LinkText(alt)
  local l = alt and DB and DB.muleLink and DB.muleLink[alt]
  if l and l.state == "verified" then
    return ("|cff33ff33Link check: confirmed, %s answered%s.|r"):format(alt, l.via and (" from " .. l.via) or ""), "verified"
  end
  local pre = "Link check: " .. ((l and l.named) and "|cff33ff33Name confirmed (you logged in on it).|r "
    or ("|cffffd100Log in on " .. tostring(alt) .. " once to confirm the name; auto-mail waits for that.|r "))
  if not l or l.state == "unsent" then
    return pre .. "|cff888888A test letter goes out when you open a mailbox.|r", "unsent"
  end
  return pre .. ("|cffffd100Test letter %s accepted by the game; open %s's mailbox to finish it.|r"):format(l.code or "?", alt), "sent"
end

-- Logged in on the chosen AH alt: the name the player picked is the character they are playing, so it is exact and
-- auto-mail is allowed. This needs no mail at all.
function Mule.NoteLogin()
  if not (DB and DB.muleTo) then return false end
  if Squash(DB.muleTo) ~= Squash(SelfName()) then return false end
  local l = LinkOf(DB.muleTo)
  if l.named then return false end
  l.named, l.namedAt = true, Stamp()
  Print(("you are logged in on %s, your chosen AH alt: the name is confirmed and auto-mail is on."):format(DB.muleTo))
  Mule.MarkDirty()
  if Mule.RefreshUI then Mule.RefreshUI() end
  return true
end

-- ------------------------------------------------------------ small window (alt picker and Mail now)
local win, ROWS = nil, 8

local function ClassTag(a)
  return (a.class and (a.class:sub(1, 1) .. a.class:sub(2):lower()) or "?") .. (a.level and (" " .. a.level) or "")
end

function Mule.RefreshUI()
  if not win or not DB then return end
  local alts = Mule.Alts()
  for i = 1, ROWS do
    local r, a = win.rows[i], alts[i]
    if a then
      local picked = DB.muleTo == a.name
      local mark = picked and "|cff33ff33> |r" or "  "
      r.alt = a.name
      local to = Mule.Forms(a.name)[1]
      local shown = (to and to:lower() ~= a.name:lower()) and ("  |cff7fd4ff-> " .. to .. "|r") or ""
      -- green when this is the character mail will go to and it is one of your own saved characters
      local name = (picked and Mule.Mine(a.name)) and ("|cff33ff33" .. a.name .. "|r") or a.name
      r.text:SetText(mark .. name .. shown .. " |cff888888" .. ClassTag(a) .. "|r")
      r:Show()
    else
      r.alt = nil; r:Hide()
    end
  end
  win.empty:SetText(#alts == 0 and "No other characters seen yet. Log in on your AH alt once, then come back." or "")
  win.auto:SetText("Auto-mail: " .. (DB.muleOn == false and "off" or "ON"))
  local p = Mule.Current()
  win.status:SetText(p.n .. " stack(s) can go" .. (p.n > 0 and (", postage " .. ns.Coin(p.cost)) or "")
    .. (p.why and ("\n|cff888888" .. p.why .. "|r") or "\nReady: the compass will send you to a mailbox.")
    .. (DB.muleTo and ("\nMail goes to: " .. (Mule.Mine(DB.muleTo) and "|cff33ff33" or "|cffff5555")
      .. (Mule.Forms(DB.muleTo)[1] or DB.muleTo) .. "|r"
      .. (Mule.Mine(DB.muleTo) and " |cff33ff33(your alt)|r" or " |cffff5555(not one of your saved characters)|r")
      .. "\n" .. (Mule.LinkText(DB.muleTo))) or ""))
  win.now:SetText(send and "Stop" or ("Mail now (" .. p.n .. ")"))
end

local function Build()
  local f = CreateFrame("Frame", "RealmMuleWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(260, 194 + ROWS * 20)
  f:SetPoint("CENTER", 0, 0)
  f:SetFrameStrata("HIGH"); f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if ns.UI and ns.UI.Skin then ns.UI.Skin(f) end
  local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("TOPLEFT", 10, -9); t:SetText("Mule: mail to your AH alt")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() f:Hide() end)
  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 10, -30); hint:SetWidth(240); hint:SetJustifyH("LEFT")
  hint:SetText("Click the character that runs your auctions. Armor, weapons and crafting goods you cannot use go to them.")
  f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.empty:SetPoint("TOPLEFT", 10, -72); f.empty:SetWidth(240); f.empty:SetJustifyH("LEFT")
  f.rows = {}
  for i = 1, ROWS do
    local r = CreateFrame("Button", nil, f)
    r:SetSize(240, 18); r:SetPoint("TOPLEFT", 10, -62 - (i - 1) * 20)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 0, 0)
    r:SetScript("OnClick", function() if r.alt then Mule.SetAlt(r.alt) end end)
    f.rows[i] = r
  end
  f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.status:SetPoint("BOTTOMLEFT", 10, 66); f.status:SetWidth(240); f.status:SetJustifyH("LEFT")
  f.recheck = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.recheck:SetSize(240, 22); f.recheck:SetPoint("BOTTOMLEFT", 10, 38)
  f.recheck:SetText("Re-check this alt (send a new test letter)")
  f.recheck:SetScript("OnClick", function() Mule.Recheck() end)
  f.auto = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.auto:SetSize(110, 22); f.auto:SetPoint("BOTTOMLEFT", 10, 10)
  f.auto:SetScript("OnClick", function() DB.muleOn = (DB.muleOn == false); Mule.MarkDirty(); Mule.RefreshUI() end)
  f.now = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.now:SetSize(120, 22); f.now:SetPoint("BOTTOMRIGHT", -10, 10)
  f.now:SetScript("OnClick", function() if send then Mule.Stop() else Mule.Start(true) end; Mule.RefreshUI() end)
  f:Hide()
  return f
end

function Mule.Show(show)
  if not DB then return end
  win = win or Build()
  if show == nil then show = not win:IsShown() end
  if show then
    local emf = _G.RealmMailEMF
    if mailOpen and emf and emf:IsShown() then
      win:ClearAllPoints(); win:SetPoint("TOPLEFT", emf, "BOTTOMLEFT", 0, -4)
    end
    win:Show(); Mule.RefreshUI()
  else win:Hide() end
end
function Mule.Window() return win end

-- ------------------------------------------------------------ commands
local function IdOf(text)
  if not text or text == "" then return nil end
  return tonumber(text:match("item:(%d+)")) or tonumber(text:match("^%s*(%d+)%s*$"))
end

function Mule.Command(arg)
  local orig = arg or ""
  arg = orig:lower()
  local sub, rest = arg:match("^(%S*)%s*(.-)$")
  if not DB then return end
  if sub == "" then Mule.Show()
  elseif sub == "full" then
    -- the exact recipient text to send to, for when the game wants a different spelling of the alt's name
    local typed = orig:match("^%s*%S+%s*(.-)%s*$")
    if not DB.muleTo then Print("choose an alt first: /realm mule to <name>.")
    elseif typed == "" then
      DB.muleFull = DB.muleFull or {}; DB.muleFull[DB.muleTo] = nil
      Print("recipient for " .. DB.muleTo .. " back to automatic. Tries: " .. table.concat(Mule.Forms(DB.muleTo), ", "))
    else
      DB.muleFull = DB.muleFull or {}; DB.muleFull[DB.muleTo] = typed
      Print("mail to " .. DB.muleTo .. " will be addressed to \"" .. typed .. "\".")
    end
  elseif sub == "to" then
    local name = Mule.FindAlt(rest)
    if name then Mule.SetAlt(name)
    else Print("I have not seen a character like '" .. rest .. "'. Log in on it once so Realm can see it.") end
  elseif sub == "on" or sub == "off" then
    DB.muleOn = (sub == "on"); Mule.MarkDirty(); Print("auto-mail: " .. (DB.muleOn and "ON" or "off"))
  elseif sub == "now" then Mule.Start(true)
  elseif sub == "later" then Mule.Snooze(); Print("no mailbox reroute for 20 minutes.")
  elseif sub == "min" then
    local v = tonumber(rest)
    if v and v >= 1 and v <= 40 then DB.muleMin = math.floor(v); Mule.MarkDirty(); Print("reroute once " .. DB.muleMin .. " stack(s) are waiting.")
    else Print("Usage: /realm mule min 6") end
  elseif sub == "keep" then
    local id = IdOf(rest)
    if id then DB.muleKeep[id] = true; Mule.MarkDirty(); Print("item " .. id .. " will never be mailed.") else Print("Usage: /realm mule keep <item link or id>") end
  elseif sub == "send" then
    local id = IdOf(rest)
    if id then DB.muleKeep[id] = nil; Mule.MarkDirty(); Print("item " .. id .. " may be mailed again.") else Print("Usage: /realm mule send <item link or id>") end
  elseif sub == "ok" or sub == "allow" then
    local id = IdOf(rest)
    if id then Mule.Approve(id, rest:match("%[(.-)%]")); Print("item " .. id .. " is on the send list.") else Print("Usage: /realm mule ok <item link or id>") end
  elseif sub == "unok" or sub == "disallow" then
    local id = IdOf(rest)
    if id and Mule.Unapprove(id) then Print("item " .. id .. " is off the send list.") else Print("Usage: /realm mule unok <item link or id> (it must be on the list)") end
  elseif sub == "list" then Mule.ShowList()
  elseif sub == "status" then
    local p = Mule.Current()
    Print(("alt: %s | auto: %s | %d stack(s) can go | postage %s | %s"):format(
      DB.muleTo or "none", DB.muleOn == false and "off" or "on", p.n, ns.Coin(p.cost), p.why or "due"))
    if DB.muleTo then
      Print("addressed as: " .. table.concat(Mule.Forms(DB.muleTo), "  >  "))
      Print((Mule.LinkText(DB.muleTo):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
    end
  elseif sub == "verify" then
    -- start the link check again with a new code (use it if the first letter was lost)
    if not DB.muleTo then Print("choose an alt first: /realm mule to <name>.")
    else Mule.Recheck() end
  elseif sub == "confirm" then
    -- on the alt: answer the link-check letter by hand (Realm normally does it by itself)
    if not mailOpen then Print("open a mailbox first.")
    else
      letterTried = {}
      Mule.CheckInbox(true)
      if not send then Print("no link-check letter waiting in this mailbox.") end
    end
  elseif sub == "who" then
    -- what the game says each character is called: run it on the alt to see the whole name the game gives
    local B = ns.Bags
    if B and B.NameDiag then
      Print("this character (" .. (UnitName and UnitName("player") or "?") .. "):")
      for _, l in ipairs(B.NameDiag()) do Print("  " .. l) end
    end
    for _, r in pairs(DB.bags or {}) do
      if r.name and r.name ~= (UnitName and UnitName("player")) then
        Print(r.name .. ": " .. ((r.names and #r.names > 0) and table.concat(r.names, "  |  ") or "no names saved yet, log in on it once"))
        for _, l in ipairs(r.diag or {}) do Print("  " .. l) end
      end
    end
  else Print("/realm mule (window) | to <name> | full <exact name> | on | off | now | later | min <n> | keep <item> | send <item> | ok <item> | unok <item> | list | status | who | verify | confirm") end
end

-- ------------------------------------------------------------ events
local hooked = false
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_FAILED", "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD", "PLAYER_MONEY", "UI_ERROR_MESSAGE", "MAIL_INBOX_UPDATE" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, e, a1, a2)
  if e == "PLAYER_LOGIN" then
    DB = ns.DB
    DB.muleKeep = DB.muleKeep or {}
    DB.muleOk = DB.muleOk or {}
    DB.muleAsked = DB.muleAsked or {}
    DB.muleForm = DB.muleForm or {}
    DB.muleFull = DB.muleFull or {}
    -- a remembered realm spelling ("Name-Realm") is the one that makes the game ask "Really send...?": forget it
    for k, v in pairs(DB.muleForm) do
      if type(v) == "string" and v:find("-", 1, true) then DB.muleForm[k] = nil end
    end
    if hooksecurefunc and not hooked then
      hooked = true
      pcall(hooksecurefunc, "StaticPopup_Show", function(...) OnConfirmPopup(...) end)
    end
    DB.mailboxes = DB.mailboxes or {}
    if DB.muleOn == nil then DB.muleOn = true end
  elseif not DB then return
  elseif e == "MAIL_SHOW" then
    mailOpen = true
    local map = PlayerMap()
    if map then
      local x, y = PlayerXY(map)
      if x then Mule.LearnBox(map, x, y) end
    end
    Mule.MarkDirty()
    checkTried = false
    C_Timer.After(0.5, function()
      if not mailOpen then return end
      if not DB.muleTo then Mule.Show(true) end        -- first time: ask which alt
      Mule.CheckInbox()
      -- the link-check letter goes first (once per mailbox visit); when it is done the item run follows
      local l = DB.muleTo and LinkOf(DB.muleTo)
      local stale = l and l.state == "sent" and (Stamp() - (l.sentAt or 0)) > CHECK_DAYS * 86400
      if l and (l.state == "unsent" or stale) and not checkTried and not send and DB.muleTo ~= SelfName() then
        checkTried = true
        if Mule.SendCheck() then Mule.RefreshUI() return end
        Print("could not start the link-check letter to " .. DB.muleTo .. " (another mail is still being sent). Press Re-check in the Mule window.")
      elseif l then
        -- say where the link stands, so a silent mailbox never looks like a bug
        local txt = Mule.LinkText(DB.muleTo):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        if DB.muleTo == SelfName() then txt = "you are logged in on " .. DB.muleTo .. ", the chosen alt; pick another character" end
        if not l.seenShown or l.state ~= l.seenShown then l.seenShown = l.state; Print(txt) end
      end
      -- ask once about each item that could be mailed but is held back; the answer is the Send list
      local fresh = 0
      for _, h in ipairs(Mule.Held()) do
        if not DB.muleAsked[h.id] then DB.muleAsked[h.id] = true; fresh = fresh + 1 end
      end
      if fresh > 0 and DB.muleTo then
        Print(fresh .. " item(s) in your bags could go to your alt but are held back (you can use them, or Realm was not sure). Press Send list to choose which may be mailed.")
      end
      Mule.RefreshListButtons()
      if DB.muleTo and DB.muleOn ~= false and not (IsShiftKeyDown and IsShiftKeyDown()) then Mule.Start(false) end
      Mule.RefreshUI()
    end)
  elseif e == "MAIL_INBOX_UPDATE" then
    Mule.CheckInbox()
  elseif e == "MAIL_CLOSED" then
    mailOpen = false
    if send then Done("closed") end
    if win then win:Hide() end
  elseif e == "MAIL_SEND_SUCCESS" then OnSendSuccess()
  elseif e == "UI_ERROR_MESSAGE" then OnMailError((type(a2) == "string" and a2) or (type(a1) == "string" and a1) or nil)
  elseif e == "MAIL_FAILED" then
    if send then Done("failed") end
  else
    dirty = true            -- bags or money changed: the next compass tick re-reads them
    if e == "PLAYER_ENTERING_WORLD" then
      nearCache = { t = -1000 }
      C_Timer.After(3, function() Mule.NoteLogin() end)
    end
  end
end)
