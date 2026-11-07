-- Party members on the compass, and /path follow <name>. Uses the Realm Party tracker's positions.
local ADDON, ns = ...
local Path = ns.Path
local UI = ns.UI

local marks, MAXM = {}, 4
local TWO_PI = math.pi * 2
local follow

local function Wrap(a) a = a % TWO_PI; if a > math.pi then a = a - TWO_PI end return a end

local function Mark(i)
  local c = _G.RealmCompass
  if not c then return end
  if marks[i] then return marks[i] end
  local m = CreateFrame("Frame", nil, c)
  m:SetSize(14, 14); m:SetFrameLevel(c:GetFrameLevel() + 3)
  m.dot = m:CreateTexture(nil, "OVERLAY"); m.dot:SetAllPoints(); m.dot:SetTexture("Interface\\AddOns\\Realm\\disc")
  m.t = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); m.t:SetPoint("CENTER")
  if m.t.SetFont then m.t:SetFont(UI.FONT, 10, "OUTLINE") end
  m.d = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); m.d:SetPoint("TOP", m, "BOTTOM", 0, 0)
  if m.d.SetFont then m.d:SetFont(UI.FONT, 10, "OUTLINE") end
  m:Hide()
  marks[i] = m
  return m
end

local function PeerColor(name, p)
  local cls = p.class
  if (not cls or cls == "") and UnitClass then local _, k = UnitClass(name); cls = k end
  local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
  if c then return c.r, c.g, c.b end
  return .8, .8, .8
end

function Path.Follow(name)
  if not name or name == "" then
    follow = nil
    local o = Path.GetOverride()
    if o and o.kind == "friend" then Path.SetOverride(nil) end
    Path.Print("not following anyone")
    return
  end
  local peers = ns.Tracker and ns.Tracker.Peers and ns.Tracker.Peers() or {}
  local found
  for n in pairs(peers) do
    if n:lower() == name:lower() or n:lower():find(name:lower(), 1, true) == 1 then found = n break end
  end
  if not found then Path.Print("no tracked party member called '" .. name .. "'. They need the Realm tracker on with location sharing.") return end
  follow = found
  Path.Print("following " .. found .. " (/path follow to stop)")
end

local f = CreateFrame("Frame")
local acc = 0
f:SetScript("OnUpdate", function(_, dt)
  acc = acc + dt
  if acc < 0.1 then return end
  acc = 0
  local c, O = _G.RealmCompass, Path.Opts()
  if not c or not O then return end
  local peers = ns.Tracker and ns.Tracker.Peers and ns.Tracker.Peers() or {}
  if follow then
    local p = peers[follow]
    if p and p.map and p.x and p.x ~= 0 then
      local o = Path.GetOverride()
      if o and o.kind == "friend" and o.title == follow then o.p[1], o.p[2], o.m = p.x, p.y, p.map
      else Path.SetOverride({ kind = "friend", p = { p.x, p.y }, m = p.map, title = follow }) end
    end
  end
  local facing = GetPlayerFacing and GetPlayerFacing()
  local n = 0
  if facing and not (issecretvalue and issecretvalue(facing)) and O.friends ~= false and c:IsShown() then
    local heading = TWO_PI - facing
    local W = c:GetWidth() or 560
    local pxPerRad = (W / 2) / math.rad(95)
    local me = UnitName and UnitName("player")
    for name, p in pairs(peers) do
      if n >= MAXM then break end
      if name ~= me and p.map and p.x and p.x ~= 0 and (GetTime() - (p.t or 0)) < 12 then
        local b, d = Path.Vector(p.map, p.x, p.y)
        if b then
          n = n + 1
          local m = Mark(n)
          if m then
            local rel = Wrap(b - heading)
            local x = math.max(-W / 2 + 10, math.min(W / 2 - 10, rel * pxPerRad))
            m:ClearAllPoints(); m:SetPoint("CENTER", c, "CENTER", x, -8)
            local r, g, bl = PeerColor(name, p)
            m.dot:SetVertexColor(r, g, bl, .95)
            m.t:SetText(name:sub(1, 1):upper()); m.t:SetTextColor(0, 0, 0)
            m.d:SetText(d >= 1000 and string.format("%.1fk", d / 1000) or tostring(math.floor(d + .5)))
            m.d:SetTextColor(r, g, bl)
            m:Show()
          end
        end
      end
    end
  end
  for i = n + 1, #marks do marks[i]:Hide() end
end)

local old = Path.SlashExtra
function Path.SlashExtra(cmd, rest)
  if cmd == "follow" then Path.Follow(rest) return true end
  if old then return old(cmd, rest) end
end
