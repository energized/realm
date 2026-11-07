-- TheBoys: cooldown helper bar. Shows your spec's key cooldowns, only the ones you know.
local ADDON, ns = ...
local TB = ns.TB
local CD = {}
TB.Cooldowns = CD

local SIZE, GAP, MAXN = 36, 5, 9
local bar, buttons, nextBtn = nil, {}, nil

local function Entries()
  local class, list = TB.Class(), {}
  local spec = TB.Spec()
  if not class or not spec then return list end
  local seen = {}
  for _, e in ipairs(spec.cooldowns or {}) do
    local n = TB.Pick(e)
    if not seen[n] and TB.Known(n) then list[#list + 1] = { n, e[2], e[3] }; seen[n] = true end
  end
  for _, e in ipairs(class.utility or {}) do
    local n = TB.Pick(e)
    if e[2] == "defensive" and not seen[n] and TB.Known(n) then list[#list + 1] = { n, e[2], e[3] }; seen[n] = true end
  end
  return list
end
CD.Entries = Entries

local function MakeButton(i)
  local b = CreateFrame("Button", nil, bar)
  b:SetSize(SIZE, SIZE)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints(); b.icon:SetTexCoord(.07, .93, .07, .93)
  b.border = b:CreateTexture(nil, "OVERLAY")
  b.border:SetPoint("TOPLEFT", -2, 2); b.border:SetPoint("BOTTOMRIGHT", 2, -2)
  b.border:SetColorTexture(.09, .125, .169, 1)
  b.border:SetDrawLayer("BACKGROUND")
  b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cd:SetAllPoints()
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function() if not TB.DB.cdLocked then bar:StartMoving() end end)
  b:SetScript("OnDragStop", function()
    bar:StopMovingOrSizing()
    local p, _, rp, x, y = bar:GetPoint()
    TB.DB.cdPos = { p, rp, x, y }
  end)
  b:SetScript("OnEnter", function(self)
    if not GameTooltip or not self.entry then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(self.entry[1], 1, 1, 1)
    GameTooltip:AddLine(self.entry[3] or "", .8, .8, .8, true)
    GameTooltip:AddLine("Drag to move (unlock with /boys lock)", .5, .5, .5)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return b
end

local function Layout()
  local list = Entries()
  CD.list = list
  local n = math.min(#list, MAXN)
  for i = 1, math.max(n, #buttons) do
    local b = buttons[i]
    if i <= n then
      if not b then b = MakeButton(i); buttons[i] = b end
      b.entry = list[i]
      b.icon:SetTexture(TB.Icon(list[i][1]))
      b:ClearAllPoints()
      b:SetPoint("LEFT", bar, "LEFT", (i - 1) * (SIZE + GAP) + (nextBtn and (SIZE + GAP + 6) or 0), 0)
      b:Show()
    elseif b then
      b:Hide()
    end
  end
  local width = math.max(n, 1) * (SIZE + GAP) + (nextBtn and (SIZE + GAP + 6) or 0)
  bar:SetSize(width, SIZE)
end

local function Update()
  for i, b in ipairs(buttons) do
    if b:IsShown() and b.entry then
      local start, dur = TB.Cooldown(b.entry[1])
      -- in combat the game hides cooldown numbers from addons ("secret" values): hand them straight to the
      -- cooldown spinner without comparing them
      local secret = issecretvalue and (issecretvalue(start) or issecretvalue(dur))
      if secret then
        pcall(b.cd.SetCooldown, b.cd, start, dur)
        b.icon:SetDesaturated(false)
      elseif type(start) == "number" and type(dur) == "number" and start > 0 and dur > 1.6 then
        pcall(b.cd.SetCooldown, b.cd, start, dur)
        b.icon:SetDesaturated(true)
      else
        pcall(b.cd.Clear or b.cd.Hide, b.cd)
        b.icon:SetDesaturated(false)
      end
    end
  end
  -- "what should I press" icon, only if the client has the assisted-combat helper
  if nextBtn and C_AssistedCombat and C_AssistedCombat.GetNextCastSpell and TB.DB.cdNext then
    local ok, id = pcall(C_AssistedCombat.GetNextCastSpell)
    if ok and type(id) == "number" and id > 0 then
      local tex
      if C_Spell and C_Spell.GetSpellTexture then
        local ok2, t = pcall(C_Spell.GetSpellTexture, id)
        if ok2 then tex = t end
      end
      if tex then nextBtn.icon:SetTexture(tex); nextBtn:Show() return end
    end
    nextBtn:Hide()
  end
end

local function Build()
  bar = TB.NewFrame("Frame", "TheBoysCooldownBar", UIParent)
  bar:SetSize(100, SIZE)
  bar:SetMovable(true); bar:SetClampedToScreen(true)
  local pos = TB.DB.cdPos
  if pos then bar:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else bar:SetPoint("CENTER", UIParent, "CENTER", 0, -180) end
  bar:SetScale(TB.DB.cdScale or 1)

  if C_AssistedCombat and C_AssistedCombat.GetNextCastSpell then
    nextBtn = CreateFrame("Frame", nil, bar)
    nextBtn:SetSize(SIZE, SIZE); nextBtn:SetPoint("LEFT", bar, "LEFT", 0, 0)
    nextBtn.icon = nextBtn:CreateTexture(nil, "ARTWORK")
    nextBtn.icon:SetAllPoints(); nextBtn.icon:SetTexCoord(.07, .93, .07, .93)
    nextBtn.glow = nextBtn:CreateTexture(nil, "OVERLAY")
    nextBtn.glow:SetPoint("TOPLEFT", -2, 2); nextBtn.glow:SetPoint("BOTTOMRIGHT", 2, -2)
    nextBtn.glow:SetColorTexture(.2, 1, .6, .35)
    nextBtn:Hide()
  end

  local acc = 0
  bar:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.25 then return end
    acc = 0
    Update()
  end)
  return bar
end

function CD.Refresh()
  if not bar then return end
  if not TB.DB.cdBar then bar:Hide() return end
  Layout()
  bar:SetScale(TB.DB.cdScale or 1)
  if #(CD.list or {}) == 0 then bar:Hide() else bar:Show() end
  Update()
end

TB.OnLogin(function()
  Build()
  CD.Refresh()
  local f = CreateFrame("Frame")
  f:RegisterEvent("SPELLS_CHANGED")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:SetScript("OnEvent", function() CD.Refresh() end)
  TB.Listen("SPEC_CHANGED", CD.Refresh)
end)
