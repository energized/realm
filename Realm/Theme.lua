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
function UI.Button(b, tone)
  local c = UI.C
  tone = tone or c.raised
  local r = fills[b]
  if not r then
    r = {}
    r.bg = b:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    r.hl = b:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints()
    fills[b] = r
  end
  r.bg:SetColorTexture(tone[1], tone[2], tone[3], 1)
  r.hl:SetColorTexture(c.red[1], c.red[2], c.red[3], .35)
end
