-- Replay window: watch a saved PvP fight, or the scripted practice match ("What this is").
-- Controls: Play/Pause, Next step, Back step, jump to the previous/next kill or interrupt, restart, end, speed, and a
-- clickable time bar. The engine is in ReplayPlayer.lua. The log has no health numbers, so the panel shows what each
-- player dealt and took, and who has died, instead of health bars.
local ADDON, ns = ...
local V = {}
ns.ReplayView = V

local WHAT = "What this is: a scripted practice match with bots, not real players, so you can try the controls. "
  .. "Your own PvP fights are recorded for you and show up here. Step through every event, jump between kills and "
  .. "interrupts, change the speed, and see where everyone stood."
local PW, PH, BARW = 250, 250, 530
local LABEL = { bg = "battleground", arena = "arena", world = "open world", manual = "manual" }

local win, player, viewPos, note
local buttons, dots, tags = {}, {}, {}
V.buttons, V.dots = buttons, dots

local function Has(f, bit) return type(f) == "number" and math.floor(f / bit) % 2 == 1 end

local function Short(n)
  if n >= 1000000 then return string.format("%.1fm", n / 1000000) end
  if n >= 1000 then return string.format("%.1fk", n / 1000) end
  return tostring(math.floor(n))
end

-- red = enemy, gold = you, blue = your side
local function Side(rec, i)
  local f = rec.units[i] and rec.units[i][3] or 0
  if Has(f, 0x40) then return 1, .3, .3 end
  if i == rec.me then return .95, .8, .2 end
  return .3, .6, 1
end
local function Hex(r, g, b)
  return string.format("%02x%02x%02x", math.floor(r * 255 + .5), math.floor(g * 255 + .5), math.floor(b * 255 + .5))
end

local function Refresh()
  if not (win and player) then return end
  local P = ns.ReplayPlayer
  local rec, st = player.rec, player:State()

  local frac = player.tEnd > 0 and math.min(1, player.t / player.tEnd) or 0
  win.fill:SetWidth(math.max(1, math.floor(BARW * frac)))
  win.time:SetText(P.Clock(player.t) .. " / " .. P.Clock(player.tEnd) .. "     step " .. player.idx .. " of " .. player.n
    .. "     speed " .. player.speed .. "x")
  buttons.play.l:SetText(player.playing and "Pause" or "Play")
  buttons.speed.l:SetText(player.speed .. "x")

  -- who is who: dealt, took, dead, and the effects on them right now
  local lines = {}
  for i = 1, math.min(#rec.units, 10) do
    local u, s = rec.units[i], st.u[i] or {}
    local aur = {}
    for id in pairs(s.auras or {}) do aur[#aur + 1] = P.SpellName(rec, id) end
    table.sort(aur)
    lines[#lines + 1] = string.format("|cff%s%s|r  dealt %s  took %s%s%s", Hex(Side(rec, i)), u[2],
      Short(s.dealt or 0), Short(s.taken or 0), s.dead and "  |cffff4444DEAD|r" or "",
      #aur > 0 and ("  |cff9aa5b1" .. table.concat(aur, ", ") .. "|r") or "")
  end
  if #rec.units > 10 then lines[#lines + 1] = "|cff9aa5b1+ " .. (#rec.units - 10) .. " more (pets or players)|r" end
  win.units:SetText(table.concat(lines, "\n"))

  -- the last few events, the newest bright
  local recent, out = player:Recent(9), {}
  for k, e in ipairs(recent) do
    local line = P.Describe(rec, e)
    out[#out + 1] = (k == #recent) and ("|cffffffff" .. line .. "|r") or ("|cff9aa5b1" .. line .. "|r")
  end
  if #out == 0 then out[1] = "|cff9aa5b1Press Play or Next step to begin.|r" end
  win.log:SetText(table.concat(out, "\n"))

  -- top-down view of where everyone stood
  local pos, b = player:Positions(), player.bounds
  for i = 1, #rec.units do
    local d, tg = dots[i], tags[i]
    if not d then
      d = win.plot:CreateTexture(nil, "OVERLAY"); d:SetSize(9, 9); dots[i] = d
      tg = win.plot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); tags[i] = tg
    end
    local p = pos[i]
    if p and b then
      local sc = math.min((PW - 24) / math.max(1, b[2] - b[1]), (PH - 24) / math.max(1, b[4] - b[3]))
      local px, py = 12 + (p[1] - b[1]) * sc, 12 + (p[2] - b[3]) * sc
      d:ClearAllPoints(); d:SetPoint("CENTER", win.plot, "BOTTOMLEFT", px, py)
      tg:ClearAllPoints(); tg:SetPoint("BOTTOM", d, "TOP", 0, 1)
      tg:SetText((rec.units[i][2] or "?"):sub(1, 1))
      if st.u[i] and st.u[i].dead then d:SetColorTexture(.4, .4, .4, 1)
      else local r, g, bl = Side(rec, i); d:SetColorTexture(r, g, bl, 1) end
      d:Show(); tg:Show()
    else
      d:Hide(); tg:Hide()
    end
  end
  for i = #rec.units + 1, #dots do dots[i]:Hide(); tags[i]:Hide() end
end
V.Refresh = Refresh

local function Btn(name, label, w, x, y, fn)
  local b = CreateFrame("Button", nil, win)
  b:SetSize(w, 22); b:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", x, y)
  b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetColorTexture(.133, .196, .29, 1)
  b.l = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.l:SetPoint("CENTER"); b.l:SetText(label)
  b:SetScript("OnClick", fn)
  buttons[name] = b
  return b
end

local function Act(fn) return function() if player then fn(player); Refresh() end end end

local function Build()
  local f = CreateFrame("Frame", "RealmReplayWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(560, 450)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
  f:SetFrameStrata("HIGH"); f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(s) s:StartMoving() end)
  f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
  if ns.UI and ns.UI.Skin then ns.UI.Skin(f) end
  if UISpecialFrames then table.insert(UISpecialFrames, "RealmReplayWindow") end
  win = f

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetPoint("TOPLEFT", 14, -10)
  local x = CreateFrame("Button", nil, f)
  x:SetSize(22, 22); x:SetPoint("TOPRIGHT", -8, -8)
  x.bg = x:CreateTexture(nil, "BACKGROUND"); x.bg:SetAllPoints(); x.bg:SetColorTexture(.133, .196, .29, 1)
  x.l = x:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); x.l:SetPoint("CENTER"); x.l:SetText("X")
  x:SetScript("OnClick", function() f:Hide() end)

  f.what = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.what:SetPoint("TOPLEFT", 14, -34); f.what:SetWidth(530); f.what:SetJustifyH("LEFT"); f.what:SetJustifyV("TOP")

  f.plot = CreateFrame("Frame", nil, f)
  f.plot:SetSize(PW, PH); f.plot:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -92)
  f.plot.bg = f.plot:CreateTexture(nil, "BACKGROUND"); f.plot.bg:SetAllPoints(); f.plot.bg:SetColorTexture(.05, .08, .12, 1)

  f.units = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.units:SetPoint("TOPLEFT", f, "TOPLEFT", 278, -92); f.units:SetWidth(268); f.units:SetJustifyH("LEFT"); f.units:SetJustifyV("TOP")
  f.log = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.log:SetPoint("TOPLEFT", f, "TOPLEFT", 278, -226); f.log:SetWidth(268); f.log:SetJustifyH("LEFT"); f.log:SetJustifyV("TOP")

  -- time bar: click to jump
  f.bar = CreateFrame("Button", nil, f)
  f.bar:SetSize(BARW, 12); f.bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 84)
  f.bar.bg = f.bar:CreateTexture(nil, "BACKGROUND"); f.bar.bg:SetAllPoints(); f.bar.bg:SetColorTexture(.118, .165, .22, 1)
  f.fill = f.bar:CreateTexture(nil, "ARTWORK")
  f.fill:SetPoint("TOPLEFT", f.bar, "TOPLEFT", 0, 0); f.fill:SetPoint("BOTTOMLEFT", f.bar, "BOTTOMLEFT", 0, 0)
  f.fill:SetColorTexture(.77, .13, .106, 1); f.fill:SetWidth(1)
  f.bar:SetScript("OnMouseUp", function(self)
    if not player then return end
    local cx = GetCursorPosition and GetCursorPosition()
    local left, sc = self.GetLeft and self:GetLeft(), self.GetEffectiveScale and self:GetEffectiveScale()
    if type(cx) == "number" and type(left) == "number" and type(sc) == "number" and sc > 0 then
      player:Seek(math.max(0, math.min(1, (cx / sc - left) / BARW)) * player.tEnd)
      player.playing = false
      Refresh()
    end
  end)
  f.time = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.time:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 68)

  Btn("restart", "|<",        40, 14,  40, Act(function(p) p:Restart() end))
  Btn("keyback", "<<",        40, 60,  40, Act(function(p) p:Key(-1) end))
  Btn("back",    "Back step", 76, 106, 40, Act(function(p) p:Step(-1) end))
  Btn("play",    "Play",      62, 188, 40, Act(function(p) p:Toggle() end))
  Btn("fwd",     "Next step", 76, 256, 40, Act(function(p) p:Step(1) end))
  Btn("keynext", ">>",        40, 338, 40, Act(function(p) p:Key(1) end))
  Btn("toend",   ">|",        40, 384, 40, Act(function(p) p:ToEnd() end))
  Btn("speed",   "1x",        56, 430, 40, Act(function(p) p:CycleSpeed() end))
  Btn("newer",   "Newer",     60, 14,  12, function() V.Open(false, (viewPos or 1) - 1) end)
  Btn("older",   "Older",     60, 80,  12, function() V.Open(false, (viewPos or 0) + 1) end)
  Btn("what",    "What this is", 100, 146, 12, function() V.Open(true) end)
  f.keys = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.keys:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 256, 16)
  f.keys:SetText("<< and >> jump to the previous or next kill, interrupt or dispel")

  f:SetScript("OnUpdate", function(_, el)
    if player and player.playing then player:Tick(el); Refresh() end
  end)
  f:Hide()
end

function V.Load(rec, pos, why)
  if not win then Build() end
  player, viewPos = ns.ReplayPlayer.New(rec), pos
  if rec.demo then
    win.title:SetText("Replay  |cff9aa5b1practice match|r")
    win.what:SetText((why and (why .. "  ") or "") .. WHAT)
  else
    win.title:SetText("Replay  |cff9aa5b1#" .. tostring(rec.id) .. "|r")
    win.what:SetText(string.format("%s in %s, %s, %d events%s. Use Newer and Older for your other fights.",
      LABEL[rec.kind] or tostring(rec.kind), tostring(rec.zone), ns.ReplayPlayer.Clock((rec.dur or 0) * 1000), rec.nEv or #rec.ev,
      rec.trunc and " (the earliest part was dropped to fit)" or ""))
  end
  win:Show()
  Refresh()
end

-- demo = true: the scripted practice match. Otherwise saved fight number n (newest is 1); with none saved, the practice match.
function V.Open(demo, n)
  if not win then Build() end
  local saved = (ns.Replay and ns.Replay.Saved and ns.Replay.Saved()) or {}
  if demo then return V.Load(ns.ReplayPlayer.Demo(), nil) end
  if #saved == 0 then
    return V.Load(ns.ReplayPlayer.Demo(), nil, "You have no saved fights yet, so this is the practice match.")
  end
  local pos = math.max(1, math.min(#saved, math.floor(n or 1)))
  V.Load(saved[pos], pos)
end

function V.Window() return win end
function V.Player() return player end
