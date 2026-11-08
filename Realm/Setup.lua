-- Realm setup: the one-time "what do you want turned on?" window. Shown once per character on first login after
-- install (or an upgrade that adds new features), and any time with /realm setup. Nothing is changed until you press Apply.
local ADDON, ns = ...
local Setup = {}
ns.Setup = Setup

local frame, pick = nil, {}

local function Print(m) if ns.Print then ns.Print(m) end end

local function CharRec()
  local TB = ns.TB
  return TB and TB.Char and TB.Char() or nil
end

-- the questions, in order. get() reads today's value; set(v) applies a chosen one.
local function Items()
  local TB = ns.TB
  local O = ns.Path and ns.Path.Opts and ns.Path.Opts() or {}
  return {
    { key = "macros", label = "Auto-macros on the main bar pages",
      tip = "Builds rotation macros for your class and spec: page 1 solo, 2 party, 3 battlegrounds, 4 small dungeon, 5 raid. Replaces the first buttons on each page.",
      get = function() return TB and TB.Macros and TB.Macros.Store().installed or false end,
      def = true, show = function() return TB and TB.Macros and TB.Class and TB.Class() end,
      set = function(v) if v and TB.Macros then TB.Macros.SetAuto(true); TB.Macros.Install({ take = true }) end end },
    { key = "macroauto", label = "Update macros when I learn new skills",
      tip = "Rebuilds the macros after you buy a spell, change talents or level up. Never touches a macro you edited.",
      get = function() return TB and TB.Macros and TB.Macros.AutoOn() end, def = true,
      show = function() return TB and TB.Macros end,
      set = function(v) if TB.Macros then TB.Macros.SetAuto(v) end end },
    { key = "leveler", label = "The Leveler: route, compass and quest helper",
      tip = "The top-centre compass and the leveling route, with quest accept and hand-in automation.",
      get = function() return O.hud ~= false end, def = true,
      show = function() return ns.Path and ns.Path.Opts and ns.Path.Opts() end,
      set = function(v)
        local o = ns.Path.Opts(); o.hud = v and true or false; o.panel = v and true or false
        if ns.Path.Changed then pcall(ns.Path.Changed, true) end
      end },
    { key = "flights", label = "Detour to flight masters I have not found",
      tip = "While you travel, the compass first points you at a town's flight master if you have never opened it.",
      get = function() return O.discoverFlights and true or false end, def = false,
      show = function() return ns.Path and ns.Path.Opts and ns.Path.Opts() end,
      set = function(v) ns.Path.Opts().discoverFlights = v and true or false end },
    { key = "sell", label = "Auto-sell junk and auto-repair at vendors",
      tip = "Sells grey items and repairs when you open a vendor.",
      get = function() return ns.DB and ns.DB.autoSell and ns.DB.autoRepair end, def = true,
      show = function() return ns.DB end,
      set = function(v) ns.DB.autoSell = v and true or false; ns.DB.autoRepair = v and true or false end },
    { key = "bags", label = "One bag with sorting and alt tabs",
      tip = "Your bag keys open one combined bag with sorting, search and a tab for every character you have played.",
      get = function() return ns.Bags and ns.Bags.On() end, def = false,
      show = function() return ns.Bags end,
      set = function(v) if ns.Bags then ns.Bags.Set(v) end end },
    { key = "mail", label = "Mail helper (EMF): auto-collect and clean up",
      tip = "Opens your mailbox contents for you, deletes a mail only after its items and money are confirmed taken, and keeps an auction tally.",
      get = function() return ns.DB and ns.DB.emfAuto end, def = true,
      show = function() return ns.Mail end,
      set = function(v) ns.DB.emfAuto = v and true or false; ns.DB.emfDelete = true end },
  }
end

-- apply a { key = true/false } table; keys not present are left alone. Returns the keys it changed.
function Setup.Apply(choices)
  local changed = {}
  for _, it in ipairs(Items()) do
    local v = choices[it.key]
    if v ~= nil and (not it.show or it.show()) then
      local ok, err = pcall(it.set, v)
      if ok then changed[#changed + 1] = it.key else Print("setup: " .. it.key .. " failed: " .. tostring(err)) end
    end
  end
  return changed
end

function Setup.Done()
  local rec = CharRec()
  if rec then rec.setupDone = true end
end

local function Refresh()
  if not frame then return end
  for _, row in ipairs(frame.rows) do
    local v = pick[row.item.key]
    row.btn:SetText(v and "ON" or "OFF")
  end
end

local function Build()
  local f = CreateFrame("Frame", "RealmSetup", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(470, 120)
  f:SetPoint("CENTER", 0, 60)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if ns.UI and ns.UI.Skin then ns.UI.Skin(f) end
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetPoint("TOPLEFT", 14, -12); f.title:SetText("Realm setup")
  f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.sub:SetPoint("TOPLEFT", 14, -36); f.sub:SetWidth(440); f.sub:SetJustifyH("LEFT")
  f.sub:SetText("Choose what you want on. Nothing changes until you press Apply. You can run /realm setup again any time.")
  f.rows = {}
  f:Hide()
  return f
end

function Setup.Show()
  if not (ns.DB and ns.TB) then return end
  frame = frame or Build()
  for _, r in ipairs(frame.rows) do r.label:Hide(); r.btn:Hide() end
  frame.rows = {}
  local y = -64
  for _, it in ipairs(Items()) do
    if not it.show or it.show() then
      if pick[it.key] == nil then
        local cur = it.get()
        -- first time through: macros default to the recommended answer, everything else to what is set now
        if it.key == "macros" or it.key == "macroauto" then pick[it.key] = it.def else pick[it.key] = cur and true or false end
      end
      local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      label:SetPoint("TOPLEFT", 14, y); label:SetText(it.label)
      local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
      btn:SetSize(54, 20); btn:SetPoint("TOPRIGHT", -14, y + 4)
      btn:SetScript("OnClick", function() pick[it.key] = not pick[it.key]; Refresh() end)
      btn:SetScript("OnEnter", function(self)
        if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText(it.label, 1, 1, 1); GameTooltip:AddLine(it.tip, .8, .8, .8, true); GameTooltip:Show() end
      end)
      btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
      frame.rows[#frame.rows + 1] = { item = it, label = label, btn = btn }
      y = y - 26
    end
  end
  if not frame.apply then
    local apply = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    apply:SetSize(110, 24); apply:SetText("Apply")
    apply:SetScript("OnClick", function()
      local done = Setup.Apply(pick)
      Setup.Done()
      frame:Hide()
      Print(("setup applied (%d item(s)). /realm setup opens this again."):format(#done))
    end)
    frame.apply = apply
    local later = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    later:SetSize(110, 24); later:SetText("Not now")
    later:SetScript("OnClick", function()
      Setup.Done(); frame:Hide()
      Print("nothing changed. /realm setup opens this again.")
    end)
    frame.later = later
  end
  frame.apply:ClearAllPoints(); frame.apply:SetPoint("BOTTOMRIGHT", -14, 12)
  frame.later:ClearAllPoints(); frame.later:SetPoint("RIGHT", frame.apply, "LEFT", -8, 0)
  frame:SetHeight(-y + 50)
  frame:Show(); Refresh()
end

function Setup.Command() Setup.Show() end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  C_Timer.After(8, function()
    local rec = CharRec()
    if not rec or rec.setupDone then return end
    if InCombatLockdown and InCombatLockdown() then return end
    Setup.Show()
  end)
end)
