-- Quest automation: accept, hand in, and smart reward picking. Hold Shift to pause.
local ADDON, ns = ...
local Path = ns.Path

local function On(k) local o = Path.Opts(); return o and o[k] end
local function Held() return IsShiftKeyDown and IsShiftKeyDown() end

local function Wanted(questID, title)
  if On("offRoute") then return true end
  if questID and Path.IsRouteQuest(questID) then return true end
  if title and Path.RouteQuestByName(title) then return true end
  if On("classq") ~= false and Path.IsClassQuest and Path.IsClassQuest(questID, title) then return true end
  return false
end

-- ---------------------------------------------------------------- smart reward
-- Best upgrade for you by the gear scorer; if nothing is a clear upgrade, the one that sells for the most.
function Path.PickReward()
  local n = GetNumQuestChoices and GetNumQuestChoices() or 0
  if n <= 1 then return n, nil end
  local Gear = ns.TB and ns.TB.Gear
  local bestIdx, bestPct, why, link
  local missing = false
  local info = {}
  for i = 1, n do
    local l = GetQuestItemLink and GetQuestItemLink("choice", i)
    if not l then missing = true end
    local pct = (l and Gear and Gear.EvaluateLink) and Gear.EvaluateLink(l) or nil
    local price = 0
    if l and GetItemInfo then
      local _, _, _, _, _, _, _, _, _, _, p = GetItemInfo(l)
      if p then price = p else missing = true end
    end
    info[i] = { link = l, pct = pct, price = price }
    if pct and (not bestPct or pct > bestPct) then bestIdx, bestPct = i, pct end
  end
  if missing then return nil end                                  -- item data not loaded yet; try again shortly
  if bestIdx and bestPct >= 5 then
    return bestIdx, ("upgrade for you, about +%d%%"):format(math.floor(bestPct + .5)), info[bestIdx].link
  end
  local top, topPrice = 1, -1
  for i = 1, n do if info[i].price > topPrice then top, topPrice = i, info[i].price end end
  return top, "best vendor price", info[top].link
end

local retries = 0
local function TurnIn()
  if not On("autoTurnin") or Held() then return end
  -- hand-in covers every quest you are on; "also accept off-route quests" only governs accepting
  local n = GetNumQuestChoices and GetNumQuestChoices() or 0
  local idx = 0
  if n == 1 then idx = 1
  elseif n > 1 then
    if On("smartReward") then
      local pick, why, link = Path.PickReward()
      if pick == nil then
        retries = retries + 1
        if retries < 6 then C_Timer.After(0.4, TurnIn) return end
        pick = 1
      end
      retries = 0
      idx = pick
      if why then Path.Print("reward: " .. (link or ("choice " .. pick)) .. " (" .. why .. ")") end
    else
      return                                                      -- you choose
    end
  end
  GetQuestReward(idx)
end

-- ---------------------------------------------------------------- events
local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_ACCEPT_CONFIRM", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
  pcall(f.RegisterEvent, f, e)
end

-- other quest addons also accept and hand in on their own, which makes Realm's settings look broken: say so once
local OTHERS = { "SmartQuestAutomation", "AutoQuests", "QuickQuest" }
local function Conflicts()
  if not (On("autoAccept") or On("autoTurnin")) then return end
  local loaded = (type(C_AddOns) == "table" and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  if type(loaded) ~= "function" then return end
  local found = {}
  for _, n in ipairs(OTHERS) do if loaded(n) then found[#found + 1] = n end end
  if #found > 0 then
    Path.Print("another quest addon is also running (" .. table.concat(found, ", ") .. "). It accepts and hands in quests by itself, so Realm's route-only setting cannot limit it. Turn it off in the AddOns list to use Realm alone.")
  end
end

local function Gossip()
  if Held() then return end
  local G = C_GossipInfo
  if G and G.GetActiveQuests and On("autoTurnin") then
    for _, q in ipairs(G.GetActiveQuests() or {}) do
      if q.isComplete then G.SelectActiveQuest(q.questID) return end
    end
  end
  if G and G.GetAvailableQuests and On("autoAccept") then
    for _, q in ipairs(G.GetAvailableQuests() or {}) do
      if Wanted(q.questID, q.title) then G.SelectAvailableQuest(q.questID) return end
    end
  end
end

local function Greeting()
  if Held() then return end
  if On("autoTurnin") and GetNumActiveQuests then
    for i = 1, GetNumActiveQuests() do
      local title, complete = GetActiveTitle(i)
      if complete then SelectActiveQuest(i) return end
    end
  end
  if On("autoAccept") and GetNumAvailableQuests then
    for i = 1, GetNumAvailableQuests() do
      local title = GetAvailableTitle(i)
      if Wanted(nil, title) then SelectAvailableQuest(i) return end
    end
  end
end

f:SetScript("OnEvent", function(_, e)
  if not Path.Opts() then return end
  if e == "PLAYER_LOGIN" then C_Timer.After(8, Conflicts)
  elseif e == "GOSSIP_SHOW" then Gossip()
  elseif e == "QUEST_GREETING" then Greeting()
  elseif e == "QUEST_DETAIL" then
    if On("autoAccept") and not Held() and Wanted(GetQuestID and GetQuestID(), GetTitleText and GetTitleText()) then AcceptQuest() end
  elseif e == "QUEST_ACCEPT_CONFIRM" then
    if On("autoAccept") and not Held() and ConfirmAcceptQuest then ConfirmAcceptQuest() end
  elseif e == "QUEST_PROGRESS" then
    if On("autoTurnin") and not Held() and IsQuestCompletable and IsQuestCompletable()
       then CompleteQuest() end
  elseif e == "QUEST_COMPLETE" then
    retries = 0
    TurnIn()
  end
end)
