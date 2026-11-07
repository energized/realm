-- TheBoys: profession advice. Reads your professions and recommends partners.
local ADDON, ns = ...
local TB = ns.TB
local Prof = {}
TB.Professions = Prof

-- returns a set of lower-case profession names the player has
function Prof.Mine()
  local have, list = {}, {}
  local function add(name)
    if name and name ~= "" and not have[name:lower()] then
      have[name:lower()] = true; list[#list + 1] = name
    end
  end
  if GetProfessions and GetProfessionInfo then
    local ok, a, b, c, d, e = pcall(GetProfessions)
    if ok then
      for _, idx in ipairs({ a, b, c, d, e }) do
        if idx then
          local ok2, name = pcall(GetProfessionInfo, idx)
          if ok2 then add(name) end
        end
      end
    end
  end
  if #list == 0 and GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, isHeader = GetSkillLineInfo(i)
      if name and not isHeader then add(name) end
    end
  end
  return have, list
end

local function Find(class, name)
  for _, p in ipairs(class.professions or {}) do
    if p.name:lower() == name:lower() then return p end
  end
end

-- Lines for the window: {"h",text} | {"t",text} | {"row",title,desc,good}
function Prof.Lines()
  local class = TB.Class()
  local out = {}
  if not class then return out end
  local have, list = Prof.Mine()

  out[#out + 1] = { "h", "Your professions" }
  if #list == 0 then
    out[#out + 1] = { "t", "None detected. Either you have not picked any yet, or this client hides them. The plans below still apply." }
  else
    for _, n in ipairs(list) do
      local p = Find(class, n)
      if p then
        local d = p.pros
        if p.cons and p.cons ~= "" then d = d .. "  |cff9a9aaeTradeoff:|r " .. p.cons end
        out[#out + 1] = { "row", n, d, true }
      else
        out[#out + 1] = { "row", n, "", true }
      end
    end
  end

  out[#out + 1] = { "h", "Best fit for you" }
  local any = false
  for _, b in ipairs(class.proBuilds or {}) do
    local owned = 0
    for _, n in ipairs(b.needs) do if have[n:lower()] then owned = owned + 1 end end
    if owned == #b.needs then
      out[#out + 1] = { "row", "You already run " .. b.name, b.why, true }; any = true
    elseif owned == 1 then
      local missing
      for _, n in ipairs(b.needs) do if not have[n:lower()] then missing = n end end
      out[#out + 1] = { "row", "Add " .. missing .. "  >  " .. b.name, b.goal .. ". " .. b.why }; any = true
    end
  end
  if not any then out[#out + 1] = { "t", "Pick two from the plans below." } end

  out[#out + 1] = { "h", "All plans for " .. class.name }
  for _, b in ipairs(class.proBuilds or {}) do
    out[#out + 1] = { "row", b.name .. "  |cff9a9aae" .. b.goal .. "|r", b.why }
  end

  out[#out + 1] = { "h", "Every profession" }
  for _, p in ipairs(class.professions or {}) do
    local tag = (p.kind == "gather" and "gathering") or (p.kind == "secondary" and "secondary") or "crafting"
    local d = p.pros
    if p.cons and p.cons ~= "" then d = d .. "  |cff9a9aaeTradeoff:|r " .. p.cons end
    out[#out + 1] = { "row", p.name .. "  |cff9a9aae" .. tag .. "|r", d }
  end

  out[#out + 1] = { "t", "General guidance. Recipes, bonuses and what sells best change with the game version, so check your profession window for what your version offers." }
  return out
end
