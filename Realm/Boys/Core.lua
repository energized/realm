-- TheBoys (part of Realm): core. Class registry, spec detection, spell helpers, settings, slash commands.
local ADDON, ns = ...
local TB = {}
ns.TB = TB
_G.TheBoys = TB
TB.Minimap = { Toggle = function() if ns.Minimap and ns.Minimap.Toggle then ns.Minimap.Toggle() end end }

TB.version = "2.1.0"
TB.classes = {}      -- token -> class definition
TB.order = {}        -- registration order (for the settings list)
TB.modules = {}      -- ordered list of modules that want PLAYER_LOGIN init

local DEFAULTS = {
  suggest = true,        -- popup when a better item shows up
  minUpgrade = 3,        -- percent improvement needed to suggest
  cdBar = true,          -- show the cooldown helper bar
  cdLocked = false,
  cdScale = 1,
  cdNext = true,         -- show "next cast" icon if the client offers it
  mmHide = false,
  mmAngle = 250,
  chars = {},            -- per character: remembered spec (before level 10) or forced spec
  ignored = {},          -- item links the player dismissed
}

local function Print(msg)
  print("|cff9482c9The|r|cff33ff99Boys|r: " .. tostring(msg))
end
TB.Print = Print

-- ---------------------------------------------------------------- registry
function TB.RegisterClass(token, def)
  def.token = token
  if not TB.classes[token] then table.insert(TB.order, token) end
  TB.classes[token] = def
end

function TB.OnLogin(fn) table.insert(TB.modules, fn) end

function TB.ClassToken()
  local _, token = UnitClass("player")
  return token
end

function TB.Class()
  return TB.classes[TB.ClassToken() or ""]
end

-- ---------------------------------------------------------------- spells
-- Everything is looked up by NAME so it works whatever the client version
-- calls the spell id. Spell lists in the class files are plain names.
local function SpellInfoByName(name)
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, name)
    if ok and type(info) == "table" then return info.name, info.iconID, info.spellID end
  end
  if GetSpellInfo then
    local ok, n, _, icon, _, _, _, id = pcall(GetSpellInfo, name)
    if ok and n then return n, icon, id end
  end
end

function TB.Spell(name)
  local n, icon, id = SpellInfoByName(name)
  return n, icon, id
end

-- an entry is { name, note, alt = "other name" }; pick whichever name this client knows
function TB.Pick(e)
  local n = e[1]
  if TB.Known(n) then return n end
  if e.alt then
    if TB.Known(e.alt) then return e.alt end
    if not SpellInfoByName(n) and SpellInfoByName(e.alt) then return e.alt end
  end
  return n
end

function TB.Icon(name)
  local _, icon = SpellInfoByName(name)
  return icon or 134400 -- question mark
end

function TB.Known(name)
  local n, _, id = SpellInfoByName(name)
  if not n then return false end
  if id then
    if IsPlayerSpell then
      local ok, r = pcall(IsPlayerSpell, id)
      if ok and r then return true end
    end
    if IsSpellKnown then
      local ok, r = pcall(IsSpellKnown, id)
      if ok and r then return true end
    end
    if IsSpellKnownOrOverridesKnown then
      local ok, r = pcall(IsSpellKnownOrOverridesKnown, id)
      if ok and r then return true end
    end
  end
  return false
end

-- returns start, duration (0,0 when ready or unreadable)
function TB.Cooldown(name)
  local n, _, id = SpellInfoByName(name)
  if not n then return 0, 0 end
  if C_Spell and C_Spell.GetSpellCooldown then
    local ok, cd = pcall(C_Spell.GetSpellCooldown, id or name)
    if ok and type(cd) == "table" then return cd.startTime or 0, cd.duration or 0 end
  end
  if GetSpellCooldown then
    local ok, s, d = pcall(GetSpellCooldown, id or name)
    if ok then return s or 0, d or 0 end
  end
  return 0, 0
end

-- ---------------------------------------------------------------- spec detect
local function NumberOrNil(v) return type(v) == "number" and v or nil end

local SPEC_LEVEL = 10   -- talents open at 10; before that we use the remembered choice
TB.SPEC_LEVEL = SPEC_LEVEL

function TB.Char()
  local name = (UnitName and UnitName("player")) or "?"
  local realm = (GetRealmName and GetRealmName()) or ""
  local key = name .. "-" .. realm
  local chars = TB.DB.chars
  if not chars then chars = {}; TB.DB.chars = chars end
  local rec = chars[key]
  if not rec then rec = {}; chars[key] = rec end
  return rec
end

local function TalentSpec(class)
  -- talent trees: whichever tree has the most points wins (this is how Classic-style clients work)
  if GetNumTalentTabs and GetTalentTabInfo then
    local best, bestPts = nil, 0
    local okn, n = pcall(GetNumTalentTabs)
    n = (okn and n and n > 0) and n or 3
    for i = 1, n do
      local ok, a, b, c, d, e = pcall(GetTalentTabInfo, i)
      if ok then
        -- newer builds: id, name, description, icon, pointsSpent ; older: name, icon, pointsSpent
        local pts
        if type(a) == "number" and type(b) == "string" then pts = NumberOrNil(e) else pts = NumberOrNil(c) end
        if pts and pts > bestPts then best, bestPts = i, pts end
      end
    end
    if best then
      local key = class.specOrder and class.specOrder[best]
      if key then return key end
    end
  end

  -- Retail-style specialization, matched by id first and then by position
  if GetSpecialization and GetSpecializationInfo then
    local ok, idx = pcall(GetSpecialization)
    if ok and idx and idx > 0 then
      local ok2, id = pcall(GetSpecializationInfo, idx)
      if ok2 and id then
        for key, spec in pairs(class.specs) do
          if spec.id == id then return key end
        end
      end
      local key = class.specOrder and class.specOrder[idx]
      if key then return key end
    end
  end
end

-- returns key, mode   mode: "forced" | "auto" | "remembered"
function TB.DetectSpec()
  local class = TB.Class()
  if not class then return nil end
  local rec = TB.Char()
  if rec.force and class.specs[rec.force] then return rec.force, "forced" end
  local level = (UnitLevel and UnitLevel("player")) or 1
  if level >= SPEC_LEVEL then
    local key = TalentSpec(class)
    if key then return key, "auto" end
  end
  -- under level 10, or no talent points spent yet: use what the player chose
  if rec.pref and class.specs[rec.pref] then return rec.pref, "remembered" end
  return nil
end

function TB.Spec()
  local class = TB.Class()
  if not class then return nil end
  local key, mode = TB.DetectSpec()
  if not key then key = class.defaultSpec or (class.specOrder and class.specOrder[1]); mode = "default" end
  return class.specs[key], key, mode
end

-- set the player's choice. Under level 10 it is remembered; at 10+ it forces over auto detect.
function TB.SetSpecChoice(key)
  local rec = TB.Char()
  local level = (UnitLevel and UnitLevel("player")) or 1
  if key == nil then rec.force = nil; rec.pref = nil
  elseif level >= SPEC_LEVEL then rec.force = key; rec.pref = key
  else rec.pref = key; rec.force = nil end
  TB.Fire("SPEC_CHANGED")
end

-- ---------------------------------------------------------------- ui helpers
local BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }
function TB.NewFrame(kind, name, parent)
  return CreateFrame(kind or "Frame", name, parent or UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
end
function TB.Skin(f, r, g, b, a, er, eg, eb)
  if f.SetBackdrop then
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(r or .09, g or .125, b or .169, a or .97)
    f:SetBackdropBorderColor(er or .173, eg or .231, eb or .302, 1)
  end
end

function TB.Accent()
  local c = TB.Class()
  local a = c and c.accent
  if a then return a[1], a[2], a[3] end
  return .53, .53, .93
end

-- flat button used everywhere instead of the stock red-and-gold one
function TB.FlatButton(parent, text, w, h, onclick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w or 64, h or 22)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints(); b.bg:SetColorTexture(.133, .196, .29, 1)
  b.edge = b:CreateTexture(nil, "BORDER")
  b.edge:SetPoint("BOTTOMLEFT"); b.edge:SetPoint("BOTTOMRIGHT"); b.edge:SetHeight(1)
  b.edge:SetColorTexture(0, 0, 0, .6)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints(); b.hl:SetColorTexture(.77, .13, .106, .35)
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.label:SetPoint("CENTER", 0, 0)
  function b:SetLabel(t) self.label:SetText(t or "") end
  function b:SetTone(r, g, bl) self.bg:SetColorTexture(r, g, bl, 1) end
  b:SetLabel(text)
  if onclick then b:SetScript("OnClick", onclick) end
  return b
end

-- ---------------------------------------------------------------- misc
function TB.Say(...) if not TB.DB.quiet then Print(...) end end

function TB.Fire(event, ...)
  for _, fn in ipairs(TB.listeners or {}) do
    if fn.event == event then pcall(fn.fn, ...) end
  end
end
function TB.Listen(event, fn)
  TB.listeners = TB.listeners or {}
  table.insert(TB.listeners, { event = event, fn = fn })
end

-- ---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
ev:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
ev:RegisterEvent("CHARACTER_POINTS_CHANGED")
ev:RegisterEvent("SPELLS_CHANGED")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    TheBoysDB = TheBoysDB or {}
    for k, v in pairs(DEFAULTS) do
      if TheBoysDB[k] == nil then
        if type(v) == "table" then TheBoysDB[k] = {} else TheBoysDB[k] = v end
      end
    end
    TB.DB = TheBoysDB
  elseif event == "PLAYER_LOGIN" then
    if not TB.DB then TheBoysDB = TheBoysDB or {}; TB.DB = TheBoysDB end
    -- older versions kept one global override; make it this character's remembered choice
    if TB.DB.specOverride then
      local rec = TB.Char()
      if not rec.pref then rec.pref = TB.DB.specOverride end
      TB.DB.specOverride = nil
    end
    TB.lastSpecKey = TB.DetectSpec()
    for _, fn in ipairs(TB.modules) do
      local ok, err = pcall(fn)
      if not ok then Print("module error: " .. tostring(err)) end
    end
    local class = TB.Class()
    if class then
      TB.Say("loaded for " .. (class.name or TB.ClassToken()) .. ". Type /boys to open.")
    else
      TB.Say("loaded, but there is no guide for your class yet. All nine classes are in.")
    end
  else
    -- talents or level changed: only react if the detected spec actually moved
    local key = TB.DetectSpec()
    if key ~= TB.lastSpecKey then TB.lastSpecKey = key; TB.Fire("SPEC_CHANGED") end
  end
end)

-- ---------------------------------------------------------------- slash
local function Help()
  Print("commands:")
  print("  /boys              open the window")
  print("  /boys gear         gear upgrades tab (rescans bags)")
  print("  /boys rotation     rotation guide")
  print("  /boys cd           cooldowns tab; /boys bar toggles the bar")
  print("  /boys prof         profession advice")
  print("  /boys spec <name>  set your spec (remembered under level 10), or 'auto'")
  print("  /boys suggest      toggle upgrade popups")
  print("  /boys min <pct>    minimum upgrade percent to suggest")
  print("  /boys minimap      show/hide the minimap button")
  print("  /boys reset        forget dismissed items")
end

SLASH_THEBOYS1 = "/boys"
SLASH_THEBOYS2 = "/theboys"
SlashCmdList["THEBOYS"] = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  cmd = cmd or ""
  local DB = TB.DB
  if cmd == "" then
    if TB.Window then TB.Window.Toggle() end
  elseif cmd == "gear" or cmd == "rotation" or cmd == "rot" or cmd == "cd" or cmd == "cooldowns"
      or cmd == "prof" or cmd == "professions" or cmd == "settings" then
    local map = { rot = "rotation", cd = "cooldowns", prof = "professions" }
    if TB.Window then TB.Window.Show(map[cmd] or cmd) end
  elseif cmd == "bar" then
    DB.cdBar = not DB.cdBar
    if TB.Cooldowns then TB.Cooldowns.Refresh() end
    Print("cooldown bar " .. (DB.cdBar and "on" or "off"))
  elseif cmd == "lock" then
    DB.cdLocked = not DB.cdLocked
    Print("cooldown bar " .. (DB.cdLocked and "locked" or "unlocked: drag it where you want"))
  elseif cmd == "spec" then
    local class = TB.Class()
    if not class then Print("no class guide loaded") return end
    local level = (UnitLevel and UnitLevel("player")) or 1
    if rest == "" then
      local spec, key, mode = TB.Spec()
      Print("spec: " .. (spec and spec.name or "?") .. " (" .. mode .. ")")
      return
    elseif rest == "auto" then
      local rec = TB.Char(); rec.force = nil; rec.pref = nil
      TB.Fire("SPEC_CHANGED")
      Print("spec: auto detect from your talents (level " .. TB.SPEC_LEVEL .. "+)")
    else
      local found
      for key, spec in pairs(class.specs) do
        if key:lower():find(rest, 1, true) or spec.name:lower():find(rest, 1, true) then found = key end
      end
      if not found then Print("unknown spec '" .. rest .. "'") return end
      TB.SetSpecChoice(found)
      if level >= TB.SPEC_LEVEL then
        Print("spec forced to " .. class.specs[found].name .. ". /boys spec auto goes back to talent detection.")
      else
        Print("spec remembered as " .. class.specs[found].name .. ". Once you reach level " .. TB.SPEC_LEVEL .. " it follows your talents.")
      end
    end
  elseif cmd == "macros" or cmd == "macro" then
    if TB.Macros then TB.Macros.Command(rest) end
  elseif cmd == "suggest" then
    DB.suggest = not DB.suggest
    Print("upgrade popups " .. (DB.suggest and "on" or "off"))
  elseif cmd == "min" then
    local n = tonumber(rest)
    if n and n >= 0 and n <= 100 then DB.minUpgrade = n; Print("minimum upgrade: " .. n .. "%")
    else Print("usage: /boys min <0-100>") end
  elseif cmd == "minimap" then
    if TB.Minimap then TB.Minimap.Toggle() end
  elseif cmd == "reset" then
    DB.ignored = {}
    if TB.Gear then TB.Gear.Scan(true) end
    Print("dismissed items cleared")
  else
    Help()
  end
end
