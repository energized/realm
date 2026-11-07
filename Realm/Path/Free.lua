-- Free mode: points the compass at quests you picked up yourself, using the game's own quest markers.
local ADDON, ns = ...
local Path = ns.Path

local cache, at = nil, 0

local function Info(i)
  local CQ = C_QuestLog
  if CQ and CQ.GetInfo then
    local ok, q = pcall(CQ.GetInfo, i)
    if ok and q then return q.questID, q.title, q.isHeader, q.isHidden end
  end
  if GetQuestLogTitle then
    local ok, title, _, _, header, _, _, _, id = pcall(GetQuestLogTitle, i)
    if ok then return id, title, header end
  end
end

local function Spot(q, hint)
  local CQ = C_QuestLog
  if CQ and CQ.GetNextWaypoint then
    local ok, m, x, y = pcall(CQ.GetNextWaypoint, q)
    if ok and m and x and x > 0 then return m, x, y end
  end
  if hint and CQ and CQ.GetQuestsOnMap then
    local ok, list = pcall(CQ.GetQuestsOnMap, hint)
    if ok and type(list) == "table" then
      for _, e in ipairs(list) do
        if e.questID == q and e.x and e.x > 0 then return hint, e.x, e.y end
      end
    end
  end
end

-- the nearest quest in your log that the compass can place. Quests the route already covers are skipped
-- unless includeRoute is set.
function Path.FreeTarget(includeRoute)
  local now = GetTime and GetTime() or 0
  if cache and cache.inc == includeRoute and now - at < 2 then return cache.o end
  local CQ = C_QuestLog
  local n = CQ and CQ.GetNumQuestLogEntries and select(1, CQ.GetNumQuestLogEntries()) or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
  local hint = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local best, bd
  for i = 1, n do
    local q, title, header, hidden = Info(i)
    if q and q > 0 and not header and not hidden then
      local m, x, y = Spot(q, hint)
      if m then
        local b, d = Path.Vector(m, x, y)
        if b and (not bd or d < bd) then
          local ready = Path.Ready(q)
          best, bd = { kind = ready and "T" or "D", p = { x, y }, m = m, title = title or ("Quest " .. q), q = q,
                       sub = ready and "Ready to hand in" or "Your own quest, from the game's quest marker" }, d
        end
      end
    end
  end
  cache, at = { inc = includeRoute, o = best }, now
  return best
end
