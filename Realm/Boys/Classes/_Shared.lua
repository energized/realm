-- TheBoys: helpers shared by the class files. Stat weights are tuned for Classic-style items
-- (spell power, attack power, % bonuses read from item text), which is what World of Warcraft: Forever uses.
local ADDON, ns = ...
local TB = ns.TB

local K = {
  SP = "ITEM_MOD_SPELL_POWER_SHORT", SD = "ITEM_MOD_SPELL_DAMAGE_DONE", HEAL = "ITEM_MOD_SPELL_HEALING_DONE",
  INT = "ITEM_MOD_INTELLECT_SHORT", SPI = "ITEM_MOD_SPIRIT_SHORT", STA = "ITEM_MOD_STAMINA_SHORT",
  STR = "ITEM_MOD_STRENGTH_SHORT", AGI = "ITEM_MOD_AGILITY_SHORT",
  AP = "ITEM_MOD_ATTACK_POWER_SHORT", RAP = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", FAP = "ITEM_MOD_FERAL_ATTACK_POWER_SHORT",
  CRIT = "ITEM_MOD_CRIT_RATING_SHORT", HIT = "ITEM_MOD_HIT_RATING_SHORT", HASTE = "ITEM_MOD_HASTE_RATING_SHORT",
  MP5 = "ITEM_MOD_MANA_REGENERATION_SHORT", DPS = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT",
  DEF = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", DODGE = "ITEM_MOD_DODGE_RATING_SHORT", PARRY = "ITEM_MOD_PARRY_RATING_SHORT",
  BLOCKV = "ITEM_MOD_BLOCK_VALUE_SHORT", ARMOR = "RESISTANCE0_NAME",
}
TB.K = K

local BASE = {
  caster = { SP = 1, SD = 1, INT = .35, SPI = .04, STA = .12, MP5 = .4, CRIT = .7, HIT = .8, HASTE = .6,
             TIP_SPELL_CRIT = 10, TIP_SPELL_HIT = 8 },
  healer = { HEAL = 1, SP = 1, INT = .45, SPI = .3, STA = .08, MP5 = 1.2, CRIT = .5, HASTE = .6, TIP_SPELL_CRIT = 6 },
  melee  = { AP = 1, STR = 2, AGI = 1, STA = .1, CRIT = .8, HIT = 1, HASTE = .8, DPS = 12, TIP_CRIT = 14, TIP_HIT = 12 },
  tank   = { STA = 1.2, ARMOR = .12, DEF = 3, DODGE = 3, PARRY = 3, BLOCKV = 1, STR = .8, AGI = 1.2, AP = .2,
             HIT = .5, DPS = 5, TIP_HIT = 6, TIP_DODGE = 14, TIP_PARRY = 14 },
  ranged = { RAP = 1, AP = 1, AGI = 2, STA = .1, INT = .15, CRIT = .8, HIT = 1, HASTE = .8, DPS = 12, TIP_CRIT = 14, TIP_HIT = 12 },
}

-- kind: caster | healer | melee | tank | ranged. over: { SP = 1.2, TIP_SCHOOL_SHADOW = .85, ... } using the short keys above
function TB.Weights(kind, over)
  local out = {}
  local function put(t) for k, v in pairs(t) do out[K[k] or k] = v end end
  put(BASE[kind])
  if over then put(over) end
  return out
end

local PRO = {
  Tailoring = { "Make cloth gear and bags.", "Gear is only useful if you wear cloth." },
  Leatherworking = { "Make leather and mail gear, armor kits and bags.", "Gear is only useful if you wear leather or mail." },
  Blacksmithing = { "Make plate and mail gear, weapons and sharpening stones.", "Heavy gear only helps heavy-armor classes." },
  Enchanting = { "Enchant your own gear and disenchant what you outgrow.", "Slow to level without items to disenchant." },
  Engineering = { "Gadgets, bombs and utility. Strong for damage and for PvP.", "Expensive to level." },
  Alchemy = { "Your own flasks, elixirs and potions. Good money.", "Needs a steady herb supply." },
  Herbalism = { "Herbs sell well and feed Alchemy. Gather while questing.", "No direct combat power." },
  Mining = { "Ore sells well and feeds Blacksmithing and Engineering.", "No direct combat power." },
  Skinning = { "Free leather for Leatherworking and easy gold while leveling.", "No direct combat power." },
}
local CRAFT_FOR = { cloth = "Tailoring", leather = "Leatherworking", mail = "Leatherworking", plate = "Blacksmithing" }

function TB.StdPro(armor, first)
  local mine = CRAFT_FOR[armor]
  local pros = {}
  local order = { "Tailoring", "Leatherworking", "Blacksmithing", "Enchanting", "Engineering", "Alchemy", "Herbalism", "Mining", "Skinning" }
  local kind = { Herbalism = "gather", Mining = "gather", Skinning = "gather" }
  for _, n in ipairs(order) do
    local p = PRO[n]
    local pr, co = p[1], p[2]
    if (n == "Tailoring" or n == "Leatherworking") and n ~= mine and not (armor == "plate" and false) then
      pr = "Mostly for selling and bags."; co = "The gear is not for you."
    end
    if n == "Blacksmithing" and armor ~= "plate" and armor ~= "mail" then pr = "Mostly for selling."; co = "The gear is not for you." end
    pros[#pros + 1] = { name = n, kind = kind[n] or "craft", pros = pr, cons = co }
  end
  pros[#pros + 1] = { name = "First Aid", kind = "secondary", pros = "Bandages heal you between fights. Everyone should have it.", cons = "" }
  pros[#pros + 1] = { name = "Cooking", kind = "secondary", pros = "Food gives stat buffs and a little bonus experience in Forever.", cons = "" }
  pros[#pros + 1] = { name = "Fishing", kind = "secondary", pros = "Feeds Cooking and makes easy gold.", cons = "" }

  local gather = (armor == "leather") and "Skinning" or "Mining"
  local builds = {}
  for _, b in ipairs(first or {}) do builds[#builds + 1] = b end
  builds[#builds + 1] = { name = mine .. " + " .. gather, goal = "Dress yourself",
    why = "Make your own " .. armor .. " gear from mats you gather yourself. Cheap and self-sufficient.", needs = { mine, gather } }
  builds[#builds + 1] = { name = "Alchemy + Herbalism", goal = "Money and consumables",
    why = "Pick your own herbs and brew your own flasks and potions. Good gold and good raid prep.", needs = { "Alchemy", "Herbalism" } }
  builds[#builds + 1] = { name = "Enchanting + " .. mine, goal = "Gear and enchants",
    why = "Craft gear and enchant it yourself. Disenchant what you outgrow.", needs = { "Enchanting", mine } }
  builds[#builds + 1] = { name = "Engineering + Mining", goal = "Damage and utility",
    why = "Mine ore for Engineering and build gadgets and bombs.", needs = { "Engineering", "Mining" } }
  builds[#builds + 1] = { name = "Mining + Herbalism", goal = "Pure gold",
    why = "Two gathering professions are the fastest way to earn gold, especially while leveling.", needs = { "Mining", "Herbalism" } }
  builds[#builds + 1] = { name = "Herbalism + Skinning", goal = "Easy leveling gold",
    why = "Gather as you quest. Always something to sell.", needs = { "Herbalism", "Skinning" } }
  return pros, builds
end

function TB.UseStdPro(def, armor, first)
  def.professions, def.proBuilds = TB.StdPro(armor, first)
end
