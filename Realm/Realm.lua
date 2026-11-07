-- Realm: auto-sell junk + auto-repair. Works on Retail and all Classic clients.
local ADDON, ns = ...

local defaults = { autoSell = true, autoRepair = true, useGuild = true, quiet = false }
local DB
local sessionSold, sessionRepair = 0, 0

-- Cross-version bag API shims
local CC = C_Container
local NumSlots = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
local UseItem  = (CC and CC.UseContainerItem) or UseContainerItem
local function SlotInfo(bag, slot)
  if CC and CC.GetContainerItemInfo then
    local i = CC.GetContainerItemInfo(bag, slot)
    if i then return i.hyperlink, i.quality, i.stackCount or 1, i.hasNoValue end
  else
    local _, count, _, quality, _, _, link, _, noValue = GetContainerItemInfo(bag, slot)
    return link, quality, count or 1, noValue
  end
end

local function Print(msg)
  print("|cffe8ab35Realm:|r " .. msg)
end
ns.Print = Print
local function Money(c) return GetCoinTextureString and GetCoinTextureString(c) or (c .. "c") end

-- GetItemInfo moved to C_Item on newer clients; the old global can be nil there
local function ItemPrice(link)
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f, g, h, i, j, price = pcall(fn, link)
  if ok then return price end
end

local function SellJunk()
  local total, count = 0, 0
  for bag = 0, 5 do
    for slot = 1, (NumSlots(bag) or 0) do
      local link, quality, stack, noValue = SlotInfo(bag, slot)
      if link and quality == 0 and not noValue then
        local price = ItemPrice(link)
        if price and price > 0 then
          total = total + price * stack
          count = count + 1
          UseItem(bag, slot)
        end
      end
    end
  end
  if count > 0 then
    sessionSold = sessionSold + total
    if not DB.quiet then Print(("Sold %d junk item(s) for %s"):format(count, Money(total))) end
  end
end

local function Repair()
  if not (CanMerchantRepair and CanMerchantRepair()) then return end
  local cost, canRepair = GetRepairAllCost()
  if not canRepair or cost <= 0 then return end
  local guild = DB.useGuild and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair()
    and GetGuildBankWithdrawMoney and (GetGuildBankWithdrawMoney() == -1 or GetGuildBankWithdrawMoney() >= cost)
  if guild then
    RepairAllItems(true)
    if not DB.quiet then Print("Repaired for " .. Money(cost) .. " (guild funds)") end
  elseif GetMoney() >= cost then
    RepairAllItems()
    sessionRepair = sessionRepair + cost
    if not DB.quiet then Print("Repaired for " .. Money(cost)) end
  else
    Print("Not enough gold to repair (" .. Money(cost) .. ")")
  end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("MERCHANT_SHOW")
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    RealmDB = RealmDB or {}
    DB = RealmDB
    -- one-time import of the old WowForever settings
    if not DB.imported and WowForeverDB then
      DB.imported = true
      for k, v in pairs(WowForeverDB) do if DB[k] == nil then DB[k] = v end end
    end
    ns.DB = DB
    for k, v in pairs(defaults) do if DB[k] == nil then DB[k] = v end end
  elseif event == "MERCHANT_SHOW" and DB then
    if DB.autoRepair then Repair() end
    if DB.autoSell then SellJunk() end
  end
end)

SLASH_REALM1, SLASH_REALM2 = "/realm", "/wf"
SlashCmdList.REALM = function(msg)
  local full = msg or ""
  local arg
  msg, arg = (msg or ""):lower():match("^%s*(%S*)%s*(%S*)")
  local keys = { sell = "autoSell", repair = "autoRepair", guild = "useGuild", quiet = "quiet" }
  if keys[msg] then
    DB[keys[msg]] = not DB[keys[msg]]
    Print(msg .. ": " .. (DB[keys[msg]] and "|cff00ff00on|r" or "|cffff4040off|r"))
  elseif msg == "ex" or msg == "exchange" then
    ns.Exchange.Command((full:lower():match("^%s*%S+%s*(.-)%s*$")))
  elseif msg == "view" then
    ns.Tracker.ToggleView()
  elseif msg == "names" then
    ns.Tracker.ToggleNames()
  elseif msg == "pins" then
    ns.Tracker.TogglePins()
  elseif msg == "where" then
    ns.Tracker.Where()
  elseif msg == "deaths" or msg == "dl" then
    ns.Deaths.Toggle()
  elseif msg == "minimap" then
    ns.Minimap.Toggle()
  elseif msg == "track" then
    ns.Tracker.SetTrack(arg == "on" and true or arg == "off" and false or nil)
  elseif msg == "window" then
    ns.Tracker.Show()
  elseif msg == "scale" then
    ns.Tracker.SetScale(arg)
  elseif msg == "macros" or msg == "macro" then
    if ns.TB and ns.TB.Macros then ns.TB.Macros.Command((full:lower():match("^%s*%S+%s*(.-)%s*$"))) end
  elseif msg == "stats" then
    Print(("This session: sold junk for %s, spent %s on repairs."):format(Money(sessionSold), Money(sessionRepair)))
  else
    Print("Deaths: /realm deaths (or /dl) | /dl total | /dl quiet | /dl reset")
    Print("Commands: /realm sell | repair | guild | quiet | stats")
    Print("Macros: /realm macros | status | show | spec <name> | force | remove | autoupdate on/off")
    Print("Exchange: /realm ex (market window) | /realm ex help | /realm minimap")
    Print("Tracker: /realm view | pins | names | where | window | track [on/off] | scale <0.7-3>")
    Print(("sell=%s repair=%s guild=%s quiet=%s"):format(tostring(DB.autoSell), tostring(DB.autoRepair), tostring(DB.useGuild), tostring(DB.quiet)))
  end
end


-- If the game ever blocks one of our actions, say which one so it can be fixed.
do
  local f = CreateFrame("Frame")
  f:RegisterEvent("ADDON_ACTION_BLOCKED"); f:RegisterEvent("ADDON_ACTION_FORBIDDEN")
  f:SetScript("OnEvent", function(_, ev, addon, func)
    if addon == ADDON then ns.Print("blocked by the game: " .. tostring(func) .. " (" .. ev .. ")") end
  end)
end
