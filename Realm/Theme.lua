-- Realm look: the Red Ass palette (table blue, cream, burn red, gold) in one place.
local ADDON, ns = ...
local function rgb(h) return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 } end

local UI = {}
ns.UI = UI
UI.C = {
  bg = rgb("17202B"),        -- table blue
  panel = rgb("1E2A38"),
  raised = rgb("22324A"),
  line = rgb("2C3B4D"),
  cream = rgb("FBF8F3"),
  text = rgb("E9EDF3"),
  muted = rgb("A3AFC0"),
  red = rgb("C4211B"),
  ember = rgb("FF5A4F"),
  gold = rgb("E8AB35"),
  good = rgb("4CC790"),
  blue = rgb("5B9BFF"),
  purple = rgb("A57BFF"),
  edge = rgb("3A4F6A"),      -- 1px button border
}
UI.FONT = "Fonts\\ARIALN.TTF"
function UI.Hex(c) return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + .5), math.floor(c[2] * 255 + .5), math.floor(c[3] * 255 + .5)) end
UI.H = {}
for k, v in pairs(UI.C) do UI.H[k] = UI.Hex(v) end

local tops = setmetatable({}, { __mode = "k" })
local EDGE = "Interface\\Buttons\\WHITE8X8"
-- flat window: table-blue fill, thin slate border, 2px burn-red top edge
function UI.Skin(f, alpha, accent)
  local c = UI.C
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = EDGE, edgeFile = EDGE, edgeSize = 1 })
    f:SetBackdropColor(c.bg[1], c.bg[2], c.bg[3], alpha or .97)
    f:SetBackdropBorderColor(c.line[1], c.line[2], c.line[3], 1)
  end
  local top = tops[f]
  if not top then
    top = f:CreateTexture(nil, "OVERLAY")
    top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1); top:SetHeight(2)
    tops[f] = top
  end
  local a = accent or c.red
  top:SetColorTexture(a[1], a[2], a[3], 1)
end

-- flat button fill + hover
local fills = setmetatable({}, { __mode = "k" })
function UI.Button(b, tone, hover, hoverAlpha)
  local c = UI.C
  tone = tone or c.raised
  hover = hover or c.red
  local r = fills[b]
  if not r then
    r = {}
    r.bg = b:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    r.hl = b:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints()
    fills[b] = r
  end
  r.bg:SetColorTexture(tone[1], tone[2], tone[3], 1)
  r.hl:SetColorTexture(hover[1], hover[2], hover[3], hoverAlpha or .35)
end

-- modern flat button for a template button (UIPanelButtonTemplate draws the red 2004 art).
-- Hides that art, then slate fill, 1px border, neutral blue hover, clean font. Safe to call twice.
local modern = setmetatable({}, { __mode = "k" })
local function Hide(t) if type(t) == "table" and t.SetAlpha then pcall(t.SetAlpha, t, 0) end end
function UI.Modern(b, tone)
  if not b then return b end
  local c = UI.C
  if not modern[b] then
    modern[b] = true
    for _, k in ipairs({ "Left", "Middle", "Right", "LeftDisabled", "MiddleDisabled", "RightDisabled" }) do
      Hide(b[k])
      local n = b.GetName and b:GetName()
      if type(n) == "string" and _G then Hide(_G[n .. k]) end
    end
    for _, fn in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
      if b[fn] then
        local ok, t = pcall(b[fn], b)
        if ok then Hide(t) end
      end
    end
    -- 1px border
    local e = c.edge
    local function Line(p1, p2, w, h)
      local t = b:CreateTexture(nil, "BORDER")
      t:SetPoint(p1, b, p1, 0, 0); t:SetPoint(p2, b, p2, 0, 0)
      if w then t:SetWidth(w) end
      if h then t:SetHeight(h) end
      t:SetColorTexture(e[1], e[2], e[3], 1)
    end
    Line("TOPLEFT", "TOPRIGHT", nil, 1); Line("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    Line("TOPLEFT", "BOTTOMLEFT", 1, nil); Line("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
    local fs = b.GetFontString and b:GetFontString()
    if fs then
      if fs.SetFont then pcall(fs.SetFont, fs, UI.FONT, 12, "") end
      if fs.SetTextColor then fs:SetTextColor(c.text[1], c.text[2], c.text[3], 1) end
    end
  end
  UI.Button(b, tone or c.raised, c.blue, .28)
  return b
end
