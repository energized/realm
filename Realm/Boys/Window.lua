-- TheBoys: main window. Flat dark style, class-colored accent, tabs, card rows.
local ADDON, ns = ...
local TB = ns.TB
local Win = {}
TB.Window = Win

local W, H = 640, 600
local CONTENT_W = W - 46
local TABS = {
  { "gear", "Gear" }, { "rotation", "Rotation" }, { "cooldowns", "Cooldowns" },
  { "professions", "Professions" }, { "settings", "Settings" },
}
local GOLD, GRAY, GREEN, RED = "|cffffd24a", "|cff9a9aae", "|cff4dff9a", "|cffff5555"
local TONE_ON, TONE_OFF = { .10, .42, .27 }, { .19, .18, .26 }

local f, scroll, content, subtitle, tabBtns, band, bandLine, logo
local rows, y, used = {}, 0, 0
local current = "gear"
local build = {}

local function Num(v, d) return type(v) == "number" and v or d end

-- ---------------------------------------------------------------- row pool
local function GetRow(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Frame", nil, content)
  r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
  r.bar = r:CreateTexture(nil, "ARTWORK")
  r.bar:SetPoint("TOPLEFT"); r.bar:SetPoint("BOTTOMLEFT"); r.bar:SetWidth(3)
  r.ibg = r:CreateTexture(nil, "ARTWORK")
  r.ibg:SetColorTexture(0, 0, 0, 1)
  r.icon = r:CreateTexture(nil, "OVERLAY")
  r.icon:SetTexCoord(.07, .93, .07, .93)
  r.title = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  r.title:SetJustifyH("LEFT"); r.title:SetJustifyV("TOP")
  r.desc = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.desc:SetJustifyH("LEFT"); r.desc:SetJustifyV("TOP")
  r.right = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  r.right:SetJustifyH("RIGHT")
  r.line = r:CreateTexture(nil, "ARTWORK")
  r.line:SetPoint("BOTTOMLEFT"); r.line:SetPoint("BOTTOMRIGHT"); r.line:SetHeight(1)
  r.btn = TB.FlatButton(r, "", 64, 22)
  r.btn2 = TB.FlatButton(r, "", 52, 22)
  r:EnableMouse(true)
  r:SetScript("OnEnter", function(self)
    if self.tip and GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR"); GameTooltip:SetHyperlink(self.tip); GameTooltip:Show()
    end
  end)
  r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  rows[i] = r
  return r
end

local function Reset()
  y, used = 0, 0
  for _, r in ipairs(rows) do r:Hide() end
end

local function SetupButton(b, spec)
  b:SetLabel(spec[1]); b:SetScript("OnClick", spec[2])
  local t = spec[3]
  if t then b:SetTone(t[1], t[2], t[3]) else b:SetTone(.17, .16, .25) end
  b:Show()
end

-- o: kind "h" | "t" | "row"; row fields: icon, title, desc, right, tip, btn, btn2, bar, compact
local function Add(o)
  used = used + 1
  local r = GetRow(used)
  local kind = o.kind or "row"
  local ar, ag, ab = TB.Accent()
  r.tip = o.tip
  r.bg:Hide(); r.bar:Hide(); r.ibg:Hide(); r.icon:Hide(); r.title:Hide(); r.desc:Hide(); r.right:Hide()
  r.line:Hide(); r.btn:Hide(); r.btn2:Hide()

  local btnW = (o.btn and 70 or 0) + (o.btn2 and 56 or 0)
  local h

  if kind == "h" then
    y = y + (used == 1 and 0 or 12)
    r.bar:ClearAllPoints()
    r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -3); r.bar:SetSize(3, 18)
    r.bar:SetColorTexture(ar, ag, ab, 1); r.bar:Show()
    r.title:ClearAllPoints()
    r.title:SetPoint("TOPLEFT", r, "TOPLEFT", 12, -4)
    r.title:SetWidth(CONTENT_W - 24 - btnW)
    r.title:SetFontObject("GameFontNormalLarge")
    r.title:SetTextColor(1, 1, 1)
    r.title:SetText(o.text or ""); r.title:Show()
    r.line:SetColorTexture(ar, ag, ab, .35); r.line:Show()
    if o.btn then
      r.btn:ClearAllPoints(); r.btn:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, -2); SetupButton(r.btn, o.btn)
    end
    h = 28
  elseif kind == "t" then
    r.desc:ClearAllPoints()
    r.desc:SetPoint("TOPLEFT", r, "TOPLEFT", 6, -2)
    r.desc:SetWidth(CONTENT_W - 12)
    r.desc:SetFontObject("GameFontHighlight")
    r.desc:SetTextColor(.78, .78, .86)
    r.desc:SetText(o.text or ""); r.desc:Show()
    h = Num(r.desc:GetStringHeight(), 14) + 8
  else
    local compact = o.compact
    local indent = o.icon and (compact and 38 or 50) or 14
    local rightW = o.right and 84 or 0
    local textW = CONTENT_W - indent - rightW - btnW - 14
    r.bg:SetColorTexture(.118, .165, .22, (used % 2 == 0) and .6 or .95); r.bg:Show()
    local br, bg2, bb = unpack(o.bar or { ar * .7, ag * .7, ab * .7 })
    r.bar:ClearAllPoints()
    r.bar:SetPoint("TOPLEFT"); r.bar:SetPoint("BOTTOMLEFT"); r.bar:SetWidth(3)
    r.bar:SetColorTexture(br, bg2, bb, 1); r.bar:Show()

    r.title:ClearAllPoints()
    r.title:SetPoint("TOPLEFT", r, "TOPLEFT", indent, compact and -9 or -8)
    r.title:SetWidth(textW)
    r.title:SetFontObject("GameFontNormal")
    r.title:SetTextColor(1, .82, 0)
    r.title:SetText(o.title or ""); r.title:Show()
    local th = Num(r.title:GetStringHeight(), 14)
    local dh = 0
    if o.desc and o.desc ~= "" then
      r.desc:ClearAllPoints()
      r.desc:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -3)
      r.desc:SetWidth(textW)
      r.desc:SetFontObject("GameFontHighlightSmall")
      r.desc:SetTextColor(.62, .62, .72)
      r.desc:SetText(o.desc); r.desc:Show()
      dh = Num(r.desc:GetStringHeight(), 12) + 3
    end
    h = math.max(th + dh + 16, o.icon and (compact and 34 or 46) or 0, o.btn and 34 or 0)
    if o.icon then
      local s = compact and 24 or 30
      r.ibg:ClearAllPoints(); r.ibg:SetSize(s + 2, s + 2)
      r.ibg:SetPoint("LEFT", r, "LEFT", 10, 0)
      if o.border then r.ibg:SetColorTexture(o.border[1], o.border[2], o.border[3], 1) else r.ibg:SetColorTexture(0, 0, 0, 1) end
      r.ibg:Show()
      r.icon:ClearAllPoints(); r.icon:SetSize(s, s); r.icon:SetPoint("CENTER", r.ibg, "CENTER", 0, 0)
      r.icon:SetTexture(o.icon); r.icon:Show()
    end
    if o.btn then
      r.btn:ClearAllPoints(); r.btn:SetPoint("RIGHT", r, "RIGHT", -8, 0); SetupButton(r.btn, o.btn)
    end
    if o.btn2 then
      r.btn2:ClearAllPoints(); r.btn2:SetPoint("RIGHT", r, "RIGHT", -8 - (o.btn and 70 or 0), 0); SetupButton(r.btn2, o.btn2)
    end
    if o.right then
      r.right:ClearAllPoints()
      r.right:SetPoint("RIGHT", r, "RIGHT", -(btnW + 14), 0)
      r.right:SetWidth(rightW)
      r.right:SetFontObject(compact and "GameFontHighlightSmall" or "GameFontNormalLarge")
      r.right:SetText(o.right); r.right:Show()
    end
  end

  r:ClearAllPoints()
  r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
  r:SetSize(CONTENT_W, h)
  r:Show()
  y = y + h + (kind == "row" and 3 or 0)
end

local function Done() content:SetSize(CONTENT_W, y + 14) end
local function Header(text, btn) Add({ kind = "h", text = text, btn = btn }) end
local function Text(text) Add({ kind = "t", text = text }) end

-- ---------------------------------------------------------------- shared bits
local function NoClass()
  Header("No guide for your class yet")
  Text("TheBoys is a framework: every class is its own file in the Classes folder. All nine World of Warcraft: Forever classes are in.")
end

local function SpecLine()
  local class = TB.Class()
  if not class then return "" end
  local spec, key, mode = TB.Spec()
  local s = "|c" .. class.color .. class.name .. "|r"
  if spec then s = s .. "   " .. GRAY .. spec.name .. (spec.role and (" " .. spec.role:lower()) or "") .. "|r" .. (mode == "forced" and ("  " .. GOLD .. "forced|r") or "") end
  return s
end

local function QualityColor(link)
  local q
  if C_Item and C_Item.GetItemQualityByID then
    local id = link and tonumber(link:match("item:(%d+)"))
    if id then local ok, v = pcall(C_Item.GetItemQualityByID, id); if ok then q = v end end
  end
  if q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
    local c = ITEM_QUALITY_COLORS[q]; return { c.r, c.g, c.b }
  end
end

-- ---------------------------------------------------------------- tabs
function build.gear()
  local class = TB.Class()
  if not class then return NoClass() end
  local spec = TB.Spec()
  local G = TB.Gear
  Header("Upgrades in your bags", { "Rescan", function() G.Scan(true) end })
  Text("Scored for " .. GOLD .. spec.name .. "|r  (" .. (spec.statPriority or "") .. "). Weights are a rough guide, not a sim.")
  if #G.upgrades == 0 then
    Add({ title = GREEN .. "All good|r", desc = "Nothing in your bags beats what you wear (needs at least " .. (TB.DB.minUpgrade or 3) .. "%).",
          bar = { .3, 1, .6 } })
  end
  for _, u in ipairs(G.upgrades) do
    local desc = GOLD .. u.slotName .. "|r"
    if u.curLink then desc = desc .. "   replaces " .. u.curLink end
    if u.boe then desc = desc .. "   " .. RED .. "binds on equip|r" end
    if u.combo then desc = desc .. "   " .. GRAY .. "weapon swap|r" end
    Add({
      icon = u.icon, title = u.link, desc = desc, tip = u.link, bar = { .3, 1, .6 }, border = QualityColor(u.link),
      right = u.empty and (GREEN .. "NEW|r") or (GREEN .. "+" .. math.floor(u.pct + .5) .. "%|r"),
      btn = { "Equip", function() if G.Equip(u) then C_Timer.After(0.8, function() G.Scan(true) end) end end, TONE_ON },
      btn2 = { "Hide", function() G.Ignore(u) end },
    })
  end

  Header("What you are wearing")
  for _, slot in ipairs(G.SLOT_ORDER) do
    local link = G.worn and G.worn[slot]
    local label = G.SLOT_NAMES[slot]
    if link then
      local sc = G.wornScore and G.wornScore[slot] or 0
      Add({ compact = true, icon = GetInventoryItemTexture and GetInventoryItemTexture("player", slot) or nil,
            title = link, right = GRAY .. label .. "  " .. math.floor(sc + .5) .. "|r", tip = link,
            border = QualityColor(link), bar = { .25, .24, .35 } })
    elseif slot ~= 17 and slot ~= 18 then
      Add({ compact = true, title = RED .. "empty|r", right = GRAY .. label .. "|r", bar = { 1, .3, .3 } })
    end
  end
end

local function SpellRow(i, e)
  local name = TB.Pick(e)
  local known = TB.Known(name)
  local num = i and (GRAY .. i .. "|r  ") or ""
  Add({
    icon = TB.Icon(name),
    title = known and (num .. name) or (num .. GRAY .. name .. "|r"),
    desc = e[2],
    right = (not known) and (GRAY .. "not learned|r") or nil,
    bar = known and nil or { .3, .3, .35 },
  })
end

function build.rotation()
  local class = TB.Class()
  if not class then return NoClass() end
  local spec = TB.Spec()
  Header(spec.name .. " guide")
  Text(spec.summary)
  Add({ title = "Stat priority", desc = spec.statPriority or "", bar = { 1, .82, 0 } })

  Header("Opener")
  for i, s in ipairs(spec.opener or {}) do Add({ compact = true, title = GRAY .. i .. "|r  |cffffffff" .. s .. "|r" }) end

  Header("Single target priority")
  Text(GRAY .. "Top to bottom. Cast the first thing that is ready and useful.|r")
  for i, e in ipairs(spec.priority or {}) do SpellRow(i, e) end

  if spec.aoe and #spec.aoe > 0 then
    Header("Multiple targets")
    for _, e in ipairs(spec.aoe) do SpellRow(nil, e) end
  end

  Header("Tips")
  for _, t in ipairs(spec.tips or {}) do Add({ compact = true, title = "|cffffffff" .. t .. "|r", bar = { 1, .82, 0 } }) end

  local extras = class.extras or class.pets
  if extras then
    Header(class.extrasTitle or "Extras")
    for _, t in ipairs(extras) do Add({ compact = true, title = "|cffffffff" .. t .. "|r" }) end
  end
end

local function CDRow(e)
  local name = TB.Pick(e)
  local known = TB.Known(name)
  local status = GRAY .. "not learned|r"
  local bar
  if known then
    local s, d = TB.Cooldown(name)
    local remain = 0
    if issecretvalue and (issecretvalue(s) or issecretvalue(d)) then
      -- in combat the numbers are hidden from addons
    elseif type(s) == "number" and type(d) == "number" and s > 0 and d > 1.6 then remain = s + d - GetTime() end
    if remain > 0.5 then status = RED .. math.ceil(remain) .. "s|r"; bar = { 1, .3, .3 }
    else status = GREEN .. "ready|r"; bar = { .3, 1, .6 } end
  end
  Add({ icon = TB.Icon(name), title = known and name or (GRAY .. name .. "|r"), desc = e[3], right = status, bar = bar or { .3, .3, .35 } })
end

function build.cooldowns()
  local class = TB.Class()
  if not class then return NoClass() end
  local spec = TB.Spec()
  Header("Cooldown helper", { TB.DB.cdBar and "Bar ON" or "Bar OFF", function()
    TB.DB.cdBar = not TB.DB.cdBar; TB.Cooldowns.Refresh(); Win.Rebuild() end })
  Text("The bar on your screen shows the cooldowns you have learned. " .. GOLD .. "/boys lock|r locks or unlocks it, then drag it anywhere.")
  Header(spec.name .. " cooldowns")
  for _, e in ipairs(spec.cooldowns or {}) do CDRow(e) end
  Header("Defensives")
  for _, e in ipairs(class.utility or {}) do if e[2] == "defensive" then CDRow(e) end end
  Header("Utility")
  for _, e in ipairs(class.utility or {}) do if e[2] == "utility" then CDRow(e) end end
end

function build.professions()
  local class = TB.Class()
  if not class then return NoClass() end
  for _, ln in ipairs(TB.Professions.Lines()) do
    if ln[1] == "h" then Header(ln[2])
    elseif ln[1] == "row" then
      Add({ title = ln[2], desc = ln[3], bar = ln[4] and { .3, 1, .6 } or nil })
    else Text(ln[2]) end
  end
end

local function Toggle(label, desc, key, after)
  local on = TB.DB[key]
  Add({ title = label, desc = desc, btn = { on and "ON" or "OFF", function()
    TB.DB[key] = not TB.DB[key]
    if after then after() end
    Win.Rebuild()
  end, on and TONE_ON or TONE_OFF }, bar = on and { .3, 1, .6 } or { .3, .3, .35 } })
end

function build.settings()
  local DB = TB.DB
  Header("Gear")
  Toggle("Upgrade popups", "A comparison window pops up when a better item is in your bags. Equip or Ignore it.", "suggest")
  Add({ title = "Minimum upgrade size", desc = "How much better an item must score before it is suggested.",
        right = GOLD .. (DB.minUpgrade or 3) .. "%|r",
        btn = { "+", function() DB.minUpgrade = math.min(50, (DB.minUpgrade or 3) + 1); TB.Gear.Scan(true); Win.Rebuild() end },
        btn2 = { "-", function() DB.minUpgrade = math.max(0, (DB.minUpgrade or 3) - 1); TB.Gear.Scan(true); Win.Rebuild() end } })
  Add({ title = "Hidden items", desc = "Bring back items you hid with Never or Hide.",
        btn = { "Reset", function() DB.ignored = {}; TB.Gear.Scan(true); Win.Rebuild() end } })

  Header("Cooldown bar")
  Toggle("Show the bar", "Key cooldowns for your spec.", "cdBar", function() TB.Cooldowns.Refresh() end)
  Toggle("Lock position", "Turn off to drag the bar.", "cdLocked")
  Toggle("Next cast hint", "Shows the game's suggested next spell, if this version offers it.", "cdNext", function() TB.Cooldowns.Refresh() end)

  if TB.Macros then
    Header("Macros")
    local autoOn = TB.Macros.AutoOn()
    Add({ title = "Update macros when I learn skills", desc = "Rebuilds your Realm macros with your newest spells after you learn them or change talents or spec. Off leaves them alone until you run /realm macros.",
          btn = { autoOn and "ON" or "OFF", function() TB.Macros.SetAuto(not TB.Macros.AutoOn()); Win.Rebuild() end, autoOn and TONE_ON or TONE_OFF },
          bar = autoOn and { .3, 1, .6 } or { .3, .3, .35 } })
    Add({ title = "Build my macros now", desc = "Hotbars 1 to 4 and the main bar for your class and spec. Same as /realm macros.",
          btn = { "Build", function() TB.Macros.Install({}) end } })
  end

  Header("General")
  Add({ title = "Minimap button", btn = { ns.DB.mmHide and "OFF" or "ON", function() TB.Minimap.Toggle(); Win.Rebuild() end,
        ns.DB.mmHide and TONE_OFF or TONE_ON } })
  local class = TB.Class()
  if class then
    local spec, key, mode = TB.Spec()
    local level = (UnitLevel and UnitLevel("player")) or 1
    local note = (mode == "auto") and "auto from talents" or (mode == "remembered" and "remembered" or (mode == "forced" and "forced" or "default"))
    Add({ title = "Spec", desc = level < TB.SPEC_LEVEL
            and ("Pick the spec you are going for. It is remembered until level " .. TB.SPEC_LEVEL .. ", then it follows your talents.")
            or "Follows your talents. Change to force one, cycle past the last to go back to auto.",
          right = GOLD .. (spec and spec.name or "?") .. "|r\n" .. GRAY .. note .. "|r",
          btn = { "Change", function()
            local order = class.specList or class.specOrder
            local rec = TB.Char()
            local cur = (level < TB.SPEC_LEVEL) and (rec.pref or key) or (rec.force)
            local nextKey
            if not cur then nextKey = order[1]
            else for i, k in ipairs(order) do if k == cur then nextKey = order[i + 1] end end end
            if level < TB.SPEC_LEVEL and not nextKey then nextKey = order[1] end
            TB.SetSpecChoice(nextKey); Win.Rebuild()
          end } })
  end

  Header("Commands")
  Text("/boys   /boys gear   /boys rotation   /boys cd   /boys prof   /boys bar   /boys lock   /boys spec <name>   /boys min <pct>   /boys minimap")
  Text(GRAY .. "TheBoys " .. TB.version .. "|r")
end

-- ---------------------------------------------------------------- frame
local function Tint()
  local r, g, b = TB.Accent()
  if band then band:SetColorTexture(r * .22, g * .22, b * .22, 1) end
  if bandLine then bandLine:SetColorTexture(r, g, b, 1) end
  if f then TB.Skin(f, .045, .04, .07, .97, r * .6, g * .6, b * .6) end
end

function Win.Rebuild()
  if not f or not f:IsShown() then return end
  Reset()
  Tint()
  subtitle:SetText(SpecLine())
  local ok, err = pcall(build[current])
  if not ok then Text(RED .. "Error building this tab:|r " .. tostring(err)) end
  Done()
  local r, g, b = TB.Accent()
  for _, t in ipairs(TABS) do
    local tb = tabBtns[t[1]]
    if tb then
      local sel = (t[1] == current)
      tb.under:SetShown(sel)
      tb.under:SetColorTexture(r, g, b, 1)
      tb.label:SetTextColor(sel and 1 or .6, sel and 1 or .6, sel and 1 or .7)
      tb.sel:SetShown(sel)
    end
  end
end

local function Build()
  f = TB.NewFrame("Frame", "TheBoysWindow", UIParent)
  f:SetSize(W, H)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
  f:SetFrameStrata("HIGH")
  f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  TB.Skin(f, .045, .04, .07, .97)
  if UISpecialFrames then table.insert(UISpecialFrames, "TheBoysWindow") end

  -- header band
  band = f:CreateTexture(nil, "BACKGROUND")
  band:SetPoint("TOPLEFT", 1, -1); band:SetPoint("TOPRIGHT", -1, -1); band:SetHeight(58)
  band:SetColorTexture(.118, .165, .22, 1)
  bandLine = f:CreateTexture(nil, "ARTWORK")
  bandLine:SetPoint("TOPLEFT", band, "BOTTOMLEFT", 0, 0); bandLine:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT", 0, 0)
  bandLine:SetHeight(2)

  logo = f:CreateTexture(nil, "OVERLAY")
  logo:SetSize(44, 44); logo:SetPoint("TOPLEFT", 14, -7)
  logo:SetTexture("Interface\\AddOns\\Realm\\boys")

  local brand = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  brand:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -3)
  brand:SetText("|cff9482c9The|r|cff33ff99Boys|r")
  subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  subtitle:SetPoint("TOPLEFT", brand, "BOTTOMLEFT", 1, -2)

  local close = TB.FlatButton(f, "X", 24, 24, function() f:Hide() end)
  close:SetPoint("TOPRIGHT", -10, -10)
  close:SetTone(.3, .1, .12)

  -- tab strip
  tabBtns = {}
  local tw = (W - 28) / #TABS
  for i, t in ipairs(TABS) do
    local b = CreateFrame("Button", nil, f)
    b:SetSize(tw, 28); b:SetPoint("TOPLEFT", 14 + (i - 1) * tw, -66)
    b.sel = b:CreateTexture(nil, "BACKGROUND"); b.sel:SetAllPoints(); b.sel:SetColorTexture(1, 1, 1, .05)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, .08)
    b.under = b:CreateTexture(nil, "OVERLAY")
    b.under:SetPoint("BOTTOMLEFT"); b.under:SetPoint("BOTTOMRIGHT"); b.under:SetHeight(2)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.label:SetPoint("CENTER", 0, 0); b.label:SetText(t[2])
    b:SetScript("OnClick", function() current = t[1]; Win.Rebuild(); scroll:SetVerticalScroll(0) end)
    tabBtns[t[1]] = b
  end
  local sep = f:CreateTexture(nil, "ARTWORK")
  sep:SetPoint("TOPLEFT", 14, -94); sep:SetPoint("TOPRIGHT", -14, -94); sep:SetHeight(1); sep:SetColorTexture(1, 1, 1, .08)

  scroll = CreateFrame("ScrollFrame", "TheBoysScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -104)
  scroll:SetPoint("BOTTOMRIGHT", -30, 14)
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(CONTENT_W, 10)
  scroll:SetScrollChild(content)

  local acc = 0
  f:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 1 then return end
    acc = 0
    if current == "cooldowns" then Win.Rebuild() end
  end)
  f:Hide()
end

function Win.Show(tab)
  if not f then Build() end
  if tab then current = tab end
  f:Show()
  if current == "gear" then pcall(TB.Gear.Scan, true) end
  Win.Rebuild()
end

function Win.Toggle()
  if f and f:IsShown() then f:Hide() else Win.Show() end
end

TB.OnLogin(function()
  TB.Listen("GEAR_UPDATED", function() if f and f:IsShown() and current == "gear" then Win.Rebuild() end end)
  TB.Listen("SPEC_CHANGED", function() if f and f:IsShown() then Win.Rebuild() end end)
end)
