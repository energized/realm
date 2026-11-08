-- Realm Path: which open step to head for next.
-- The route lists steps in the order a guide would do them, but it is sorted by level, not by where things are, so doing
-- it strictly in order sends you back and forth between the same few NPCs. This picks, among the steps you can do right
-- now, the one that costs the least walking: its distance, plus a small price for every place it sits later in the guide
-- order (so the guide still decides between steps that are about equally close).
-- Travel and level-up steps are never jumped ahead to: they only come when they are first in line.
-- Pure function, no game calls, so the offline route replay and the tests run exactly the code the game runs.
local ADDON, ns = ...
local Pick = {}
ns.PathPick = Pick

Pick.RANK_COST = 25   -- yards of walking that one place later in the guide order is worth
Pick.STICK = 60       -- yards of head start for the step you are already heading to, so the compass never flip-flops

-- Route styles: how the route is built. All pure numbers so the tests and the replay can use them.
--   rankCost  yards of walking one later guide place is worth (lower = walk less, follow the guide less)
--   grey      a quest is skipped when it is this many levels or more below you (lower = drop low-xp quests sooner)
--   hi        a quest is skipped while it is more than this many levels above you (nil = no limit)
--   profs     turns the professions helper on
Pick.STYLES = {
  balanced = { name = "Balanced", rankCost = 25, grey = 8 },
  exp = { name = "EXP speed", rankCost = 12, grey = 5 },
  professions = { name = "Professions", rankCost = 25, grey = 8, profs = true },
  safe = { name = "Safe", rankCost = 40, grey = 8, hi = 3 },
}
Pick.STYLE_ORDER = { "balanced", "exp", "professions", "safe" }
function Pick.Style(key) return Pick.STYLES[key] or Pick.STYLES.balanced end

-- cands: open steps in guide order, each { i = step index to head for, d = yards from you (nil if unknown), travel = true for travel/level steps }
-- prev: the step index chosen last time (or nil)
-- opts: optional { rankCost, stick } overrides, used by the replay
-- returns the step index to head for, or nil when there are no candidates
function Pick.Choose(cands, prev, opts)
  local first = cands and cands[1]
  if not first then return nil end
  if first.travel or not first.d then return first.i end    -- the next thing is a trip or has no known position: stay in order
  local rankCost = (opts and opts.rankCost) or Pick.RANK_COST
  local stick = (opts and opts.stick) or Pick.STICK
  local best, bestScore
  for rank, c in ipairs(cands) do
    if c.d and not (c.travel and rank > 1) then
      local score = c.d + (rank - 1) * rankCost
      if prev and c.i == prev then score = score - stick end
      if not bestScore or score < bestScore then best, bestScore = c, score end
    end
  end
  return (best or first).i
end
