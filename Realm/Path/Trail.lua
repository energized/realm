-- Minimap breadcrumb trail: marching footprints from you toward the current target.
local ADDON, ns = ...
local Path = ns.Path

local DOTS = 24
local dots, tip
local phase = 0
local cycle = 0                -- counts each time the footprints advance one step, so left/right stays steady as they march
local STEP = 14                -- pixels between footprints
local FOOT_R = "Interface\\AddOns\\Realm\\Path\\icons\\step.tga"      -- right foot
local FOOT_L = "Interface\\AddOns\\Realm\\Path\\icons\\stepL.tga"     -- left foot (a separate picture: flipping would cancel the rotation)
local RADIUS = { [0] = 233.33, 200, 166.67, 133.33, 100, 66.67 }    -- yards from centre to edge, outdoors, by zoom

local function Radius()
  local z = Minimap.GetZoom and Minimap:GetZoom() or 0
  return RADIUS[z] or 166.67
end

local function Build()
  if dots or not Minimap then return end
  dots = {}
  for i = 1, DOTS do
    local t = Minimap:CreateTexture(nil, "OVERLAY", nil, 7)
    t:SetTexture(FOOT_R); t.tex = FOOT_R
    t:SetSize(16, 16); t:Hide(); dots[i] = t
  end
  tip = Minimap:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  if tip.SetFont then tip:SetFont(ns.UI.FONT, 15, "OUTLINE") end
  tip:Hide()
end

local function HideAll()
  if not dots then return end
  for _, t in ipairs(dots) do t:Hide() end
  tip:Hide()
end

function Path.DrawTrail(target, heading, c, icon, dt)
  local O = Path.Opts()
  if not O or O.trail == false or not Minimap or not target or not target.bearing or not target.dist then HideAll() return end
  Build()
  if not Minimap:IsVisible() then HideAll() return end
  local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
  local ang = target.bearing
  if rotate then ang = ang - heading end
  local sx, sy = math.sin(ang), math.cos(ang)
  local half = (Minimap:GetWidth() or 140) / 2
  local pxPerYd = half / Radius()
  local endPx = math.min(target.dist * pxPerYd, half - 8)
  phase = phase + (dt or 0) * 9
  while phase >= STEP do phase = phase - STEP; cycle = cycle + 1 end
  c = c or { 1, 1, 1 }
  local n = 0
  if endPx > 18 then
    local d, k = 14 + phase, 0
    local px, py = sy, -sx                       -- sideways, to the walker's right
    while d <= endPx - 6 and n < DOTS do
      k = k + 1
      local t = dots[n + 1]
      local right = (k + cycle) % 2 == 0
      local side = right and 3 or -3
      t:ClearAllPoints(); t:SetPoint("CENTER", Minimap, "CENTER", sx * d + px * side, sy * d + py * side)
      if t.SetRotation then t:SetRotation(-ang) end          -- toes point toward the target
      local want = right and FOOT_R or FOOT_L
      if t.tex ~= want then t:SetTexture(want); t.tex = want end
      t:SetVertexColor(c[1], c[2], c[3], .95); t:Show()
      n = n + 1
      d = d + STEP
    end
  end
  for i = n + 1, DOTS do dots[i]:Hide() end
  tip:ClearAllPoints(); tip:SetPoint("CENTER", Minimap, "CENTER", sx * endPx, sy * endPx)
  tip:SetText(icon or "!"); tip:SetTextColor(c[1], c[2], c[3]); tip:Show()
end
